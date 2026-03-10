# 

[![Published on DevOps Unlocked](https://img.shields.io/badge/Published%20on-DevOps%20Unlocked-blue)](https://devopsunlocked.dev/terraform-module-architecture/)

Production-ready patterns extracted from the [DevOps Unlocked](https://devopsunlocked.dev) ecosystem.

>
> This repository is a battle-tested reference architecture, not a plug-and-play solution.
> It **will not work** out-of-the-box until you provide your own AWS account details and infrastructure values.
>
> 1. **Bootstrap First:** You must run `scripts/bootstrap-team.sh` before `terraform init` to create the state bucket and locking table.
> 2. **Action Required:** Every file marked with `# ACTION REQUIRED` requires your organisation-specific values.
> 3. **Manual Review:** Review `terraform.tfvars.example` and `docs/architecture.md` before applying to a real environment.
> **Never run `terraform apply` against a production account without a full plan review.**

---

## The Problem This Solves

Every Terraform repo starts flat. One directory, one state file, one team. It works fine until it doesn't — and when it breaks, it breaks badly. Ten teams modifying a shared monolith produces state contention, config drift, and compliance collapse simultaneously. When your SOC 2 auditor asks to see consistent encryption and tagging across 200 cloud resources, "we told engineers to do it right" is not a control.

This repository implements the 3-layer module architecture described in the DevOps Unlocked article _"Stop Writing Spaghetti Terraform."_ Compliance is a structural property of the codebase — enforced by the module, not documented in a wiki. Engineers consuming these modules cannot accidentally create an unencrypted S3 bucket or expose a public endpoint.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  PRODUCT CONFIGURATION LAYER                 │
│  teams/compute-squad/   teams/data-squad/   teams/...        │
│  Instantiates versioned service modules with team vars.      │
│  No raw aws_* resources. No compliance decisions.            │
└──────────────────────────┬──────────────────────────────────┘
                           │ calls (versioned source ref)
┌──────────────────────────▼──────────────────────────────────┐
│                   SERVICE MODULE LAYER                       │
│  terraform/modules/atomic/eks-compliant/                     │
│  terraform/modules/atomic/s3-secure/                         │
│  terraform/modules/atomic/rds-postgres/                      │
│  Opinionated, compliance-baked-in, versioned.                │
└──────────────────────────┬──────────────────────────────────┘
                           │ references via SSM Parameter Store
┌──────────────────────────▼──────────────────────────────────┐
│                    FOUNDATION LAYER                          │
│  terraform/foundation/                                       │
│  VPC, KMS keys, CloudTrail, IAM roles, S3 backends           │
│  Separate state. Separate pipeline. Platform team owned.     │
└─────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
terraform-module-architecture/
├── terraform/
│   ├── foundation/                  # Layer 1: shared infra, Platform team only
│   │   ├── main.tf                  # VPC, KMS, CloudTrail, S3 backend
│   │   ├── outputs.tf               # Exposes VPC IDs, KMS ARNs, subnet IDs
│   │   ├── variables.tf             # Foundation-level inputs
│   │   └── ssm.tf                   # Publishes outputs to SSM Parameter Store
│   ├── modules/
│   │   └── atomic/
│   │       ├── eks-compliant/       # Private EKS cluster with Secrets encryption and IRSA
│   │       ├── s3-secure/           # Encrypted, private S3 — no public access possible
│   │       └── rds-postgres/        # Encrypted, multi-AZ RDS PostgreSQL
│   └── teams/
│       ├── compute-squad/           # Compute Squad live config (Layer 3)
│       └── data-squad/              # Data Squad live config (Layer 3)
├── scripts/
│   ├── verify-compliance-tags.sh    # Validates mandatory tags across all resources
│   ├── check-module-versions.sh     # Flags squads running outdated module versions
│   └── bootstrap-team.sh           # Provisions new team state backend + IAM
├── docs/
│   └── architecture.md             # Decision log, compliance mapping, failure modes
├── terraform.tfvars.example        # All variables with ACTION REQUIRED markers and descriptions
└── README.md
```

---

## Prerequisites

| Requirement                | Notes                                                            |
| -------------------------- | ---------------------------------------------------------------- |
| Terraform >= 1.5.0         | Uses `check` blocks and improved validation syntax               |
| AWS CLI >= 2.13            | Required for bootstrap scripts                                   |
| AWS Organizations          | Foundation assumes multi-account setup                           |
| S3 bucket for state        | Must exist before `terraform init` — created by bootstrap script |
| DynamoDB table for locking | `terraform-state-locks` — created by bootstrap script            |
| KMS CMK per region         | ARN required in tfvars — do not use SSE-S3                       |
| IAM permissions            | See `docs/architecture.md` for minimum required permissions      |

---

## Quick Start

**1. Bootstrap the state backend (once per AWS account)**

```bash
chmod +x scripts/bootstrap-team.sh
./scripts/bootstrap-team.sh --account-id 123456789012 --region eu-west-1 --team platform
```

**2. Deploy the foundation layer first**

```bash
cd terraform/foundation
cp ../../terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — replace all ACTION REQUIRED values
terraform init
terraform plan -out=foundation.tfplan
terraform apply foundation.tfplan
```

**3. Verify foundation outputs published to SSM**

```bash
aws ssm get-parameters-by-path --path "/platform/foundation/" --recursive
```

**4. Deploy a team configuration**

```bash
cd terraform/teams/compute-squad
terraform init
terraform plan -out=compute-squad.tfplan
terraform apply compute-squad.tfplan
```

**5. Verify compliance tags**

```bash
chmod +x scripts/verify-compliance-tags.sh
./scripts/verify-compliance-tags.sh --account-id 123456789012 --region eu-west-1
```

---

## Key Configuration Decisions

### State Isolation

| Layer       | State Key                         | Owner         | Change Process        |
| ----------- | --------------------------------- | ------------- | --------------------- |
| Foundation  | `foundation/terraform.tfstate`    | Platform only | CAB review required   |
| Modules     | No state (library)                | Platform      | Semantic version bump |
| Team Config | `teams/{squad}/terraform.tfstate` | Squad + CI    | PR + plan review      |

### Mandatory Tags (Enforced by All Modules)

| Tag Key               | Source                     | Compliance Purpose                         |
| --------------------- | -------------------------- | ------------------------------------------ |
| `managed_by`          | Hard-coded: `"terraform"`  | Identifies IaC-managed resources           |
| `compliance_scope`    | Hard-coded: `"soc2-hipaa"` | Drives log retention and encryption tier   |
| `data_classification` | Required variable          | SOC 2 CC6.1 logical access controls        |
| `cost_centre`         | Required variable          | FinOps cost allocation by squad            |
| `squad`               | Required variable          | Ownership and incident routing             |
| `environment`         | Required variable          | Blast radius separation (prod/staging/dev) |
| `squad`               | Required variable          | Ownership and incident routing             |
| `environment`         | Required variable          | Blast radius separation                    |

---

## Compliance Mapping

| Control                    | Framework                             | Implementation                                                           |
| -------------------------- | ------------------------------------- | ------------------------------------------------------------------------ |
| Encryption at rest         | SOC 2 CC6.7, HIPAA §164.312(a)(2)(iv) | KMS CMK in all atomic modules. Not a variable.                           |
| Encryption in transit      | SOC 2 CC6.7, HIPAA §164.312(e)(2)(ii) | TLS enforced in RDS and ALB. HTTP redirected.                            |
| Least privilege            | SOC 2 CC6.3, ISO 27001 A.9.2          | IAM roles scoped per squad. No wildcard actions.                         |
| Audit logging              | SOC 2 CC7.2, HIPAA §164.312(b)        | CloudTrail in foundation. S3 + RDS access logging in modules.            |
| Network segmentation       | SOC 2 CC6.6, ISO 27001 A.13.1         | Private subnets only. Public subnet IDs not exposed as inputs.           |
| Public access prevention   | SOC 2 CC6.6                           | `block_public_acls` and `endpoint_public_access=false` hard-coded.       |
| Change management evidence | SOC 2 CC8.1, ISO 27001 A.12.1         | Terraform plan stored as CI artifact. State changes tracked in DynamoDB. |

---

## What Requires Configuration vs. Production-Ready

| Component                  | Status              | Notes                                                            |
| -------------------------- | ------------------- | ---------------------------------------------------------------- |
| S3 encryption (KMS CMK)    | ✅ Production-ready | Uses CMK, not SSE-S3                                             |
| S3 public access block     | ✅ Production-ready | All four settings enforced                                       |
| Mandatory tag injection    | ✅ Production-ready | `merge()` pattern — mandatory tags cannot be overridden          |
| Variable validation blocks | ✅ Production-ready | Reject invalid inputs at plan time                               |
| RDS multi-AZ               | ✅ Production-ready | Enabled by default                                               |
| Foundation VPC CIDR        | ⚠️ Action Required  | Replace with your IPAM-assigned range                            |
| KMS key ARNs               | ⚠️ Action Required  | Must be pre-created CMKs                                         |
| AWS Account IDs            | ⚠️ Action Required  | Replace all `123456789012` placeholders                          |
| S3 state bucket name       | ⚠️ Action Required  | Must match bucket from bootstrap script                          |
| Private Terraform Registry | ❌ Not included     | Local `source` paths — update to `app.terraform.io/your-org/...` |
| CI/CD pipeline             | ❌ Not included     | Atlantis/Terraform Cloud config not included                     |

---

## Related Blog Posts

- [Stop Writing Spaghetti Terraform: The Module Architecture That Scales to 50 Teams](https://devopsunlocked.dev/terraform-module-architecture)

---

## About

**Atif Farrukh** is the founder of [DevOps Unlocked](https://devopsunlocked.dev), a consulting practice specialising in compliance-driven cloud infrastructure for fintech and health-tech.

- 📧 atif@devopsunlocked.dev
- 💼 [Upwork](https://www.upwork.com/freelancers/atiffarrukh)
- 🐙 [github.com/DevOps-Unlocked](https://github.com/DevOps-Unlocked)
- ✍️ [devopsunlocked.dev](https://devopsunlocked.dev)
