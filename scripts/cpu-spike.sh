#!/usr/bin/env bash
# Simulates a sales-day CPU spike on every server in the Auto Scaling group,
# through SSM Run Command (secure remote access: no SSH, no open ports).
# Usage: scripts/cpu-spike.sh [minutes]   (default 10)
set -euo pipefail
export AWS_PROFILE=onward-logistics AWS_REGION=eu-west-1
MINUTES=${1:-10}
ASG=onward-dev-orders-asg

aws ssm send-command \
  --document-name AWS-RunShellScript \
  --targets "Key=tag:aws:autoscaling:groupName,Values=$ASG" \
  --comment "Onward sales-day CPU spike for ${MINUTES} min" \
  --parameters "commands=[\"for c in \$(seq \$(nproc)); do timeout ${MINUTES}m sh -c 'while :; do :; done' & done; wait\"]" \
  --timeout-seconds 600 \
  --query 'Command.CommandId' --output text
echo "Spike running on current servers for ${MINUTES} min. Watch: aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG"
