#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <env_name> <base_url>"
  echo "Example: $0 dev https://erp-dev.local"
  exit 1
fi

env_name="$1"
base_url="$2"

checks=(
  "${base_url}/api/method/ping"
)

echo "Running smoke checks for ${env_name} at ${base_url}"
for url in "${checks[@]}"; do
  code=$(curl -k -s -o /dev/null -w "%{http_code}" "$url" || true)
  if [[ "$code" != "200" ]]; then
    echo "FAIL: ${url} returned ${code}"
    exit 1
  fi
  echo "PASS: ${url}"
done

echo "Smoke checks passed for ${env_name}."
