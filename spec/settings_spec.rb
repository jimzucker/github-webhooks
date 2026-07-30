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

  def test_loads_the_github_token
    with_properties("githubToken=abc123\n") do |path|
      assert_equal 'abc123', GithubWebhooks::Settings.load(path).github_token
    end
  end

  def test_raises_when_the_file_is_missing
    error = assert_raises(GithubWebhooks::ConfigurationError) do
      GithubWebhooks::Settings.load('/nonexistent/.webhook_properties')
    end

    assert_match(/java style properties file/, error.message)
  end

  def test_raises_when_the_token_is_absent
    with_properties("somethingElse=x\n") do |path|
      assert_raises(GithubWebhooks::ConfigurationError) { GithubWebhooks::Settings.load(path) }
    end
  end

  def test_raises_when_the_token_is_blank
    with_properties("githubToken=   \n") do |path|
      assert_raises(GithubWebhooks::ConfigurationError) { GithubWebhooks::Settings.load(path) }
    end
  end
end
