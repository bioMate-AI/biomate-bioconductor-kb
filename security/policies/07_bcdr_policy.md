# Business Continuity & Disaster Recovery Policy

| | |
|---|---|
| **Version** | 0.1 DRAFT |
| **Owner** | `[CONFIRM: Engineering lead]` |
| **Effective date** | `[CONFIRM]` |
| **Review cadence** | Annual (+ test at least annually) |

## 1. Purpose
Ensure BioMate can recover the BioMate AI Assistant Services System and its data after a disruption. Supports CC7.5 (and Availability criteria if scope expands).

## 2. Scope
Production application, data stores (RDS, S3, ElastiCache), and workflow-execution infrastructure in AWS.

## 3. Policy statements
1. **Backups.** Amazon RDS uses automated backups (`[CONFIRM retention — recon cited 7-day and 15-day; state the actual value]`); S3 production data and backups are stored in dedicated buckets (`biomate-production-backups-399683337364`) with encryption; the compliance-evidence bucket is versioned.
2. **Recovery objectives.** `[CONFIRM: define RTO and RPO]` for the production application and data stores.
3. **Known availability limitations.** The current topology is `[CONFIRM: single-AZ EC2 / RDS / single-node Redis]`; failover for these is `[CONFIRM: manual]`. Multi-AZ improvements are `[CONFIRM: planned/complete — do not claim as operating if not]`. These limitations are documented as accepted risks in the risk register until remediated.
4. **Restore testing.** Backup restoration is tested at least `[CONFIRM: annually]`, and results are documented and retained as evidence.
5. **Continuity.** Key personnel and contacts, and the steps to restore service, are documented; the incident response process governs the response phase.
6. **Data durability.** Reliance on AWS managed-service durability (S3, RDS) is documented as a CSOC in the System Description (DC7).

## 4. Roles & responsibilities
- **Engineering lead** — owns backups, recovery procedures, and restore tests.
- **Security owner** — ensures BC/DR is covered in the risk assessment.

## 5. Enforcement & 6. Review
Per the Information Security Policy. Reviewed and tested at least annually.
