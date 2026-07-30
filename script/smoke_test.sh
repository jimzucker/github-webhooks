#!/bin/sh
# End-to-end smoke test against a running container.
#
# Used by .github/workflows/ci.yml and runnable by hand:
#   ./script/smoke_test.sh http://127.0.0.1:4567 gw-ci
#
# Args:
#   $1  base URL of the running server (default http://127.0.0.1:4567)
#   $2  docker container name to pull logs from (optional; enables log assertions)
set -eu

BASE="${1:-http://127.0.0.1:4567}"
CONTAINER="${2:-}"

failures=0

logs() {
  [ -n "$CONTAINER" ] && docker logs "$CONTAINER" 2>&1 || true
}

check() {
  label="$1"
  expected="$2"
  actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "ok    $label (HTTP $actual)"
  else
    echo "FAIL  $label: expected HTTP $expected, got $actual"
    failures=$((failures + 1))
  fi
}

post() {
  curl -s -o /dev/null -w '%{http_code}' \
    -X POST "$BASE/github_webhook" \
    -H 'Content-Type: application/json' \
    -H "X-GitHub-Event: $1" \
    -d "$2"
}

get() {
  curl -s -o /dev/null -w '%{http_code}' "$BASE$1"
}

echo "--- smoke test against $BASE ---"

# An event we do not act on: exercises routing and request.body.read without
# touching the GitHub API.
check "POST /github_webhook (non-repository object)" 200 \
  "$(post organization '{"action":"created","organization":{"login":"acme"}}')"

# A repository event with an action we ignore: one level deeper, still no API call.
check "POST /github_webhook (repository/deleted)" 200 \
  "$(post repository '{"action":"deleted","repository":{"full_name":"acme/demo","default_branch":"main"}}')"

check "GET /nope (unknown route)" 404 "$(get /nope)"

# $stdout.sync must keep working or docker logs go silent -- see issue #6.
if [ -n "$CONTAINER" ]; then
  if logs | grep -q '\[INFO\] Ignoring object'; then
    echo "ok    [INFO] output reaches docker logs"
  else
    echo "FAIL  no [INFO] output in docker logs (\$stdout.sync regression?)"
    failures=$((failures + 1))
  fi
fi

if [ "$failures" -ne 0 ]; then
  echo "--- $failures check(s) failed; container logs follow ---"
  logs
  exit 1
fi

echo "--- all checks passed ---"
