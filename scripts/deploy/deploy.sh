#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <dev|staging|prod>"
  exit 1
fi

env_name="$1"
base_compose_file="compose/common/docker-compose.base.yml"
env_compose_file="compose/docker-compose.${env_name}.yml"
env_file="env/${env_name}/.env"

if [[ ! -f "$base_compose_file" ]]; then
  echo "Missing compose file: $base_compose_file"
  exit 1
fi

if [[ ! -f "$env_compose_file" ]]; then
  echo "Missing compose file: $env_compose_file"
  exit 1
fi

if [[ ! -f "$env_file" ]]; then
  echo "Missing env file: $env_file"
  echo "Hint: copy env/${env_name}/.env.example to env/${env_name}/.env"
  exit 1
fi

echo "Deploying ${env_name} stack..."
docker compose --env-file "$env_file" -f "$base_compose_file" -f "$env_compose_file" up -d

echo "Deployment command completed for ${env_name}."
