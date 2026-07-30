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

  def app
    GithubWebhooks::App
  end

  def setup
    super
    @handler = RecordingHandler.new
    install_handler(@handler)
  end

  def install_handler(handler)
    GithubWebhooks::App.repository_handler = handler
    # Run the job on this thread so assertions see its effects.
    GithubWebhooks::App.executor = GithubWebhooks::App::INLINE_EXECUTOR
  end

  def deliver(event, payload)
    post '/github_webhook', JSON.generate(payload),
         'CONTENT_TYPE' => 'application/json',
         'HTTP_X_GITHUB_EVENT' => event
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
    post '/github_webhook', JSON.generate('action' => 'created'),
         'CONTENT_TYPE' => 'application/json'

    assert_equal 200, last_response.status
    assert_logged(/Ignoring object = unknown/)
  end

  def test_rejects_unparseable_json
    post '/github_webhook', 'not json at all', 'CONTENT_TYPE' => 'application/json',
                                               'HTTP_X_GITHUB_EVENT' => 'repository'

    assert_equal 400, last_response.status
    assert_empty @handler.payloads
    assert_logged(/unparseable JSON/)
  end

  def test_rejects_a_json_body_that_is_not_an_object
    post '/github_webhook', '["a","b"]', 'CONTENT_TYPE' => 'application/json',
                                         'HTTP_X_GITHUB_EVENT' => 'repository'

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
