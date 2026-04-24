# Skill: platform-aws

AWS-specific prerequisites, IPI deployment steps, and OpenShift Virtualization
caveats for deploying OCP on Amazon Web Services.

Reference: https://docs.openshift.com/container-platform/latest/installing/installing_aws/

---

## Required CLIs

```bash
# AWS CLI v2
aws --version   # >= 2.x

# OpenShift tools
oc version --client
openshift-install version
```

Install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html

## Authentication Setup

```bash
# Option A: environment variables
export AWS_ACCESS_KEY_ID=<key>
export AWS_SECRET_ACCESS_KEY=<secret>
export AWS_DEFAULT_REGION=<region>

# Option B: named profile
aws configure --profile ocp-install
export AWS_PROFILE=ocp-install

# Verify
aws sts get-caller-identity
```

**Never commit credentials.** Store in `~/.aws/credentials` or AWS Secrets Manager.

## Minimum IAM Permissions

The installer requires a broad set of IAM permissions. Use the official
policy documents from:
https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-account.html

Key services needed: EC2, ELB, ELBv2, IAM, Route53, S3, VPC, STS.

Credential modes:
- **Mint** (default): installer creates IAM users per component. Requires
  `iam:CreateUser`, `iam:AttachUserPolicy`, etc.
- **Passthrough**: all components share the installer credential.
- **Manual (STS/WIF)**: pre-create IAM roles, reference in
  `credentialsMode: Manual`. Recommended for restricted environments.

## Networking Prerequisites

- **VPC** (new or existing): if existing, subnets must be tagged
  `kubernetes.io/cluster/<cluster-id>=shared`.
- **Subnets**: at least one public + one private subnet per AZ (for IPI).
- **Route53 hosted zone** for base domain (public or private).
- Security groups are created by the installer.
- **Internet access** from the VPC to Red Hat registries is required unless
  using a disconnected/mirrored install.

## Example install-config snippet

```yaml
platform:
  aws:
    region: ${AWS_REGION}
    zones:
      - ${AWS_ZONE_A}
      - ${AWS_ZONE_B}
      - ${AWS_ZONE_C}
    # Uncomment for existing VPC:
    # vpc:
    #   id: vpc-xxxxxxxxxxxxxxxxx
    #   subnets:
    #     - subnet-xxxxxxxxxxxxxxxxx
    #     - subnet-yyyyyyyyyyyyyyyyy
```

See full template: `templates/install-config/aws.install-config.yaml.tmpl`

## OpenShift Virtualization on AWS — Caveats

| Requirement | Detail |
|---|---|
| Worker instance type | Must be **bare-metal** for CPU passthrough. Use `m6i.metal`, `c5.metal`, or `r5.metal`. |
| Nested virtualisation | AWS does **not** support nested virtualisation on regular instances. Metal is mandatory. |
| Cost | Metal instances are expensive ($3–$8/hr). Use spot instances for lab/dev. |
| EBS storage | `gp3` supports RWO only; for RWX (live migration) deploy ODF on top of instance store. |
| Example instance | `m6i.metal`: 128 vCPU / 512 GiB — can host ~50–100 VMs depending on density. |

### Enabling metal workers in install-config

```yaml
compute:
  - name: worker
    replicas: 3
    platform:
      aws:
        type: m6i.metal
        zones:
          - us-east-1a
```

### Checking CPU flags after deploy

```bash
oc debug node/<worker-node> -- grep -m1 vmx /proc/cpuinfo
```

Should return a line containing `vmx` flags.
