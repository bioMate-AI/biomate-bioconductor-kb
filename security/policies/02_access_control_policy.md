# Access Control Policy

| | |
|---|---|
| **Version** | 0.1 DRAFT |
| **Owner** | `[CONFIRM]` |
| **Effective date** | `[CONFIRM]` |
| **Review cadence** | Annual |

## 1. Purpose
Define how access to BioMate systems and data is granted, managed, reviewed, and revoked, so that access is limited to authorized individuals on a least-privilege basis. Supports CC6.1–CC6.3.

## 2. Scope
All production systems (AWS account 399683337364), the application, data stores (RDS, S3, ElastiCache), source control (GitHub), and supporting SaaS. Applies to human users and service accounts.

## 3. Policy statements
1. **Identity.** `[CONFIRM: primary IdP — Google Workspace / Entra ID]` is the source of identity; in-scope tools are federated to the IdP where supported (`[CONFIRM: AWS, GitHub, HRIS]`). Tools not federated are documented with a compensating control.
2. **Authentication.** Application users authenticate with JWT + `httpOnly`/`sameSite=strict` cookies; passwords are stored with bcrypt (12 rounds); sessions expire after 15 minutes of inactivity. `[CONFIRM: MFA is required for administrative and IdP access — state actual production status; do not claim if not enforced.]`
3. **Least privilege & roles.** Application access follows role tiers (anonymous, authenticated user, admin, service account). AWS access uses IAM roles/users scoped to least privilege; the root account access key is deactivated and root is used only for break-glass with MFA.
4. **Service accounts.** Service accounts (e.g., `galaxy-dev`, `biomate-ses-smtp`) are documented, scoped to the minimum permissions required, and not used for interactive human login.
5. **Production access brokering.** Host access is brokered through AWS Systems Manager Session Manager; direct SSH is not exposed to the internet, and port 22 is restricted to `[CONFIRM management IP/CIDR]` for break-glass. `[CONFIRM: VPN/Tailscale broker status.]`
6. **Provisioning & deprovisioning.** Access is granted on documented approval at onboarding and revoked within `[CONFIRM: e.g., 24 hours]` of termination or role change. Requests and revocations are tracked in `[CONFIRM: ticketing/IdP]`.
7. **Access reviews.** Access to production systems and data is reviewed at least `[CONFIRM: quarterly/semi-annually — state the real cadence; do not claim quarterly if not performed]`, with results retained as evidence.
8. **Shared accounts.** Shared human accounts are prohibited. `[CONFIRM none exist.]`
9. **Password/secret hygiene.** Application secrets are stored in AWS Secrets Manager or environment files on the host (migration to Secrets Manager in progress `[CONFIRM]`); secrets are never committed to source control.

## 4. Roles & responsibilities
- **Security owner** — approves access, runs access reviews.
- **Engineering** — implements IAM/IdP configuration, service-account scoping.
- **Managers** — request/approve access for their reports; notify of terminations.

## 5. Enforcement & 6. Review
Non-compliance handled per the Information Security Policy. Reviewed annually.
