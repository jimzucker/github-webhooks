#!/bin/sh
docker build -t github-webhooks .
docker tag github-webhooks jimzucker/github-webhooks:latest
#docker hub has CI when we push`
#docker push jimzucker/github-webhooks:latest
exit 0
