#!/usr/bin/env bash
set -euo pipefail

AWS_REGION=eu-central-1
SUBNET_ID=subnet-055662df8ccdc4184
ROUTE_TABLE_ID=rtb-0d4e8b299da4cec51
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.nat-state"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "State file not found: $STATE_FILE" >&2
  exit 1
fi
source "$STATE_FILE"
: "${EIP_ALLOCATION_ID:?Missing EIP allocation ID}"

if [[ -n "${NAT_GATEWAY_ID:-}" ]]; then
  echo 'Removing default route if it targets our NAT Gateway...'
  CURRENT_NAT=$(aws ec2 describe-route-tables --region "$AWS_REGION" \
    --route-table-ids "$ROUTE_TABLE_ID" \
    --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].NatGatewayId | [0]" --output text)
  if [[ "$CURRENT_NAT" == "$NAT_GATEWAY_ID" ]]; then
    aws ec2 delete-route --region "$AWS_REGION" --route-table-id "$ROUTE_TABLE_ID" \
      --destination-cidr-block 0.0.0.0/0
  elif [[ "$CURRENT_NAT" != 'None' ]]; then
    echo "Route targets another NAT Gateway ($CURRENT_NAT); refusing to modify it." >&2
    exit 1
  fi

  STATUS=$(aws ec2 describe-nat-gateways --region "$AWS_REGION" \
    --nat-gateway-ids "$NAT_GATEWAY_ID" --query 'NatGateways[0].State' --output text)
  if [[ "$STATUS" != 'deleted' && "$STATUS" != 'deleting' ]]; then
    aws ec2 delete-nat-gateway --region "$AWS_REGION" --nat-gateway-id "$NAT_GATEWAY_ID"
  fi
  echo 'Waiting for NAT Gateway deletion...'
  aws ec2 wait nat-gateway-deleted --region "$AWS_REGION" --nat-gateway-ids "$NAT_GATEWAY_ID"
fi

for attempt in {1..20}; do
  if aws ec2 release-address --region "$AWS_REGION" --allocation-id "$EIP_ALLOCATION_ID"; then
    rm -f "$STATE_FILE"
    echo 'Elastic IP released. Cleanup complete.'
    exit 0
  fi
  echo "Elastic IP still in use (attempt $attempt/20); retrying in 15 seconds..." >&2
  sleep 15
done

echo "Could not release Elastic IP $EIP_ALLOCATION_ID; state file retained for retry." >&2
exit 1
