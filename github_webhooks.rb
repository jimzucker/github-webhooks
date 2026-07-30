#!/usr/local/bin/ruby
# frozen_string_literal: true

# Entry point for running the webhook server directly:
#
#   bundle exec ruby github_webhooks.rb [-o ADDR] [-p PORT]
#
# The application itself lives in lib/github_webhooks/. See README.md for setup,
# and https://docs.github.com/en/webhooks for configuring the webhook in GitHub.

# Force puts to show up in docker logs (reference: sinatra/sinatra#1118, issue #6).
$stdout.sync = true

require 'optparse'

require_relative 'lib/github_webhooks/app'

# Sinatra's classic mode parses -o/-p out of ARGV for you. Sinatra::Base does
# not, and both the Dockerfile CMD and the README pass `-o 0.0.0.0` -- without
# this the server would silently bind to localhost and the container would be
# unreachable from outside.
options = { bind: '127.0.0.1', port: 4567, environment: nil }
OptionParser.new do |opts|
  opts.banner = 'usage: ruby github_webhooks.rb [options]'
  opts.on('-o ADDR', '--bind ADDR', 'address to bind to (default 127.0.0.1)') { |v| options[:bind] = v }
  opts.on('-p PORT', '--port PORT', Integer, 'port to listen on (default 4567)') { |v| options[:port] = v }
  opts.on('-e ENV', '--environment ENV', 'Sinatra environment') { |v| options[:environment] = v }
  opts.on('-h', '--help', 'show this message') do
    puts opts
    exit 0
  end
end.parse!(ARGV)

begin
  settings = GithubWebhooks::Settings.load
rescue GithubWebhooks::ConfigurationError => e
  # Fatal at boot is fine and intentional -- unlike the old code, which called
  # exit(1) from inside the request path.
  warn "[ERROR] #{e.message}"
  exit 1
end

app = GithubWebhooks::App
app.configure!(settings)
app.set :bind, options[:bind]
app.set :port, options[:port]
app.set :environment, options[:environment].to_sym if options[:environment]
app.run!
