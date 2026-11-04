#!/usr/bin/env bash
# Polls the load balancer once a second and prints which server answered.
# Usage: scripts/watch.sh   (reads the URL from the compute stack)
set -euo pipefail
export AWS_PROFILE=onward-logistics AWS_REGION=eu-west-1
URL=$(aws cloudformation describe-stacks --stack-name onward-dev-orders-compute \
  --query "Stacks[0].Outputs[?OutputKey=='AppUrl'].OutputValue" --output text)
echo "Watching $URL"
while :; do
  printf '%s  ' "$(date +%T)"
  curl -s --max-time 2 "$URL/api/whoami" || printf 'no answer'
  echo
  sleep 1
done
