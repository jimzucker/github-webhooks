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

    attr_reader :github_token, :webhook_secret

    def self.load(path = DEFAULT_PATH)
      unless File.exist?(path)
        raise ConfigurationError,
              "You must have a java style properties file #{path} with " \
              'githubToken=xx and webhookSecret=xx defined'
      end

      new(JavaProperties.load(path))
    end

    def initialize(properties)
      @github_token = presence(properties[:githubToken])
      @webhook_secret = presence(properties[:webhookSecret])

      raise ConfigurationError, 'githubToken is missing or empty in the properties file' if @github_token.nil?
      return unless @webhook_secret.nil?

      # Fail closed. Without a secret the endpoint would accept anything from
      # anyone and act on it with a privileged token, which is the whole reason
      # this check exists.
      raise ConfigurationError,
            'webhookSecret is missing or empty in the properties file. Set the same ' \
            "value here and in the webhook's Secret field in GitHub."
    end

    private

    def presence(value)
      string = value.to_s.strip
      string.empty? ? nil : string
    end
  end
end
