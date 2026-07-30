# frozen_string_literal: true

require 'java-properties'

require_relative 'errors'

module GithubWebhooks
  # Loads .webhook_properties once at boot.
  #
  # The previous implementation re-read and re-parsed this file on every single
  # API call, and called exit(1) from inside the request path if it had gone
  # missing.
  class Settings
    DEFAULT_PATH = '.webhook_properties'

    attr_reader :github_token

    def self.load(path = DEFAULT_PATH)
      unless File.exist?(path)
        raise ConfigurationError,
              "You must have a java style properties file #{path} with githubToken=xx defined"
      end

      new(JavaProperties.load(path))
    end

    def initialize(properties)
      @github_token = presence(properties[:githubToken])

      return unless @github_token.nil?

      raise ConfigurationError, 'githubToken is missing or empty in the properties file'
    end

    private

    def presence(value)
      string = value.to_s.strip
      string.empty? ? nil : string
    end
  end
end
