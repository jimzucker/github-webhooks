# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'stringio'

require 'minitest/autorun'
require 'rack/test'
require 'webmock/minitest'

require_relative '../lib/github_webhooks/app'

module LogCapture
  def setup
    super
    @log_output = StringIO.new
    GithubWebhooks::Log.out = @log_output
  end

  def teardown
    GithubWebhooks::Log.out = $stdout
    super
  end

  def log_text
    @log_output.string
  end

  def assert_logged(pattern, message = nil)
    assert_match pattern, log_text, message || "expected #{pattern.inspect} in the log output"
  end

  def refute_logged(pattern, message = nil)
    refute_match pattern, log_text, message || "did not expect #{pattern.inspect} in the log output"
  end
end

class SpecCase < Minitest::Test
  include LogCapture

  # Minitest::Test treats any subclass with no test_ methods as fine, but this
  # base class itself should never be collected as a suite.
  def self.runnable_methods
    self == SpecCase ? [] : super
  end
end
