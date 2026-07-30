#!/bin/sh
# End-to-end smoke test against a running container.
#
# Used by .github/workflows/ci.yml and runnable by hand:
#   WEBHOOK_SECRET=smoke-test-secret ./script/smoke_test.sh http://127.0.0.1:4567 gw-ci
#
# Args:
#   $1  base URL of the running server (default http://127.0.0.1:4567)
#   $2  docker container name to pull logs from (optional; enables log assertions)
# Env:
#   WEBHOOK_SECRET  must match webhookSecret in the container's .webhook_properties
set -eu

BASE="${1:-http://127.0.0.1:4567}"
CONTAINER="${2:-}"
SECRET="${WEBHOOK_SECRET:-smoke-test-secret}"

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

check_log() {
  label="$1"
  pattern="$2"
  [ -n "$CONTAINER" ] || return 0
  if logs | grep -qE "$pattern"; then
    echo "ok    $label"
  else
    echo "FAIL  $label (no match for /$pattern/ in container logs)"
    failures=$((failures + 1))
  fi
}

# Same HMAC GitHub computes over the raw body; verified to agree with
# OpenSSL::HMAC.hexdigest in Ruby.
sign() {
  printf '%s' "$1" | openssl dgst -sha256 -hmac "$SECRET" | sed 's/^.*= *//'
}

# $1 event, $2 body -- correctly signed, the way GitHub sends it.
post() {
  post_raw "$1" "$2" "X-Hub-Signature-256: sha256=$(sign "$2")"
}

# $1 event, $2 body, $3 extra header line (may be empty)
post_raw() {
  if [ -n "$3" ]; then
    curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/github_webhook" \
      -H 'Content-Type: application/json' -H "X-GitHub-Event: $1" -H "$3" -d "$2"
  else
    curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/github_webhook" \
      -H 'Content-Type: application/json' -H "X-GitHub-Event: $1" -d "$2"
  fi
}

get() {
  curl -s -o /dev/null -w '%{http_code}' "$BASE$1"
}

IGNORED='{"action":"created","organization":{"login":"acme"}}'
REPO_DELETED='{"action":"deleted","repository":{"full_name":"acme/demo","default_branch":"main"}}'
REPO_CREATED='{"action":"created","repository":{"full_name":"acme/demo","default_branch":"main"},"sender":{"login":"acme-bot"}}'

echo "--- smoke test against $BASE ---"

# --- signature verification -------------------------------------------------
# An unsigned request must never reach the handler: the endpoint acts on a
# privileged GitHub token, so anyone who learns the URL could otherwise drive it.
check "unsigned request is rejected" 401 "$(post_raw repository "$REPO_CREATED" '')"

check "garbage signature is rejected" 401 \
  "$(post_raw repository "$REPO_CREATED" 'X-Hub-Signature-256: sha256=deadbeef')"

# Signature valid, but for a different body.
check "tampered body is rejected" 401 \
  "$(post_raw repository "$(printf '%s' "$REPO_CREATED" | sed 's|acme/demo|attacker/evil|')" \
      "X-Hub-Signature-256: sha256=$(sign "$REPO_CREATED")")"

# GitHub still sends the legacy SHA-1 header; accepting it would defeat the check.
check "legacy sha1-only signature is rejected" 401 \
  "$(post_raw repository "$REPO_CREATED" \
      "X-Hub-Signature: sha1=$(printf '%s' "$REPO_CREATED" | openssl dgst -sha1 -hmac "$SECRET" | sed 's/^.*= *//')")"

# --- normal operation -------------------------------------------------------
check "POST /github_webhook (non-repository object)" 200 "$(post organization "$IGNORED")"
check "POST /github_webhook (repository/deleted)" 200 "$(post repository "$REPO_DELETED")"
check "GET /nope (unknown route)" 404 "$(get /nope)"
check "POST /github_webhook (malformed JSON)" 400 "$(post repository 'not json')"

# An event we DO act on. The container runs with a dummy token, so the GitHub call
# behind this fails -- which is the point. The work is acknowledged with 202 and
# runs off the request thread; the failure must be logged and contained. This is
# the regression test for exit(1) in the request path, which used to take the
# whole server down mid-webhook.
check "POST /github_webhook (repository/created, signed)" 202 "$(post repository "$REPO_CREATED")"

# Give the background thread a moment to fail and log.
sleep 3

check "server still serving after a failed background job" 404 "$(get /nope)"

# --- log assertions ---------------------------------------------------------
check_log "background failure was logged, not fatal" '\[ERROR\].*processing repository/created'
# $stdout.sync must keep working or docker logs go silent -- see issue #6.
check_log "[INFO] output reaches docker logs" '\[INFO\] Ignoring object'
check_log "rejections are logged" '\[ERROR\] Rejecting webhook'
# The secret must never appear in logs, nor a valid signature for a known body.
if [ -n "$CONTAINER" ]; then
  if logs | grep -q "$SECRET"; then
    echo "FAIL  webhook secret leaked into the logs"
    failures=$((failures + 1))
  else
    echo "ok    webhook secret never appears in the logs"
  fi
fi

if [ "$failures" -ne 0 ]; then
  echo "--- $failures check(s) failed; container logs follow ---"
  logs
  exit 1
fi

echo "--- all checks passed ---"
