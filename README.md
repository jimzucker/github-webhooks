# github-webhooks
Web service that listens for organization events to know when a repository has been created. When the repository is created it automates the protection of the repository's default branch, and notifies you with an @mention in an issue within the repository that outlines the protections that were added.

You can run the webhooks in docker, see https://hub.docker.com/r/jimzucker/github-webhooks, or you can run the server directly from Github, instructions are at the end of the readme.

#### The following rules are enforced

##### Repository
* Allow merge commits
* Squash commits are not allowed

##### Default branch
* Pull requests are required to merge
* Do not allow re-writing history
* Restrictions are applied to administrators

The branch is read from `repository.default_branch` in the webhook payload, so this works for repositories that default to `main` as well as older ones on `master`.

##### Responses

`POST /github_webhook` answers immediately and does the GitHub API work on a background thread, because GitHub only allows a webhook 10 seconds to respond:

| Status | Meaning |
| --- | --- |
| `202` | Accepted; repository setup is running in the background (watch the logs) |
| `200` | Received, but this is not an event the service acts on |
| `400` | Body was not a JSON object |
| `401` | `X-Hub-Signature-256` was missing or did not verify |

Because the work is in-flight rather than queued, a restart loses any setup that had not finished. Check the logs after creating a repository.


##### Configuration
You can change the configuration for the settings used by the webhooks.  Each config file is a JSON as described by the references.

---

# To run the webhooks with default settings

## First create a file .webhook_properties with two properties defined

```
githubToken=<github api token>
webhookSecret=<shared secret, also set in the webhook's Secret field in GitHub>
```

> **Both are required.** The server refuses to start if either is missing.
>
> `webhookSecret` must match the **Secret** field of the webhook in GitHub
> (repository or organization → Settings → Webhooks → your webhook → Secret).
> Every request is checked against `X-Hub-Signature-256`, and anything that does
> not verify is rejected with `401` before it is processed. Without this the
> endpoint would act on a privileged GitHub token for anyone who found the URL.
>
> Generate one with:
>
> ```
> openssl rand -hex 32
> ```

## Start docker

``` 
docker run --rm -ti -p 4567:4567 -v $PWD/.webhook_properties:/usr/src/app/.webhook_properties \
	--name github-webhooks jimzucker/github-webhooks:latest
```

## Example docker-compose

You change the parameters for the webhooks by creating a local copy over overriting the config directory

```
services:
  github-webhooks:
    image: jimzucker/github-webhooks:latest
    container_name: github-webhooks
    restart: unless-stopped
    ports:
      - 4567:4567
    volumes:
      - $PWD/.webhook_properties:/usr/src/app/.webhook_properties
# you can copy configs locally and then override with:
#  docker cp github-webhooks:/usr/src/app/config .
#      - $PWD/config:/usr/src/app/config
```

See `docker-compose.yml` in the repo for the maintained copy.
---

## Default webhook settings

##### Repository Settings

File: config/new_repo_config.json<br>
Reference: https://docs.github.com/en/rest/repos/repos#update-a-repository

```
{
  "allow_squash_merge": false,
  "allow_merge_commit": true,
  "allow_rebase_merge": true,
  "delete_branch_on_merge": true
}
```

##### Branch Protection

File: config/new_master_branch_config.json<br>
Reference: https://docs.github.com/en/rest/branches/branch-protection#update-branch-protection

```
{ 
  "required_status_checks": {
	"strict" : true,
	"contexts": []
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismissal_restrictions": {},
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false
}
```
---


## Tech Notes

##### Github project

https://github.com/jimzucker/github-webhooks


##### Instructions to run Manually outside of Docker from github source

Requires Ruby 3.4 or newer (see the `Dockerfile` for the version this is built and tested against).

1. Install the dependencies:

   ```
   bundle install
   ```

2. Create a file `.webhook_properties` with both entries (see above):

   ```
   githubToken=<github api token>
   webhookSecret=<shared secret>
   ```

3. Start the server; it listens on port 4567:

   ```
   bundle exec ruby github_webhooks.rb
   ```

4. To expose your port for development:

   ```
   ./ngrok http 4567
   ```

5. Set the webhook payload URL in GitHub to:

   ```
   https://<URL to server that maps to 4567>/github_webhook
   ```

##### Running the tests

```
bundle install
bundle exec rake
```

##### Layout

| Path | Purpose |
| --- | --- |
| `github_webhooks.rb` | entry point; parses `-o`/`-p` and starts the server |
| `config.ru` | Rack entry point, for `bundle exec rackup` |
| `lib/github_webhooks/app.rb` | routes and event dispatch |
| `lib/github_webhooks/github_client.rb` | GitHub REST API calls |
| `lib/github_webhooks/repository_defaults.rb` | the new-repository workflow |
| `lib/github_webhooks/settings.rb` | reads `.webhook_properties` |
| `spec/` | Minitest + rack-test suite |

##### Building the image

Every merge to `master` publishes a multi-architecture (`linux/amd64` + `linux/arm64`) image to Docker Hub via `.github/workflows/publish.yml`, so you normally do not need to build by hand. For local one-offs:

```
./build.sh --local   # build for this machine only
./build.sh --push    # build both architectures and push to Docker Hub
```

`build.sh` deliberately refuses to do a plain single-arch `docker build` and push: on an Apple Silicon Mac that would replace the published `amd64` image with an `arm64`-only one.

##### Postman Reference

> Postman collection for testing github rest API: github_webooks.postman_collection.json


