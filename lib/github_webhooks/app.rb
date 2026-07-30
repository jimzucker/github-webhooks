# frozen_string_literal: true

require 'json'
require 'sinatra/base'

require_relative 'errors'
require_relative 'github_client'
require_relative 'log'
require_relative 'repository_defaults'
require_relative 'settings'

module GithubWebhooks
  class App < Sinatra::Base
    # GitHub gives a webhook 10 seconds to respond and records anything slower as
    # a failed delivery. Repository setup takes longer than that -- it has to wait
    # for the new repo to be initialized before branch protection will apply -- so
    # the request is acknowledged immediately and the work runs off-thread.
    #
    # The tradeoff: in-flight work is lost if the process restarts. That is
    # strictly better than the previous behavior, where a sleep(30) in the handler
    # guaranteed every delivery timed out.
    DEFAULT_EXECUTOR = ->(job) { Thread.new { job.call } }

    # Synchronous alternative, used by the specs.
    INLINE_EXECUTOR = ->(job) { job.call }

    # Deliberately plain class accessors rather than Sinatra's `set`: `set` treats
    # a Proc value as a lazily-computed setting and invokes it on read, so an
    # executor lambda stored that way gets called with no arguments.
    class << self
      attr_accessor :executor, :repository_handler
    end

    self.executor = DEFAULT_EXECUTOR
    self.repository_handler = nil

    # Errors are logged and converted to a status code; never leak a stack trace
    # to a webhook sender, and never let one escape to Puma.
    set :show_exceptions, false
    set :raise_errors, false

    # Wires up the real GitHub client. Specs inject a double instead.
    def self.configure!(settings, executor: DEFAULT_EXECUTOR)
      client = GithubClient.new(token: settings.github_token)
      self.repository_handler = RepositoryDefaults.new(client: client)
      self.executor = executor
      self
    end

    post '/github_webhook' do
      payload = parse_payload
      # The event name comes from the X-GitHub-Event header, which is what GitHub
      # actually documents. The old code read payload.keys[1], so it depended on
      # JSON key ordering and misrouted whenever GitHub reordered the payload.
      event = request.env['HTTP_X_GITHUB_EVENT'].to_s
      action = payload['action'].to_s

      unless handled?(event, action)
        Log.info("Ignoring object = #{event.empty? ? 'unknown' : event}, action = #{action}")
        status 200
        return ''
      end

      process_later(event, action, payload)
      status 202
      ''
    end

    private

    def handled?(event, action)
      event == 'repository' && action == 'created'
    end

    def parse_payload
      body = request.body.read
      parsed = JSON.parse(body.to_s)
      halt 400, 'expected a JSON object' unless parsed.is_a?(Hash)
      parsed
    rescue JSON::ParserError => e
      Log.error("Rejecting webhook with unparseable JSON body: #{e.message}")
      halt 400, 'invalid JSON'
    end

    def process_later(event, action, payload)
      handler = self.class.repository_handler
      if handler.nil?
        Log.error('No repository handler configured; dropping event')
        return
      end

      self.class.executor.call(lambda do
        # An exception raised inside a Thread is silent by default, so every
        # failure has to be caught and logged here.
        begin
          handler.call(payload)
        rescue ApiError => e
          Log.error("GitHub API error processing #{event}/#{action}: #{e.message}")
        rescue StandardError => e
          Log.error("Unhandled error processing #{event}/#{action}: #{e.class}: #{e.message}")
        end
      end)
    end
  end
end
