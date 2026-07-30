# frozen_string_literal: true

module GithubWebhooks
  # Base for every error this app raises deliberately.
  class Error < StandardError; end

  # Raised at boot when .webhook_properties is missing or has no token. Fatal by
  # design -- there is nothing useful the server can do without credentials.
  class ConfigurationError < Error; end

  # Raised when the GitHub API answers with an unexpected status.
  #
  # Handled per request and never fatal. The previous implementation called
  # exit(1) on any API failure, from inside the request path, which took the
  # whole Puma process down mid-webhook.
  class ApiError < Error
    attr_reader :code, :body, :url

    def initialize(message, code: nil, body: nil, url: nil)
      super(message)
      @code = code
      @body = body
      @url = url
    end
  end
end
