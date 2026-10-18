#!/usr/bin/env bash
set -euo pipefail

AWS_REGION=eu-central-1
SUBNET_ID=subnet-055662df8ccdc4184
ROUTE_TABLE_ID=rtb-0d4e8b299da4cec51
OWNER="${OWNER:-blackrosegarrote}"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.nat-state"

if [[ -f "$STATE_FILE" ]]; then
  echo "State file exists: $STATE_FILE. Run nat-down.sh or resolve existing resources first." >&2
  exit 1
fi
if [[ "$OWNER" == "your-nickname" ]]; then
  echo 'Set OWNER to your nickname, e.g. OWNER=myname ./scripts/nat-up.sh' >&2
  exit 1
fi

TAGS="[{Key=Name,Value=timecapsule-dev-nat-eip},{Key=Project,Value=timecapsule},{Key=Environment,Value=dev},{Key=Owner,Value=${OWNER}},{Key=Lab,Value=lab3}]"
EIP_ALLOCATION_ID=$(aws ec2 allocate-address \
  --region "$AWS_REGION" --domain vpc \
  --tag-specifications "ResourceType=elastic-ip,Tags=$TAGS" \
  --query AllocationId --output text)

printf 'EIP_ALLOCATION_ID=%q\n' "$EIP_ALLOCATION_ID" > "$STATE_FILE"
printf 'AWS_REGION=%q\nROUTE_TABLE_ID=%q\n' "$AWS_REGION" "$ROUTE_TABLE_ID" >> "$STATE_FILE"

echo "Allocated EIP: $EIP_ALLOCATION_ID"
NAT_TAGS="[{Key=Name,Value=timecapsule-dev-nat},{Key=Project,Value=timecapsule},{Key=Environment,Value=dev},{Key=Owner,Value=${OWNER}},{Key=Lab,Value=lab3}]"
NAT_GATEWAY_ID=$(aws ec2 create-nat-gateway \
  --region "$AWS_REGION" --subnet-id "$SUBNET_ID" \
  --allocation-id "$EIP_ALLOCATION_ID" --connectivity-type public \
  --tag-specifications "ResourceType=natgateway,Tags=$NAT_TAGS" \
  --query 'NatGateway.NatGatewayId' --output text)
printf 'NAT_GATEWAY_ID=%q\n' "$NAT_GATEWAY_ID" >> "$STATE_FILE"

echo "Waiting for NAT Gateway $NAT_GATEWAY_ID ..."
aws ec2 wait nat-gateway-available --region "$AWS_REGION" --nat-gateway-ids "$NAT_GATEWAY_ID"

aws ec2 create-route --region "$AWS_REGION" --route-table-id "$ROUTE_TABLE_ID" \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_GATEWAY_ID"
echo "NAT Gateway ready; default route created. State: $STATE_FILE"
