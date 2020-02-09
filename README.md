# github-webhooks
Web service that listens for organization events to know when a repository has been created. When the repository is created please automate the protection of the master branch. Notify yourself with an @mention in an issue within the repository that outlines the protections that were added.

1. To start the server and it will monitor on port 4567
	ruby github-webhooks.rb

2. To expose your ports for development
./ngrok http 4567


3. To setup the webhook in GitHub
https://<URL to server that maps to 4567>/github_webhook

## The following rules are enforced:
1. Repository:
	a. Squash commits are not allowed
2. Master Branch:
	a. Pull requests are required to merge to master
	b. Restrictions are applied to administrators.

## Configuration
You can change the configuration for the settings used by the webhooks.  Each config file is a JSON as described by the references.

#### 1. Repository Settings
    File: config/new_repo_config.json
    Reference: https://developer.github.com/v3/repos/?#edit

#### 2. Branch Protection
	File: config/new_master_branch_config.json
	Reference: https://developer.github.com/v3/repos/branches/#update-branch-protection

## Tech Notes
> 1. Postman collection for testing github rest API: github_webooks.postman_collection.json
> 2. Docker is still in development


