# Encryption & Key Management Policy

| | |
|---|---|
| **Version** | 0.1 DRAFT |
| **Owner** | `[CONFIRM: Engineering lead]` |
| **Effective date** | `[CONFIRM]` |
| **Review cadence** | Annual |

## 1. Purpose
Define encryption standards and key-management practices for BioMate data and systems. Supports CC6.1.

## 2. Scope
All Restricted and Confidential data in transit and at rest, and the keys and secrets protecting them.

## 3. Policy statements
1. **In transit.** External traffic uses TLS 1.2 or higher, terminated at the AWS Application Load Balancer. Redis connections use TLS (`rediss://`, transit-encryption required). RDS connections use TLS.
2. **At rest.** AES-256 is used at rest: RDS and KMS-encrypted S3 buckets via AWS KMS; working buckets via SSE-S3; stored secrets/API keys via application-layer AES-256-GCM.
3. **Algorithms.** Approved: AES-256-GCM (field encryption), TLS 1.2+ (transport), bcrypt (password hashing, 12 rounds), SHA-256 (integrity/audit hashing), HS256 (JWT). Deprecated/weak algorithms are prohibited.
4. **Key management.** Encryption keys are managed in AWS KMS (customer-managed keys) with annual rotation enabled. Application secrets are stored in AWS Secrets Manager (`biomate/…`) or, during migration, in host environment files `[CONFIRM migration status]`; secrets are never committed to source control.
5. **Access to keys.** Access to KMS keys and Secrets Manager is least-privilege via IAM and audit-logged in CloudTrail.
6. **Exceptions.** The lab-instrument network uses `insecure=True` gRPC and plain HTTP to devices; this is an accepted risk documented in the risk register because the lab VLAN is isolated with no internet exposure and is `[CONFIRM: out of the audit boundary]`.

## 4. Roles & responsibilities
- **Engineering lead** — owns KMS/Secrets Manager configuration and rotation.
- **Security owner** — verifies compliance during reviews.

## 5. Enforcement & 6. Review
Per the Information Security Policy. Reviewed annually.
