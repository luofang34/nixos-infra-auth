#!/usr/bin/env bash
# Kanidm smoke test. Run against a freshly-deployed host before declaring it
# healthy. This script exercises only unauthenticated reachability checks —
# any operator-credential checks live in the consumer's deployment repo
# where the credentials themselves live.
set -euo pipefail

usage() {
  echo "usage: $0 <fqdn>" >&2
  exit 2
}

host="${1:-}"
[[ -z "$host" ]] && usage

# Restrict host to RFC 1123 hostname syntax so it cannot smuggle path
# components, query strings, or shell metacharacters into the curl URL.
if ! [[ "$host" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
  echo "error: host must be a bare FQDN, not $host" >&2
  exit 2
fi

# 1. TLS reachability + sane HTTP response.
status_url="https://${host}/status"
if ! status=$(curl --fail --silent --show-error --max-time 10 -o /dev/null -w '%{http_code}' "$status_url"); then
  echo "FAIL: could not reach $status_url" >&2
  exit 1
fi
if [[ "$status" != "200" ]]; then
  echo "FAIL: $status_url returned HTTP $status (expected 200)" >&2
  exit 1
fi

# 2. The TLS certificate's subject should cover the requested host. curl
# already verifies this when --fail is set without --insecure; the explicit
# probe below produces a clearer error message if it ever drifts.
if ! curl --silent --show-error --max-time 10 --head "https://${host}/" >/dev/null; then
  echo "FAIL: TLS handshake to https://${host}/ failed" >&2
  exit 1
fi

echo "OK: $host responding on 443 with a valid TLS cert."
