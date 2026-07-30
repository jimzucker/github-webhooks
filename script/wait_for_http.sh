#!/bin/sh
# Block until an HTTP server answers at all, or time out.
#
# Any response counts as up -- the app has no route for /, so a 404 is the
# expected success signal here. Only a connection failure (curl exit 7) means
# the server has not started yet.
#
#   ./script/wait_for_http.sh http://127.0.0.1:4567/ 45
set -eu

URL="${1:?usage: wait_for_http.sh URL [seconds]}"
TIMEOUT="${2:-45}"

i=0
while [ "$i" -lt "$TIMEOUT" ]; do
  if curl -s -o /dev/null "$URL" 2>/dev/null; then
    echo "$URL responded after ${i}s"
    exit 0
  fi
  i=$((i + 1))
  sleep 1
done

echo "timed out after ${TIMEOUT}s waiting for $URL" >&2
exit 1
