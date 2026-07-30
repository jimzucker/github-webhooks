# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

require_relative 'errors'
require_relative 'log'

module GithubWebhooks
  # Thin Net::HTTP wrapper around the GitHub REST API.
  #
  # Unexpected statuses raise ApiError. They used to call exit(1), which killed
  # the server; callers that legitimately expect a failure (probing whether a
  # README exists, say) pass allow_failure: true and inspect the code.
  class GithubClient
    API_ROOT = 'https://api.github.com/'

    # Required for the branch-protection endpoints; sent on every request, as
    # the original did.
    PREVIEW_ACCEPT = 'application/vnd.github.luke-cage-preview+json'

    REQUEST_CLASSES = {
      get: Net::HTTP::Get,
      patch: Net::HTTP::Patch,
      post: Net::HTTP::Post,
      put: Net::HTTP::Put
    }.freeze

    Response = Struct.new(:code, :body, keyword_init: true) do
      def json
        JSON.parse(body.to_s)
      end
    end

    def initialize(token:, api_root: API_ROOT)
      @token = token
      @api_root = api_root
    end

    def get(path, expect: '200', allow_failure: false, message: nil)
      request(:get, path, expect: expect, allow_failure: allow_failure, message: message)
    end

    def patch(path, body, expect: '200', allow_failure: false, message: nil)
      request(:patch, path, body: body, expect: expect, allow_failure: allow_failure, message: message)
    end

    def post(path, body, expect: '201', allow_failure: false, message: nil)
      request(:post, path, body: body, expect: expect, allow_failure: allow_failure, message: message)
    end

    def put(path, body, expect: '200', allow_failure: false, message: nil)
      request(:put, path, body: body, expect: expect, allow_failure: allow_failure, message: message)
    end

    private

    def request(method, path, body: nil, expect: '200', allow_failure: false, message: nil)
      request_class = REQUEST_CLASSES.fetch(method) do
        raise ArgumentError, "unknown method: #{method}"
      end

      url = @api_root + path
      Log.info("#{message || 'GitHub API'}:  method= #{method.to_s.capitalize}, url= #{url}")

      uri = URI(url)
      net_request = build_request(request_class, uri, body)
      raw = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(net_request)
      end

      response = Response.new(code: raw.code, body: raw.body)
      return response if allow_failure || response.code == expect

      raise ApiError.new(
        "GitHub API returned #{response.code} (expected #{expect}) for #{method.to_s.upcase} #{url}",
        code: response.code, body: response.body, url: url
      )
    end

    def build_request(request_class, uri, body)
      request = request_class.new(uri)
      request['Authorization'] = "token #{@token}"
      request['Content-Type'] = 'application/json'
      request['Accept'] = PREVIEW_ACCEPT
      request.body = body unless body.nil?
      request
    end
  end
end
