# frozen_string_literal: true

require 'tempfile'

require_relative 'spec_helper'

class SettingsSpec < SpecCase
  def with_properties(contents)
    Tempfile.create('webhook_properties') do |file|
      file.write(contents)
      file.flush
      yield file.path
    end
  end

  VALID = "githubToken=abc123\nwebhookSecret=s3cr3t\n"

  def test_loads_the_github_token_and_webhook_secret
    with_properties(VALID) do |path|
      settings = GithubWebhooks::Settings.load(path)

      assert_equal 'abc123', settings.github_token
      assert_equal 's3cr3t', settings.webhook_secret
    end
  end

  def test_raises_when_the_file_is_missing
    error = assert_raises(GithubWebhooks::ConfigurationError) do
      GithubWebhooks::Settings.load('/nonexistent/.webhook_properties')
    end

    assert_match(/java style properties file/, error.message)
  end

  def test_raises_when_the_token_is_absent
    with_properties("webhookSecret=s3cr3t\n") do |path|
      assert_raises(GithubWebhooks::ConfigurationError) { GithubWebhooks::Settings.load(path) }
    end
  end

  def test_raises_when_the_token_is_blank
    with_properties("githubToken=   \nwebhookSecret=s3cr3t\n") do |path|
      assert_raises(GithubWebhooks::ConfigurationError) { GithubWebhooks::Settings.load(path) }
    end
  end

  # Fail closed: booting without a secret would leave the endpoint open.
  def test_raises_when_the_webhook_secret_is_absent
    with_properties("githubToken=abc123\n") do |path|
      error = assert_raises(GithubWebhooks::ConfigurationError) do
        GithubWebhooks::Settings.load(path)
      end

      assert_match(/webhookSecret is missing/, error.message)
    end
  end

  def test_raises_when_the_webhook_secret_is_blank
    with_properties("githubToken=abc123\nwebhookSecret=  \n") do |path|
      assert_raises(GithubWebhooks::ConfigurationError) { GithubWebhooks::Settings.load(path) }
    end
  end
end
