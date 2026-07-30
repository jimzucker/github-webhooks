# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

# sinatra >= 4.2.0 is the first release clear of CVE-2022-29970, CVE-2022-45442,
# CVE-2024-21510 and CVE-2025-61921. It pulls rack 3.x, which also clears the
# rack advisories (CVE-2022-30123 et al).
gem 'sinatra', '~> 4.2'

# Rack 3 moved Rack::Handler into the rackup gem and sinatra no longer bundles a
# server, so classic mode (`ruby github_webhooks.rb`) needs both spelled out.
gem 'rackup', '~> 2.3'
gem 'puma', '~> 8.0'

gem 'json', '~> 2.21'
gem 'java-properties', '~> 0.3'
