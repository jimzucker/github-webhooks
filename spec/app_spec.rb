# frozen_string_literal: true

require_relative 'spec_helper'

# Records what it was handed instead of calling GitHub.
class RecordingHandler
  attr_reader :payloads

  def initialize(&raiser)
    @payloads = []
    @raiser = raiser
  end

  def call(payload)
    @payloads << payload
    @raiser&.call
  end
end

class AppSpec < SpecCase
  include Rack::Test::Methods

  SECRET = 'test-webhook-secret'

  def app
    GithubWebhooks::App
  end

  def setup
    super
    @handler = RecordingHandler.new
    install_handler(@handler)
    GithubWebhooks::App.webhook_secret = SECRET
  end

  def teardown
    GithubWebhooks::App.webhook_secret = nil
    super
  end

  def install_handler(handler)
    GithubWebhooks::App.repository_handler = handler
    # Run the job on this thread so assertions see its effects.
    GithubWebhooks::App.executor = GithubWebhooks::App::INLINE_EXECUTOR
  end

  def signature_for(body, secret: SECRET)
    "sha256=#{OpenSSL::HMAC.hexdigest('sha256', secret, body)}"
  end

  # Posts a correctly signed request, the way GitHub would.
  def deliver(event, payload, headers = {})
    body = JSON.generate(payload)
    send_raw(body, { 'HTTP_X_GITHUB_EVENT' => event,
                     'HTTP_X_HUB_SIGNATURE_256' => signature_for(body) }.merge(headers))
  end

  def send_raw(body, headers = {})
    post '/github_webhook', body, { 'CONTENT_TYPE' => 'application/json' }.merge(headers)
  end

  def test_acknowledges_repository_created_with_202_and_runs_the_handler
    deliver('repository', 'action' => 'created',
                          'repository' => { 'full_name' => 'acme/demo', 'default_branch' => 'main' })

    assert_equal 202, last_response.status
    assert_equal 1, @handler.payloads.length
    assert_equal 'acme/demo', @handler.payloads.first.dig('repository', 'full_name')
  end

  def test_ignores_repository_actions_other_than_created
    deliver('repository', 'action' => 'deleted', 'repository' => { 'full_name' => 'acme/demo' })

    assert_equal 200, last_response.status
    assert_empty @handler.payloads
    assert_logged(/\[INFO\] Ignoring object = repository, action = deleted/)
  end

  def test_ignores_events_it_does_not_handle
    deliver('organization', 'action' => 'created', 'organization' => { 'login' => 'acme' })

    assert_equal 200, last_response.status
    assert_empty @handler.payloads
    assert_logged(/\[INFO\] Ignoring object = organization, action = created/)
  end

  # The old code took the event name from payload.keys[1], so a payload whose
  # second key happened to be "repository" was treated as a repository event no
  # matter what GitHub actually sent.
  def test_dispatches_on_the_header_not_on_json_key_order
    deliver('organization', 'action' => 'created',
                            'repository' => { 'full_name' => 'acme/demo' },
                            'organization' => { 'login' => 'acme' })

    assert_equal 200, last_response.status
    assert_empty @handler.payloads, 'must not dispatch on payload key ordering'
  end

  def test_missing_event_header_is_ignored_rather_than_crashing
    body = JSON.generate('action' => 'created')
    send_raw(body, 'HTTP_X_HUB_SIGNATURE_256' => signature_for(body))

    assert_equal 200, last_response.status
    assert_logged(/Ignoring object = unknown/)
  end

  def test_rejects_unparseable_json
    send_raw('not json at all',
             'HTTP_X_GITHUB_EVENT' => 'repository',
             'HTTP_X_HUB_SIGNATURE_256' => signature_for('not json at all'))

    assert_equal 400, last_response.status
    assert_empty @handler.payloads
    assert_logged(/unparseable JSON/)
  end

  def test_rejects_a_json_body_that_is_not_an_object
    send_raw('["a","b"]',
             'HTTP_X_GITHUB_EVENT' => 'repository',
             'HTTP_X_HUB_SIGNATURE_256' => signature_for('["a","b"]'))

    assert_equal 400, last_response.status
  end

  # Regression test for the exit(1)-in-the-request-path bug: a failing GitHub
  # call used to terminate the whole Puma process. It must now be logged and
  # contained.
  def test_a_failing_handler_does_not_escape_or_change_the_response
    install_handler(RecordingHandler.new do
      raise GithubWebhooks::ApiError.new('boom', code: '401', url: 'https://api.github.com/user')
    end)

    deliver('repository', 'action' => 'created', 'repository' => { 'full_name' => 'acme/demo' })

    assert_equal 202, last_response.status
    assert_logged(/\[ERROR\] GitHub API error processing repository\/created: boom/)
  end

  def test_an_unexpected_handler_error_is_also_contained
    install_handler(RecordingHandler.new { raise 'totally unexpected' })

    deliver('repository', 'action' => 'created', 'repository' => { 'full_name' => 'acme/demo' })

    assert_equal 202, last_response.status
    assert_logged(/\[ERROR\] Unhandled error processing repository\/created: RuntimeError/)
  end

  def test_unknown_routes_are_404
    get '/nope'

    assert_equal 404, last_response.status
  end
end

# Before this existed, anyone who learned the URL could drive privileged calls
# against the stored GitHub token.
class SignatureVerificationSpec < SpecCase
  include Rack::Test::Methods

  SECRET = 'test-webhook-secret'
  PAYLOAD = '{"action":"created","repository":{"full_name":"acme/demo"}}'

  def app
    GithubWebhooks::App
  end

  def setup
    super
    @handler = RecordingHandler.new
    GithubWebhooks::App.repository_handler = @handler
    GithubWebhooks::App.executor = GithubWebhooks::App::INLINE_EXECUTOR
    GithubWebhooks::App.webhook_secret = SECRET
  end

  def teardown
    GithubWebhooks::App.webhook_secret = nil
    super
  end

  def signature_for(body, secret: SECRET)
    "sha256=#{OpenSSL::HMAC.hexdigest('sha256', secret, body)}"
  end

  def deliver(body, headers = {})
    post '/github_webhook', body,
         { 'CONTENT_TYPE' => 'application/json',
           'HTTP_X_GITHUB_EVENT' => 'repository' }.merge(headers)
  end

  def test_accepts_a_correctly_signed_request
    deliver(PAYLOAD, 'HTTP_X_HUB_SIGNATURE_256' => signature_for(PAYLOAD))

    assert_equal 202, last_response.status
    assert_equal 1, @handler.payloads.length
  end

  def test_rejects_a_request_with_no_signature
    deliver(PAYLOAD)

    assert_equal 401, last_response.status
    assert_empty @handler.payloads
    assert_logged(/no X-Hub-Signature-256 header/)
  end

  def test_rejects_a_garbage_signature
    deliver(PAYLOAD, 'HTTP_X_HUB_SIGNATURE_256' => 'sha256=deadbeef')

    assert_equal 401, last_response.status
    assert_empty @handler.payloads
    assert_logged(/invalid X-Hub-Signature-256/)
  end

  def test_rejects_a_signature_computed_with_the_wrong_secret
    deliver(PAYLOAD, 'HTTP_X_HUB_SIGNATURE_256' => signature_for(PAYLOAD, secret: 'not-the-secret'))

    assert_equal 401, last_response.status
    assert_empty @handler.payloads
  end

  # The signature must cover the bytes actually delivered, not some other body.
  def test_rejects_a_tampered_body
    tampered = PAYLOAD.sub('acme/demo', 'attacker/evil')

    deliver(tampered, 'HTTP_X_HUB_SIGNATURE_256' => signature_for(PAYLOAD))

    assert_equal 401, last_response.status
    assert_empty @handler.payloads
  end

  # GitHub still sends the legacy SHA-1 header; accepting it would undo the point.
  def test_rejects_a_request_carrying_only_the_legacy_sha1_header
    sha1 = "sha1=#{OpenSSL::HMAC.hexdigest('sha1', SECRET, PAYLOAD)}"

    deliver(PAYLOAD, 'HTTP_X_HUB_SIGNATURE' => sha1)

    assert_equal 401, last_response.status
    assert_empty @handler.payloads
  end

  def test_never_logs_the_secret_or_the_expected_signature
    deliver(PAYLOAD, 'HTTP_X_HUB_SIGNATURE_256' => 'sha256=deadbeef')

    refute_logged(/#{SECRET}/)
    refute_logged(/#{OpenSSL::HMAC.hexdigest('sha256', SECRET, PAYLOAD)}/)
  end

  # Belt and braces: Settings refuses to boot without a secret, but the request
  # path must not fail open either.
  def test_refuses_to_process_when_no_secret_is_configured
    GithubWebhooks::App.webhook_secret = nil

    deliver(PAYLOAD, 'HTTP_X_HUB_SIGNATURE_256' => signature_for(PAYLOAD))

    assert_equal 500, last_response.status
    assert_empty @handler.payloads
    assert_logged(/No webhook secret configured/)
  end
end
