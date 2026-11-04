#!/usr/bin/env bash
# Builds the whole week 3 setup from Git, in dependency order:
#   GitHub connection -> budget -> placeholder stacks -> Git sync (network, then security, then compute)
# Git sync then deploys infra/<layer>/ from the deployment repo, and servers clone the app repo at boot.
#
# Usage: bootstrap/deploy.sh   (first run: BUDGET_EMAIL=you@example.com bootstrap/deploy.sh)
# First run only: the GitHub connection must be approved once in the console; the script stops and says when.
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-onward-logistics} AWS_REGION=${AWS_REGION:-eu-west-1}
cd "$(dirname "$0")"
ENV=dev
TAGS=(Project=onward "Owner=Gabriel Anyaele" Environment=$ENV)
LAYERS=(network security compute)

deploy() { # stack template [params...]
  local stack=$1 template=$2; shift 2
  aws cloudformation deploy --stack-name "$stack" --template-file "$template" \
    --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset --tags "${TAGS[@]}" \
    ${1:+--parameter-overrides "$@"} >/dev/null
  echo "  $stack: deployed"
}

stack_status() { aws cloudformation describe-stacks --stack-name "$1" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo MISSING; }

echo "1. GitHub connection"
if [ "$(stack_status onward-$ENV-github-connection)" = MISSING ]; then
  deploy onward-$ENV-github-connection github-connection.yaml CreateRepositoryLink=false
fi
CONN=$(aws cloudformation describe-stacks --stack-name onward-$ENV-github-connection \
  --query "Stacks[0].Outputs[?OutputKey=='ConnectionArn'].OutputValue" --output text)
if [ "$(aws codeconnections get-connection --connection-arn "$CONN" --query Connection.ConnectionStatus --output text)" != AVAILABLE ]; then
  echo "  Approve connection onward-$ENV-github in the console (Developer Tools > Settings > Connections),"
  echo "  install the AWS Connector for GitHub app on the repository, then run this script again."
  exit 1
fi
deploy onward-$ENV-github-connection github-connection.yaml CreateRepositoryLink=true

echo "2. Budget alert"
# The alert email lives in SSM (settings stack), never in Git. Pass BUDGET_EMAIL only to set or change it.
if [ -n "${BUDGET_EMAIL:-}" ]; then
  deploy onward-$ENV-settings settings.yaml BudgetAlertEmail="$BUDGET_EMAIL"
fi
if [ "$(stack_status onward-$ENV-settings)" = MISSING ]; then
  echo "  skipped: run once with BUDGET_EMAIL=you@example.com to store the alert address"
else
  deploy onward-$ENV-budget budget.yaml
fi

echo "3. Placeholder stacks"
for l in "${LAYERS[@]}"; do
  if [ "$(stack_status onward-$ENV-orders-$l)" = MISSING ]; then
    deploy onward-$ENV-orders-$l placeholder-stack.yaml
  else
    echo "  onward-$ENV-orders-$l: exists"
  fi
done

echo "4. Git sync, one layer at a time"
# Layers already synced on a previous run are left alone, so re-running never drops a sync config.
current=$(aws cloudformation describe-stacks --stack-name onward-$ENV-orders-git-sync \
  --query "Stacks[0].Parameters[?ParameterKey=='SyncedLayers'].ParameterValue" --output text 2>/dev/null || echo 0)
for n in 1 2 3; do
  l=${LAYERS[$((n - 1))]}; stack=onward-$ENV-orders-$l
  if [ "${current:-0}" -ge "$n" ] 2>/dev/null; then
    echo "  $stack: already synced"; continue
  fi
  deploy onward-$ENV-orders-git-sync git-sync.yaml SyncedLayers=$n
  # Wait until Git sync has replaced the placeholder (real stacks have outputs; placeholders do not).
  for _ in $(seq 1 80); do
    st=$(stack_status "$stack")
    outputs=$(aws cloudformation describe-stacks --stack-name "$stack" --query 'length(Stacks[0].Outputs || `[]`)' --output text)
    case "$st" in
      *ROLLBACK_COMPLETE|*FAILED) echo "  $stack: $st - check the stack events"; exit 1 ;;
      *_COMPLETE) [ "$outputs" -gt 0 ] && break ;;
    esac
    sleep 15
  done
  [ "$outputs" -gt 0 ] || { echo "  $stack: timed out waiting for Git sync"; exit 1; }
  echo "  $stack: $st"
done

URL=$(aws cloudformation describe-stacks --stack-name onward-$ENV-orders-compute \
  --query "Stacks[0].Outputs[?OutputKey=='AppUrl'].OutputValue" --output text)
echo "Done. Order system: $URL"
