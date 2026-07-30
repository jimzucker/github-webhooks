# frozen_string_literal: true

# Rack entry point, for running under any Rack server:
#
#   bundle exec rackup
#
# The Dockerfile uses github_webhooks.rb instead, which starts Puma directly and
# accepts -o/-p. Both paths boot the same GithubWebhooks::App.

$stdout.sync = true

require_relative 'lib/github_webhooks/app'

GithubWebhooks::App.configure!(GithubWebhooks::Settings.load)

run GithubWebhooks::App
