# Architecture Decision Log
## terraform-module-architecture | DevOps Unlocked

---

## Decision 1: Three Layers with Strict Separation

**Decision:** Separate Terraform into three distinct layers — Foundation, Service Modules, and Product Configuration — each with their own state files and ownership model.

**Alternatives Considered:**
- **Single monolithic repo / one state file:** Simplest to start. Breaks at scale: state contention, unlimited blast radius, no way to enforce different change processes per layer.
- **Two layers (shared infra + team config):** Better than one, but conflates atomic modules with service composition, making reuse and versioning hard.
- **Terragrunt with flat module hierarchy:** Valid approach. We chose vanilla Terraform composition to reduce toolchain surface. Terragrunt is a viable enhancement for DRY backend blocks.

**Rationale:** Each layer has a fundamentally different risk profile and change cadence. Foundation changes have org-wide blast radius and happen rarely. Module changes are versioned and affect consumers gradually. Team config changes are frequent and scoped to one squad. Separating them allows appropriate change control per layer without blocking others.

---

## Decision 2: SSM Parameter Store for Cross-Layer Coupling

**Decision:** Foundation publishes outputs (VPC ID, subnet IDs) to SSM. Consumers read from SSM rather than terraform_remote_state.

**Alternatives Considered:**
- **terraform_remote_state:** Hard dependency on backend config. If the foundation team changes the S3 bucket or key path, every consumer breaks. Also requires consumers to have read access to the full state file.
- **Hard-coded values in team configs:** Fast to start, fatal at scale. Values drift, get stale, create hidden dependencies.

**Rationale:** SSM provides a stable contract. The /platform/foundation/ path is the interface, not the backend. IAM policies grant ssm:GetParameter without exposing the state bucket. CloudTrail logs every parameter read — clean audit trail. Parameter updates are atomic and versioned.

---

## Decision 3: Compliance Controls Hard-Coded in Modules

**Decision:** Security settings (public access blocks, KMS encryption, mandatory tags, private networking) are hard-coded in modules. Not exposed as variables.

**Alternatives Considered:**
- **Expose all settings as variables with secure defaults:** Defaults get overridden "just for this one case." One missed flag during a sprint = public S3 bucket in production.
- **OPA/Conftest enforcement:** Excellent complement, not a replacement. OPA catches misconfigurations at plan time; hard-coded controls prevent them from being expressible at all.

**Rationale:** The module is the enforcement point. If the setting is not a variable, it cannot be bypassed. This is the difference between "we have a policy" and "the policy is structurally enforced." For SOC 2 auditors, structural enforcement is significantly more defensible than documented intent.

---

## Decision 4: KMS CMK Over SSE-S3 for S3 Encryption

**Decision:** All S3 encryption uses KMS CMKs. SSE-S3 (AES256) is not supported by the s3-secure module.

**Rationale:** For SOC 2 CC6.7 and HIPAA, auditors ask not "is data encrypted?" but "can you demonstrate key management controls?" CMKs provide rotation audit trails in CloudTrail, key usage restrictions via key policies, and the ability to revoke all data access by disabling the key. bucket_key_enabled=true reduces KMS API call costs by ~99% for high-throughput buckets, eliminating the cost objection.

---

## Decision 5: Mandatory Tags via merge() with Module Tags Last

**Decision:** Modules inject mandatory compliance tags using merge(var.tags, local.mandatory_tags) — module tags listed second so they always win conflicts.

**Rationale:** merge(var.tags, local.mandatory_tags) means caller tags are applied first, then mandatory tags overwrite conflicts. Callers can add tags freely; they cannot override managed_by, compliance_scope, or data_classification. This gives teams flexibility without compromising audit integrity.

---

## Compliance Mapping

| Control ID | Framework | Requirement | Implementation |
|---|---|---|---|
| CC6.1 | SOC 2 | Logical access controls | data_classification mandatory tag on all resources. IAM policies reference tag conditions. |
| CC6.6 | SOC 2 | Restrict network access | Private subnets only. block_public_acls=true. publicly_accessible=false. Hard-coded. |
| CC6.7 | SOC 2 | Encrypt data at rest | KMS CMK in all atomic modules. Not configurable off. |
| CC7.2 | SOC 2 | Monitor system components | CloudTrail multi-region. RDS Enhanced Monitoring 1s. CloudWatch Logs for all services. |
| CC8.1 | SOC 2 | Change management | Terraform plan stored as CI artifact. State changes tracked in DynamoDB with IAM identity. |
| 164.312(a)(2)(iv) | HIPAA | Encryption of ePHI | KMS CMK enforced in S3, RDS, SSM. |
| 164.312(b) | HIPAA | Audit controls | CloudTrail, RDS audit logs, S3 access logging all enabled. |
| 164.312(e)(1) | HIPAA | Transmission security | TLS enforced at ALB. RDS require_ssl in parameter group. |
| A.10.1 | ISO 27001 | Cryptographic controls | CMK policy defines encrypt/decrypt permissions. Rotation enabled. |
| A.12.4 | ISO 27001 | Logging and monitoring | CloudTrail, VPC Flow Logs, RDS logs, S3 access logs shipped to centralised logging. |
| A.13.1 | ISO 27001 | Network security | VPC with private subnets. Security groups default-deny. No public ingress to compute or data tiers. |

---

## Failure Modes and Mitigations

| Failure Mode | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Foundation state corruption | Low | Critical | S3 versioning on state bucket. DynamoDB locking. Manual approval gate on foundation pipeline. |
| Module breaking change propagates across org | Medium | High | Semantic versioning. Automated upgrade PRs. CI policy blocks teams >1 major version behind. |
| KMS key accidentally disabled | Low | Critical | MFA required for kms:DisableKey. CloudTrail alert on key state changes. 7-30 day deletion waiting period. |
| SSM parameter deleted or overwritten | Low | Medium | SSM parameter history retained. IAM restricts write access to foundation pipeline role only. |
| Team deploys raw aws_s3_bucket without module | Medium | Medium | Conftest/OPA policy rejects plans with raw S3 resources. PR review enforced. |
| State lock not released after failed apply | Medium | Low | terraform force-unlock documented in runbook. Alert on locks held >30 minutes. |
| Version drift across squads | High | Medium | Weekly CI job opens upgrade PRs. Dashboard shows version distribution across team configs. |
