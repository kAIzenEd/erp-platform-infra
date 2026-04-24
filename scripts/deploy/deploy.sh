#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <dev|staging|prod>"
  exit 1
fi

env_name="$1"
compose_file="compose/docker-compose.${env_name}.yml"
env_file="env/${env_name}/.env"

if [[ ! -f "$compose_file" ]]; then
  echo "Missing compose file: $compose_file"
  exit 1
fi

if [[ ! -f "$env_file" ]]; then
  echo "Missing env file: $env_file"
  echo "Hint: copy env/${env_name}/.env.example to env/${env_name}/.env"
  exit 1
fi

echo "Deploying ${env_name} stack..."
docker compose --env-file "$env_file" -f "$compose_file" up -d

echo "Deployment command completed for ${env_name}."
