#!/usr/bin/env bash
# Identity-host reachability smoke. Backend-neutral (Kanidm or Rauthy): it
# only checks that the host answers on 443 with a valid TLS certificate.
# Backend-specific OIDC endpoints are covered by oidc-discovery-smoke.sh.
# Any operator-credential checks live in the consumer's deployment repo
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

# curl verifies the TLS certificate by default (no --insecure), so a cert or
# connection failure makes it exit non-zero. Any HTTP status below 500 then
# proves the host is up and serving over a valid cert. No assumption about a
# specific path — Kanidm and Rauthy mount different roots.
if ! code=$(curl --silent --show-error --max-time 10 -o /dev/null -w '%{http_code}' "https://${host}/"); then
  echo "FAIL: could not reach https://${host}/ (TLS or connection failure)" >&2
  exit 1
fi
if [[ "$code" == "000" ]] || ((code >= 500)); then
  echo "FAIL: https://${host}/ returned HTTP $code" >&2
  exit 1
fi

echo "OK: $host responding on 443 with a valid TLS cert (HTTP $code)."
