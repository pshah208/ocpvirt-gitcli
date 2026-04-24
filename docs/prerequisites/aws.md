# AWS Prerequisites

Reference: https://docs.openshift.com/container-platform/latest/installing/installing_aws/

---

## AWS Account Requirements

- An AWS account with billing enabled.
- An IAM user or role with sufficient permissions (see below).
- A **Route53 public hosted zone** for your base domain
  (or a delegated subdomain).

## IAM Permissions

The installer needs broad AWS permissions. Use the policy files from the
OpenShift documentation. At a minimum:

```
ec2:*, elasticloadbalancing:*, route53:*, s3:*, iam:Create*,
iam:Get*, iam:List*, iam:Put*, iam:Tag*, sts:AssumeRole
```

For **Mint** mode (default): `iam:CreateUser`, `iam:AttachUserPolicy`,
`iam:CreateAccessKey`.

For **STS/WIF** mode: create component roles manually before install.

Reference: https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-account.html#installation-aws-permissions

## Service Quotas

Check and increase these quotas in your target region:

| Resource | Default | Recommended |
|---|---|---|
| Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances | 32 vCPU | ≥ 96 vCPU |
| Running On-Demand F instances (if using metal) | varies | ≥ 128 vCPU per metal |
| Elastic IP addresses | 5 | ≥ 10 |
| VPCs per Region | 5 | ≥ 6 |
| NAT Gateways per AZ | 5 | ≥ 3 |

```bash
# Check current vCPU quota
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A \
  --region "${AWS_REGION}"
```

## Network Prerequisites

- **Route53 hosted zone** for base domain (public or private).
- If using existing VPC: subnets must be in different AZs, with proper routing.
- Ensure the VPC has Internet Gateway (or NAT for private) for registry access.

## Pre-install Checks

```bash
# Authenticate
aws sts get-caller-identity

# Verify Route53 hosted zone
aws route53 list-hosted-zones-by-name \
  --dns-name "${BASE_DOMAIN}" \
  --query 'HostedZones[0].Name'

# Check vCPU quota in target region
aws service-quotas get-service-quota \
  --service-code ec2 --quota-code L-1216C47A \
  --region "${AWS_REGION}"
```

## CNV on AWS — Additional Requirements

- Workers must use **bare-metal instance types** (e.g. `m6i.metal`, `c5.metal`).
- No additional AWS configuration required — metal instances expose CPU flags natively.
- For RWX storage (live migration), deploy ODF on instance store volumes.

```bash
# Verify metal worker instances
aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
            "Name=instance-type,Values=*.metal" \
  --query 'Reservations[].Instances[].InstanceId'
```
