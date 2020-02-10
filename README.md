# github-webhooks
Web service that listens for organization events to know when a repository has been created. When the repository is created please automate the protection of the master branch. Notify yourself with an @mention in an issue within the repository that outlines the protections that were added.

You can run the webhooks in docker, see https://hub.docker.com/r/jimzucker/github-webhooks, or you can run the server directly from Github, instructions are at the end of the readme.

#### The following rules are enforced

##### Repository
* Allow merge commits
* Squash commits are not allowed

##### Master Branch
* Pull requests are required to merge to master
* Do not allow re-writting history
* Restrictions are applied to administrators


##### Configuration
You can change the configuration for the settings used by the webhooks.  Each config file is a JSON as described by the references.

---

# To run the webhooks with default settings

## First create a file .webhook_properties with one property defined

```
githubToken=<github api token>
```

## Start docker

``` 
docker run --rm -d -p4567:4567 --volume $PWD/.webhook_properties:/usr/src/app/.webhook_properties jimzucker/github-webhooks:latest
```

## Example docker-compose

You change the parameters for the webhooks by creating a local copy over overriting the config directory

```
version: '3.4'
services:
  github-webhooks:
    image: jimzucker/github-webhooks:latest
    container_name: github-webhooks
    restart: unless-stopped
    ports:
      - 4567:4567
# you can copy configs locally and then override with:
#  docker cp github-webhooks:/usr/src/app/config .
    volumes:
      - $PWD/webhook_properties:/usr/src/app/.webhook_properties
#      - $PWD/config:/usr/src/app/config
```
---

## Default webhook settings

##### Repository Settings

File: config/new_repo_config.json<br>
Reference: https://developer.github.com/v3/repos/?#edit

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
Reference: https://developer.github.com/v3/repos/branches/#update-branch-protection

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

> 1. To start the server and it will monitor on port 4567
> 	ruby github-webhooks.rb
>   Note: you must create a file .webhook_properties with 1 entry
>   githubToken=<github api token>
> 
> 2. To expose your ports for development
> ./ngrok http 4567
> 
> 3. To setup the webhook in GitHub
> https://<URL to server that maps to 4567>/github_webhook

##### Postman Reference

> Postman collection for testing github rest API: github_webooks.postman_collection.json


