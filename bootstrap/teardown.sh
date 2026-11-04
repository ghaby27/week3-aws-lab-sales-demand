#!/usr/bin/env bash
# Deletes the week 3 lab stacks in reverse dependency order, then the Git sync stack
# (so the next deploy.sh recreates the sync configs, which is what triggers a fresh sync).
# Keeps the GitHub connection and the budget, so a rebuild needs no console step.
# Usage: bootstrap/teardown.sh
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-onward-logistics} AWS_REGION=${AWS_REGION:-eu-west-1}
ENV=dev

for stack in onward-$ENV-orders-compute onward-$ENV-orders-security onward-$ENV-orders-network onward-$ENV-orders-git-sync; do
  if aws cloudformation describe-stacks --stack-name "$stack" >/dev/null 2>&1; then
    echo "Deleting $stack"
    aws cloudformation delete-stack --stack-name "$stack"
    aws cloudformation wait stack-delete-complete --stack-name "$stack"
  fi
done
echo "Lab stacks deleted. Rebuild with: bootstrap/deploy.sh"
