#!/usr/bin/env bash
# Phase 1 infrastructure verification against live AWS + Terraform state.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT/terraform/phase1_network"
REGION="${AWS_REGION:-$(terraform -chdir="$TF_DIR" output -raw aws_region)}"

VPC_ID=$(terraform -chdir="$TF_DIR" output -raw vpc_id)
BUCKET=$(terraform -chdir="$TF_DIR" output -raw s3_bucket_id)
KMS_KEY=$(terraform -chdir="$TF_DIR" output -raw kms_key_id)
SG=$(terraform -chdir="$TF_DIR" output -raw vpc_endpoint_security_group_id)
S3_VPCE=$(terraform -chdir="$TF_DIR" output -raw s3_vpc_endpoint_id)
BEDROCK_RT_VPCE=$(terraform -chdir="$TF_DIR" output -raw bedrock_runtime_vpc_endpoint_id)

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "========== PHASE 1 INFRASTRUCTURE TESTS =========="
echo "region=$REGION vpc=$VPC_ID bucket=$BUCKET"
echo ""

echo "--- VPC ---"
CIDR=$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlock' --output text)
DNS_SUP=$(aws ec2 describe-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --attribute enableDnsSupport --query 'EnableDnsSupport.Value' --output text)
DNS_HOST=$(aws ec2 describe-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --attribute enableDnsHostnames --query 'EnableDnsHostnames.Value' --output text)
[[ "$CIDR" == "10.0.0.0/16" ]] && pass "VPC CIDR is 10.0.0.0/16" || fail "VPC CIDR expected 10.0.0.0/16 got $CIDR"
[[ "$DNS_SUP" == "True" ]] && pass "VPC DNS support enabled" || fail "VPC DNS support not enabled ($DNS_SUP)"
[[ "$DNS_HOST" == "True" ]] && pass "VPC DNS hostnames enabled" || fail "VPC DNS hostnames not enabled ($DNS_HOST)"

IGW_COUNT=$(aws ec2 describe-internet-gateways --region "$REGION" --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'length(InternetGateways)' --output text)
[[ "$IGW_COUNT" == "0" ]] && pass "No Internet Gateway attached (private-only)" || fail "Found $IGW_COUNT IGW(s) attached to VPC"

NAT_COUNT=$(aws ec2 describe-nat-gateways --region "$REGION" --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" --query 'length(NatGateways)' --output text)
[[ "$NAT_COUNT" == "0" ]] && pass "No NAT Gateways present" || fail "Found $NAT_COUNT NAT Gateway(s)"

echo ""
echo "--- Subnets ---"
PRIV_N=$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=private" --query 'length(Subnets)' --output text)
ISO_N=$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=isolated" --query 'length(Subnets)' --output text)
PRIV_AZ=$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=private" --query 'Subnets[].AvailabilityZone' --output text | tr '\t' '\n' | sort -u | wc -l | tr -d ' ')
ISO_AZ=$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=isolated" --query 'Subnets[].AvailabilityZone' --output text | tr '\t' '\n' | sort -u | wc -l | tr -d ' ')
PRIV_PUB=$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=private" --query 'Subnets[?MapPublicIpOnLaunch==`true`] | length(@)' --output text)
ISO_PUB=$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=isolated" --query 'Subnets[?MapPublicIpOnLaunch==`true`] | length(@)' --output text)
[[ "$PRIV_N" == "2" ]] && pass "2 private subnets" || fail "Expected 2 private subnets, got $PRIV_N"
[[ "$ISO_N" == "2" ]] && pass "2 isolated subnets" || fail "Expected 2 isolated subnets, got $ISO_N"
[[ "$PRIV_AZ" == "2" ]] && pass "Private subnets span 2 AZs" || fail "Private subnets AZ count=$PRIV_AZ"
[[ "$ISO_AZ" == "2" ]] && pass "Isolated subnets span 2 AZs" || fail "Isolated subnets AZ count=$ISO_AZ"
[[ "$PRIV_PUB" == "0" ]] && pass "Private subnets MapPublicIpOnLaunch=false" || fail "Private subnet has public IP mapping"
[[ "$ISO_PUB" == "0" ]] && pass "Isolated subnets MapPublicIpOnLaunch=false" || fail "Isolated subnet has public IP mapping"

echo ""
echo "--- Route tables ---"
# Explicit check: no 0.0.0.0/0 routes via igw-* or nat-*
DEFAULT_INTERNET=$(aws ec2 describe-route-tables --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" --output json | python3 -c '
import sys, json
rts = json.load(sys.stdin)["RouteTables"]
bad = 0
for rt in rts:
    for r in rt.get("Routes", []):
        if r.get("DestinationCidrBlock") != "0.0.0.0/0":
            continue
        gw = r.get("GatewayId") or ""
        nat = r.get("NatGatewayId") or ""
        if gw.startswith("igw-") or nat.startswith("nat-"):
            bad += 1
print(bad)
')
[[ "$DEFAULT_INTERNET" == "0" ]] && pass "No default route to IGW/NAT (air-gapped path)" || fail "Found default internet routes: $DEFAULT_INTERNET"

echo ""
echo "--- KMS ---"
KMS_STATE=$(aws kms describe-key --region "$REGION" --key-id "$KMS_KEY" --query 'KeyMetadata.KeyState' --output text)
KMS_ENABLED=$(aws kms describe-key --region "$REGION" --key-id "$KMS_KEY" --query 'KeyMetadata.Enabled' --output text)
KMS_ROT=$(aws kms get-key-rotation-status --region "$REGION" --key-id "$KMS_KEY" --query 'KeyRotationEnabled' --output text)
ALIAS=$(aws kms list-aliases --region "$REGION" --key-id "$KMS_KEY" --query "Aliases[?AliasName=='alias/enterprise-rag-cmk'] | length(@)" --output text)
[[ "$KMS_STATE" == "Enabled" ]] && pass "KMS key state Enabled" || fail "KMS key state=$KMS_STATE"
[[ "$KMS_ENABLED" == "True" ]] && pass "KMS key Enabled=true" || fail "KMS key not enabled"
[[ "$KMS_ROT" == "True" ]] && pass "KMS key rotation enabled" || fail "KMS rotation disabled"
[[ "$ALIAS" == "1" ]] && pass "KMS alias alias/enterprise-rag-cmk exists" || fail "KMS alias missing"

echo ""
echo "--- S3 ---"
PAB_OK=$(aws s3api get-public-access-block --bucket "$BUCKET" --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,BlockPublicPolicy,IgnorePublicAcls,RestrictPublicBuckets]' --output text | tr '\t' '\n' | grep -c True || true)
[[ "$PAB_OK" == "4" ]] && pass "S3 public access fully blocked" || fail "S3 public access block incomplete ($PAB_OK/4)"

SSE_ALG=$(aws s3api get-bucket-encryption --bucket "$BUCKET" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)
SSE_KEY=$(aws s3api get-bucket-encryption --bucket "$BUCKET" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.KMSMasterKeyID' --output text)
[[ "$SSE_ALG" == "aws:kms" && "$SSE_KEY" == *"$KMS_KEY"* ]] && pass "S3 SSE-KMS with Phase 1 CMK" || fail "S3 encryption unexpected: $SSE_ALG $SSE_KEY"

VER=$(aws s3api get-bucket-versioning --bucket "$BUCKET" --query 'Status' --output text)
[[ "$VER" == "Enabled" ]] && pass "S3 versioning Enabled" || fail "S3 versioning=$VER"

TEST_KEY="phase1-smoke-test/$(date +%s).txt"
echo "phase1-ok" > /tmp/p1-smoke.txt
if aws s3api put-object --bucket "$BUCKET" --key "$TEST_KEY" --body /tmp/p1-smoke.txt \
  --server-side-encryption aws:kms --ssekms-key-id "$KMS_KEY" >/dev/null 2>&1; then
  pass "S3 PutObject with SSE-KMS succeeded"
  aws s3api delete-object --bucket "$BUCKET" --key "$TEST_KEY" >/dev/null 2>&1 || true
else
  fail "S3 PutObject with SSE-KMS failed"
fi

if aws s3api put-object --bucket "$BUCKET" --key "${TEST_KEY}.nosse" --body /tmp/p1-smoke.txt >/dev/null 2>&1; then
  fail "S3 PutObject WITHOUT SSE should have been denied"
  aws s3api delete-object --bucket "$BUCKET" --key "${TEST_KEY}.nosse" >/dev/null 2>&1 || true
else
  pass "S3 PutObject without SSE correctly denied by bucket policy"
fi

echo ""
echo "--- VPC Endpoints ---"
EP_JSON=$(aws ec2 describe-vpc-endpoints --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" --output json)

check_ep() {
  local want_svc="$1" want_type="$2"
  local result
  result=$(echo "$EP_JSON" | python3 -c '
import sys, json
want_svc, want_type = sys.argv[1], sys.argv[2]
eps = json.load(sys.stdin)["VpcEndpoints"]
matches = [e for e in eps if e["ServiceName"].endswith("." + want_svc) and e["VpcEndpointType"] == want_type]
if not matches:
    print("MISSING")
else:
    e = matches[0]
    print("%s|%s" % (e["State"], e["VpcEndpointId"]))
' "$want_svc" "$want_type")
  if [[ "$result" == "MISSING" ]]; then
    fail "missing $want_type endpoint for $want_svc"
  else
    state="${result%%|*}"
    eid="${result#*|}"
    if [[ "$state" == "available" ]]; then
      pass "$want_type endpoint $want_svc available ($eid)"
    else
      fail "$want_svc endpoint state=$state (expected available)"
    fi
  fi
}

check_ep "s3" "Gateway"
check_ep "bedrock-runtime" "Interface"
check_ep "bedrock-agent" "Interface"
check_ep "comprehend" "Interface"

PRIV_DNS_FALSE=$(aws ec2 describe-vpc-endpoints --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" "Name=vpc-endpoint-type,Values=Interface" --query 'VpcEndpoints[?PrivateDnsEnabled==`false`] | length(@)' --output text)
[[ "$PRIV_DNS_FALSE" == "0" ]] && pass "All Interface endpoints have PrivateDnsEnabled" || fail "Private DNS not enabled on all Interface endpoints"

S3_RT=$(aws ec2 describe-vpc-endpoints --region "$REGION" --vpc-endpoint-ids "$S3_VPCE" --query 'VpcEndpoints[0].RouteTableIds | length(@)' --output text)
[[ "$S3_RT" == "4" ]] && pass "S3 Gateway endpoint associated with 4 route tables" || fail "S3 Gateway route tables=$S3_RT (expected 4)"

echo ""
echo "--- Security Group ---"
ING_OK=$(aws ec2 describe-security-group-rules --region "$REGION" --filters "Name=group-id,Values=$SG" --query "length(SecurityGroupRules[?IsEgress==\`false\` && FromPort==\`443\` && CidrIpv4==\`10.0.0.0/16\`])" --output text)
[[ "$ING_OK" == "1" ]] && pass "VPCE SG allows HTTPS 443 from 10.0.0.0/16" || fail "VPCE SG ingress rule missing/incorrect ($ING_OK)"

echo ""
echo "--- Terraform drift ---"
set +e
terraform -chdir="$TF_DIR" plan -input=false -detailed-exitcode >/tmp/p1_plan_test.txt 2>&1
PLAN_RC=$?
set -e
if [[ "$PLAN_RC" == "0" ]]; then
  pass "Terraform plan: no drift (infrastructure matches config)"
elif [[ "$PLAN_RC" == "2" ]]; then
  fail "Terraform plan detected drift/changes"
else
  fail "Terraform plan failed (exit $PLAN_RC)"
fi

echo ""
echo "========== SUMMARY =========="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  echo "RESULT: PHASE 1 TESTS FAILED"
  exit 1
fi
echo "RESULT: PHASE 1 TESTS PASSED"
