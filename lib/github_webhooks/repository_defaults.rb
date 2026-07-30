# frozen_string_literal: true

require 'base64'
require 'json'

require_relative 'errors'
require_relative 'github_client'
require_relative 'log'

module GithubWebhooks
  # Applies the default settings to a newly created repository: make sure it has
  # a README (branch protection cannot apply to an empty repo -- issue #2),
  # apply the repository settings, protect the default branch, and open an issue
  # recording what was done.
  class RepositoryDefaults
    REPO_CONFIG_FILE = 'new_repo_config.json'
    # Filename kept as-is: the README documents it and users override the config
    # directory by volume mount, so renaming it would silently break them.
    BRANCH_CONFIG_FILE = 'new_master_branch_config.json'

    FALLBACK_BRANCH = 'main'

    def initialize(client:, config_dir: 'config', poll_attempts: 10, poll_interval: 3)
      @client = client
      @config_dir = config_dir
      @poll_attempts = poll_attempts
      @poll_interval = poll_interval
    end

    def call(payload)
      repository = payload['repository'] || {}
      full_name = repository['full_name']
      raise ArgumentError, 'payload has no repository.full_name' if full_name.nil?

      branch = default_branch(repository, full_name)
      Log.info("Processing repository= #{full_name}, default_branch= #{branch}, " \
               "sender= #{payload.dig('sender', 'login')}")

      author = authorized_user
      ensure_readme(full_name, author)
      apply_repository_settings(full_name)
      protect_branch(full_name, branch)
      open_summary_issue(full_name, branch, author)
    end

    private

    # GitHub sends default_branch in the repository payload, so in the normal
    # case no extra call is needed. The old code hardcoded "master", which 404s
    # on any repository created since GitHub changed the default to "main".
    def default_branch(repository, full_name)
      from_payload = repository['default_branch']
      return from_payload unless from_payload.to_s.empty?

      response = @client.get("repos/#{full_name}", allow_failure: true,
                                                   message: 'Looking up default branch')
      return FALLBACK_BRANCH unless response.code == '200'

      branch = response.json['default_branch']
      branch.to_s.empty? ? FALLBACK_BRANCH : branch
    end

    def authorized_user
      user = @client.get('user', message: 'Getting Authorized User').json

      if user['email'].to_s.empty?
        # Only used as the README commit author. GitHub falls back to the
        # authenticated user's default identity, so this is not worth failing
        # over -- it used to exit(1) and take the server with it.
        Log.warn("Primary email address is not public for user_login=#{user['login']}; " \
                 'GitHub will pick the default commit identity')
      end

      user
    end

    def ensure_readme(full_name, author)
      return if readme_exists?(full_name)

      @client.put(
        "repos/#{full_name}/contents/README.md",
        readme_body(full_name, author),
        expect: '201',
        message: 'Creating README.md (repository must be initialized for the ' \
                 'branch protection API to work)'
      )

      # Creating a file is not instantly visible to the branch-protection API.
      wait_for_readme(full_name)
    end

    def readme_exists?(full_name)
      response = @client.get("repos/#{full_name}/contents/README.md",
                             allow_failure: true,
                             message: 'Checking existence of README.md')
      response.code == '200'
    end

    # Replaces a flat sleep(30). That exceeded GitHub's 10 second webhook
    # delivery timeout, so every delivery was recorded as failed; the work now
    # runs off the request thread and polls only as long as it actually needs to.
    def wait_for_readme(full_name)
      @poll_attempts.times do |attempt|
        return true if readme_exists?(full_name)

        Log.info("Waiting for README.md to become visible (attempt #{attempt + 1}/#{@poll_attempts})")
        sleep(@poll_interval) if @poll_interval.positive?
      end

      Log.warn("README.md still not visible after #{@poll_attempts} attempts; " \
               'continuing -- branch protection may fail')
      false
    end

    def readme_body(full_name, author)
      body = {
        'message' => 'my commit message',
        'content' => Base64.strict_encode64("# #{full_name}")
      }

      # The original sent this under a "sender_login" key, which the contents API
      # ignores, and put the user's *name* in the email field.
      unless author['email'].to_s.empty?
        body['committer'] = { 'name' => author['name'], 'email' => author['email'] }
      end

      JSON.generate(body)
    end

    def apply_repository_settings(full_name)
      @client.patch("repos/#{full_name}", read_config(REPO_CONFIG_FILE),
                    message: 'Defaulting Repository Settings')
    end

    def protect_branch(full_name, branch)
      @client.put("repos/#{full_name}/branches/#{branch}/protection",
                  read_config(BRANCH_CONFIG_FILE),
                  message: "Protecting #{branch} branch")
    end

    def open_summary_issue(full_name, branch, author)
      # Built with JSON.generate: the original interpolated these values straight
      # into a JSON string, so any name containing a quote produced invalid JSON.
      body = JSON.generate(
        'title' => "Ran webhook to default repository settings & protected the #{branch} branch",
        'body' => " @#{author['login']} set default repository settings and " \
                  "protected the #{branch} branch."
      )

      @client.post("repos/#{full_name}/issues", body, expect: '201',
                                                      message: 'Recording changes in an issue')
    end

    def read_config(filename)
      path = File.join(@config_dir, filename)
      raise ConfigurationError, "#{path} file missing" unless File.exist?(path)

      File.read(path)
    end
  end
end
