# frozen_string_literal: true

require_relative 'spec_helper'

class GithubClientSpec < SpecCase
  def setup
    super
    @client = GithubWebhooks::GithubClient.new(token: 'test-token')
  end

  def test_sends_the_documented_auth_and_accept_headers
    stub = stub_request(:get, 'https://api.github.com/user')
           .with(headers: {
                   'Authorization' => 'token test-token',
                   'Content-Type' => 'application/json',
                   'Accept' => GithubWebhooks::GithubClient::PREVIEW_ACCEPT
                 })
           .to_return(status: 200, body: '{"login":"jimzucker"}')

    assert_equal 'jimzucker', @client.get('user').json['login']
    assert_requested stub
  end

  def test_raises_api_error_on_an_unexpected_status
    stub_request(:get, 'https://api.github.com/user')
      .to_return(status: 401, body: '{"message":"Bad credentials"}')

    error = assert_raises(GithubWebhooks::ApiError) { @client.get('user') }

    assert_equal '401', error.code
    assert_match(/returned 401 \(expected 200\)/, error.message)
    assert_match(/Bad credentials/, error.body)
  end

  # Callers that legitimately probe for a 404 (does this README exist?) must be
  # able to do so without an exception.
  def test_allow_failure_returns_the_response_instead_of_raising
    stub_request(:get, 'https://api.github.com/repos/acme/demo/contents/README.md')
      .to_return(status: 404, body: '{}')

    response = @client.get('repos/acme/demo/contents/README.md', allow_failure: true)

    assert_equal '404', response.code
  end

  def test_put_sends_the_body_through_unchanged
    stub = stub_request(:put, 'https://api.github.com/repos/acme/demo/contents/README.md')
           .with(body: '{"message":"hi"}')
           .to_return(status: 201, body: '{}')

    @client.put('repos/acme/demo/contents/README.md', '{"message":"hi"}', expect: '201')

    assert_requested stub
  end

  def test_rejects_an_unsupported_http_method
    assert_raises(ArgumentError) { @client.send(:request, :delete, 'user') }
  end

  def test_logs_the_call_without_leaking_the_token
    stub_request(:get, 'https://api.github.com/user').to_return(status: 200, body: '{}')

    @client.get('user', message: 'Getting Authorized User')

    assert_logged(%r{\[INFO\] Getting Authorized User:\s+method= Get, url= https://api\.github\.com/user})
    refute_logged(/test-token/)
  end
end
