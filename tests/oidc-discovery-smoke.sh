#!/usr/bin/env bash
# OIDC discovery smoke test. Verifies that an OIDC RP (e.g. Proxmox) would be
# able to wire itself up to the identity host. Backend-neutral: different
# providers mount the discovery document under different prefixes, so try the
# known locations and use the first that returns a valid OIDC document.
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

# Candidate discovery paths, in order: Rauthy, Kanidm, then the RFC 8414
# root. The first that returns a valid OIDC JSON document wins.
candidate_paths=(
  "/auth/v1/.well-known/openid-configuration"
  "/oauth2/openid/.well-known/openid-configuration"
  "/.well-known/openid-configuration"
)

body=""
url=""
for path in "${candidate_paths[@]}"; do
  candidate="https://${host}${path}"
  if b=$(curl --fail --silent --show-error --max-time 10 "$candidate" 2>/dev/null) \
    && echo "$b" | jq -e . >/dev/null 2>&1; then
    body="$b"
    url="$candidate"
    break
  fi
done

if [[ -z "$url" ]]; then
  echo "FAIL: no valid OIDC discovery document at any known path on $host" >&2
  printf '  tried: %s\n' "${candidate_paths[@]}" >&2
  exit 1
fi

required_keys=(
  issuer
  authorization_endpoint
  token_endpoint
  jwks_uri
  response_types_supported
)
for key in "${required_keys[@]}"; do
  value=$(echo "$body" | jq -r --arg k "$key" '.[$k] // empty')
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "FAIL: $url missing or empty key: $key" >&2
    exit 1
  fi
done

issuer=$(echo "$body" | jq -r .issuer)
expected_issuer_prefix="https://${host}"
if [[ "$issuer" != "$expected_issuer_prefix"* ]]; then
  echo "FAIL: issuer $issuer does not start with $expected_issuer_prefix" >&2
  exit 1
fi

echo "OK: OIDC discovery at $url looks healthy."
