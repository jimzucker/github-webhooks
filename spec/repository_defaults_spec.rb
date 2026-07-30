# frozen_string_literal: true

require_relative 'spec_helper'

class RepositoryDefaultsSpec < SpecCase
  USER_JSON = '{"login":"jimzucker","name":"Jim Zucker","email":"jim@example.com"}'

  def setup
    super
    @client = GithubWebhooks::GithubClient.new(token: 'test-token')
    # poll_interval: 0 keeps the README wait from actually sleeping.
    @defaults = GithubWebhooks::RepositoryDefaults.new(
      client: @client, config_dir: 'config', poll_attempts: 3, poll_interval: 0
    )
  end

  def stub_user(body: USER_JSON)
    stub_request(:get, 'https://api.github.com/user').to_return(status: 200, body: body)
  end

  def stub_readme_present(full_name = 'acme/demo')
    stub_request(:get, "https://api.github.com/repos/#{full_name}/contents/README.md")
      .to_return(status: 200, body: '{}')
  end

  def stub_settings_and_issue(full_name = 'acme/demo')
    stub_request(:patch, "https://api.github.com/repos/#{full_name}").to_return(status: 200, body: '{}')
    stub_request(:post, "https://api.github.com/repos/#{full_name}/issues")
      .to_return(status: 201, body: '{}')
  end

  def payload(repository)
    { 'action' => 'created', 'repository' => repository, 'sender' => { 'login' => 'jimzucker' } }
  end

  # Stubs a request and returns an array that collects the bodies sent to it, so
  # assertions can run after the call rather than inside a webmock matcher.
  def capture_bodies(method, url, status:, body: '{}')
    captured = []
    stub_request(method, url)
      .with { |request| captured << request.body; true }
      .to_return(status: status, body: body)
    captured
  end

  # The old code hardcoded branches/master/protection, which 404s on any repo
  # created since GitHub switched the default to main.
  def test_protects_the_default_branch_from_the_payload
    stub_user
    stub_readme_present
    stub_settings_and_issue
    protect = stub_request(:put, 'https://api.github.com/repos/acme/demo/branches/main/protection')
              .to_return(status: 200, body: '{}')

    @defaults.call(payload('full_name' => 'acme/demo', 'default_branch' => 'main'))

    assert_requested protect
  end

  def test_still_works_for_repositories_whose_default_branch_is_master
    stub_user
    stub_readme_present
    stub_settings_and_issue
    protect = stub_request(:put, 'https://api.github.com/repos/acme/demo/branches/master/protection')
              .to_return(status: 200, body: '{}')

    @defaults.call(payload('full_name' => 'acme/demo', 'default_branch' => 'master'))

    assert_requested protect
  end

  def test_looks_up_the_default_branch_when_the_payload_omits_it
    stub_user
    stub_readme_present
    stub_settings_and_issue
    lookup = stub_request(:get, 'https://api.github.com/repos/acme/demo')
             .to_return(status: 200, body: '{"default_branch":"trunk"}')
    protect = stub_request(:put, 'https://api.github.com/repos/acme/demo/branches/trunk/protection')
              .to_return(status: 200, body: '{}')

    @defaults.call(payload('full_name' => 'acme/demo'))

    assert_requested lookup
    assert_requested protect
  end

  def test_falls_back_to_main_when_the_branch_cannot_be_determined
    stub_user
    stub_readme_present
    stub_settings_and_issue
    stub_request(:get, 'https://api.github.com/repos/acme/demo').to_return(status: 404, body: '{}')
    protect = stub_request(:put, 'https://api.github.com/repos/acme/demo/branches/main/protection')
              .to_return(status: 200, body: '{}')

    @defaults.call(payload('full_name' => 'acme/demo'))

    assert_requested protect
  end

  # The original sent the committer under a "sender_login" key the contents API
  # ignores, and put the user's *name* in the email field.
  def test_creates_a_readme_with_a_correctly_shaped_committer
    stub_user
    stub_request(:get, 'https://api.github.com/repos/acme/demo/contents/README.md')
      .to_return({ status: 404, body: '{}' }, { status: 200, body: '{}' })
    stub_settings_and_issue
    stub_request(:put, 'https://api.github.com/repos/acme/demo/branches/main/protection')
      .to_return(status: 200, body: '{}')
    created = capture_bodies(:put, 'https://api.github.com/repos/acme/demo/contents/README.md',
                             status: 201)

    @defaults.call(payload('full_name' => 'acme/demo', 'default_branch' => 'main'))

    body = JSON.parse(created.last)
    assert_equal 'Jim Zucker', body.dig('committer', 'name')
    assert_equal 'jim@example.com', body.dig('committer', 'email')
    assert_nil body['sender_login'], 'sender_login is not a key the contents API understands'
    assert_equal '# acme/demo', Base64.strict_decode64(body['content'])
  end

  def test_omits_the_committer_and_warns_when_the_primary_email_is_private
    stub_user(body: '{"login":"jimzucker","name":"Jim Zucker","email":null}')
    stub_request(:get, 'https://api.github.com/repos/acme/demo/contents/README.md')
      .to_return({ status: 404, body: '{}' }, { status: 200, body: '{}' })
    stub_settings_and_issue
    stub_request(:put, 'https://api.github.com/repos/acme/demo/branches/main/protection')
      .to_return(status: 200, body: '{}')
    created = capture_bodies(:put, 'https://api.github.com/repos/acme/demo/contents/README.md',
                             status: 201)

    # Used to exit(1) and take the server down.
    @defaults.call(payload('full_name' => 'acme/demo', 'default_branch' => 'main'))

    assert_nil JSON.parse(created.last)['committer']
    assert_logged(/\[WARN\] Primary email address is not public/)
  end

  # The original interpolated these straight into a JSON string literal.
  def test_generates_valid_json_when_values_contain_quotes
    stub_user(body: JSON.generate('login' => 'jim"z', 'name' => 'Jim "JZ" Zucker',
                                  'email' => 'jim@example.com'))
    stub_readme_present
    stub_request(:patch, 'https://api.github.com/repos/acme/demo').to_return(status: 200, body: '{}')
    stub_request(:put, 'https://api.github.com/repos/acme/demo/branches/main/protection')
      .to_return(status: 200, body: '{}')
    issues = capture_bodies(:post, 'https://api.github.com/repos/acme/demo/issues', status: 201)

    @defaults.call(payload('full_name' => 'acme/demo', 'default_branch' => 'main'))

    body = JSON.parse(issues.last) # would raise on the old interpolated string
    assert_includes body['body'], 'jim"z'
    assert_includes body['title'], 'main'
  end

  def test_reports_the_branch_name_in_the_summary_issue
    stub_user
    stub_readme_present
    stub_request(:patch, 'https://api.github.com/repos/acme/demo').to_return(status: 200, body: '{}')
    stub_request(:put, 'https://api.github.com/repos/acme/demo/branches/trunk/protection')
      .to_return(status: 200, body: '{}')
    issues = capture_bodies(:post, 'https://api.github.com/repos/acme/demo/issues', status: 201)

    @defaults.call(payload('full_name' => 'acme/demo', 'default_branch' => 'trunk'))

    assert_includes JSON.parse(issues.last)['body'], 'protected the trunk branch'
  end

  def test_raises_when_the_payload_has_no_repository
    assert_raises(ArgumentError) { @defaults.call('action' => 'created') }
  end

  def test_propagates_api_errors_so_the_caller_can_log_them
    stub_request(:get, 'https://api.github.com/user').to_return(status: 401, body: '{}')

    assert_raises(GithubWebhooks::ApiError) do
      @defaults.call(payload('full_name' => 'acme/demo', 'default_branch' => 'main'))
    end
  end
end
