# System Description — Management Draft (SOC 2 Type 2, Security)

> **STATUS: MANAGEMENT WORKING DRAFT — not for submission as-is.**
> Per Sentry's guide and AICPA independence rules, **management authors and owns this description**; the auditor only evaluates it. This draft is a *starting point* built from BioMate's actual architecture (cited in `docs/20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md` and code). Before submission, management must:
> 1. Replace every `[CONFIRM]` with a verified fact (or delete the statement).
> 2. Have each control owner confirm each described control is **performed as written** during the observation period.
> 3. Remove anything not true *today* — SOC 2 tests reality, not plans.
> 4. Run the guide's "Management's self-review checklist" and sign `06_MANAGEMENT_ACKNOWLEDGMENT.md`.
>
> **Writing rules enforced in this draft (the 8 "tells" that get a description returned):** no bracketed placeholders left in final; no technology we don't run; no verbatim Vanta template phrasing; no aspirational/unfalsifiable tense ("committed to," "best-in-class," "will implement"); no control text contradicted by evidence; no copied CUEC blocks; no orphaned/missing subservice orgs; boundary + changes stated explicitly. Third person only (no I/we/us/our/your).

**System name:** BioMate AI Assistant Services System
**Service organization:** BioMate AI LLC (Texas)
**Trust Services Category in scope:** Security (Common Criteria), 2017 TSC (revised 2022)
**Observation period:** `[CONFIRM]`

---

## DC1 — Types of services provided
BioMate AI LLC operates the BioMate AI Assistant Services System, a cloud-hosted software-as-a-service platform that lets user entities (`[CONFIRM: describe user entities — e.g., biotech/pharma research teams, bioinformaticians]`) run bioinformatics, drug-discovery, and clinical-research workflows through an AI assistant. The platform interprets natural-language requests, routes them to indexed or generated Nextflow/Bioconductor workflows, executes those workflows on managed cloud compute, streams progress back to the user, and returns results and reports.

Services within the examination boundary:
- The web application and API served at `biomate.ai` (the "BioMate AI Assistant").
- AI-assisted workflow selection, parameter extraction, and report/narrative generation.
- Workflow execution on managed cloud compute and the storage of user inputs and outputs.
- User account management, authentication, and billing/quota enforcement.

`[CONFIRM: whether the platform is offered to active paying customers or is pre-customer during the period.]`

Privacy is not in the examination scope; data-processor/controller designations are therefore not asserted here. `[CONFIRM: if Confidentiality is later added, address data-handling commitments.]`

## DC2 — Principal service commitments and system requirements
Service commitments are the security promises BioMate makes to user entities; system requirements are the internal standards set to meet them. Each statement below must trace to a real MSA/SLA/DPA/published policy — `[CONFIRM against the executed customer contract and published security statement; delete any not actually committed]`:

- **Access control:** Access to production systems and customer data is restricted to authorized BioMate personnel and service accounts, enforced through AWS IAM and application role tiers (anonymous / authenticated user / admin / service account).
- **Encryption:** Customer data is encrypted in transit (TLS 1.2 or higher, terminated at the AWS Application Load Balancer; `rediss://` TLS to Redis) and at rest (AES-256 via AWS KMS for RDS and S3-KMS buckets; SSE-S3 for working buckets; AES-256-GCM application-layer encryption for stored API keys).
- **Authentication:** User authentication uses JSON Web Tokens with `httpOnly`/`sameSite=strict` session cookies and bcrypt (12 rounds) password hashing; sessions expire after 15 minutes of inactivity. `[CONFIRM: MFA — state the exact production status; do not claim enforced MFA unless it is live during the period.]`
- **Logging & monitoring:** Security-relevant events are recorded in an application `audit_logs` store and AWS CloudTrail (`biomate-audit-trail`, multi-region, log-file validation); authentication-failure conditions raise a CloudWatch alarm routed to BioMate via SNS.
- **Change management:** Production changes are made through peer-reviewed pull requests on protected branches with a required CI test suite and health-gated, auto-rollback deployments.
- **Breach notification:** `[CONFIRM: state the actual notification window committed to customers, e.g., "within X hours/days of confirmation"; source it to the contract/policy.]`

## DC3 — System components (infrastructure, software, people, procedures, data)
*(Written to the guide's "customized — accepted" standard: specific providers, regions, roles, frequencies, mechanisms.)*

**Infrastructure.** The production environment runs in Amazon Web Services (account 399683337364), primarily in region us-west-2 (with us-east-1 used for cryo-EM processing). Compute consists of an EC2 instance (`i-06696b0d91f4346e0`, us-west-2a) hosting the application tier, and AWS Batch job queues (`galaxy-cloud-queue` and `galaxy-cloud-queue-gpu`) for workflow execution. Ingress terminates TLS 1.2+ at an Application Load Balancer. Network access is controlled by AWS security groups (`biomate-sg`); administrative access to hosts is brokered through AWS Systems Manager Session Manager rather than open SSH, with port 22 restricted to `[CONFIRM current management IP/CIDR]` for break-glass. Container images are stored in Amazon ECR. `[CONFIRM: single-AZ vs. multi-AZ — state the actual topology; note single-AZ is an availability matter, not a Security-criterion issue.]`

**Software.** The application tier comprises a Node.js/Express + React (Vite) frontend and a Python (Galaxy) backend served by gunicorn, with a Nextflow executor that dispatches DSL2 workflows to AWS Batch. Application security middleware includes Helmet, CORS, CSRF protection, rate limiting, and a 15-minute session-timeout enforcer.

**People.** `[CONFIRM: list the roles that operate the system — e.g., founder/engineering lead as production administrators, plus any contractors — and how many. Name the roles, not individuals.]` A service account (`galaxy-dev`) performs workflow automation and AWS resource management; `biomate-admin` holds administrative access; `biomate-ses-smtp` is limited to email.

**Procedures.** Change management (PR review + CI + gated deploy), access provisioning/de-provisioning `[CONFIRM: describe the actual onboarding/offboarding steps and where they are ticketed]`, incident response (per `docs/runbooks/incident.md`), evidence collection (automated audit-log export to `s3://biomate-compliance-evidence-399683337364/` on a daily systemd timer), and backup/restore of RDS and S3.

**Data.** User-supplied research data (omics files such as FASTQ/BAM/VCF/h5ad, chemistry inputs such as SMILES/PDB, and any de-identified clinical metadata a user chooses to upload), user account records, workflow execution records, audit logs, and billing/quota data. Customer data at rest resides in Amazon RDS (PostgreSQL) and Amazon S3; session and quota state resides in ElastiCache Redis. A PHI-detection guardrail strips 18-identifier patterns (SSN, DOB, MRN, Patient ID, NPI, insurance) from text before it is sent to any LLM and logs a hash rather than the value.

**Explicitly out of the system boundary** (`[CONFIRM/adjust]`): the marketing website; the isolated laboratory instrument network (CryoSPARC, Oxford Nanopore/MinKNOW, Thermo EPU, SiLA2 devices on a segregated lab VLAN with no internet exposure); the local Ollama offline LLM fallback; and any 21 CFR Part 11 electronic-records validation scope.

## DC4 — System incidents in the period
`[CONFIRM]` For the observation period, state affirmatively either: (a) "No incidents occurred during the period that resulted from a control that was not suitably designed or operating effectively, or that otherwise caused a significant failure to achieve a service commitment or system requirement," **or** (b) disclose each qualifying incident's nature, timing, extent, effect, and disposition. **Note:** an incident visible in ticketing, CloudWatch, or Vanta evidence that is omitted here is a description misstatement. Reconcile against `audit_logs`, the CloudWatch auth-failure alarm history, and the IR runbook before asserting "none."

## DC5 — Applicable Trust Services Criteria and related controls
The examination covers the Security category (Common Criteria CC1–CC9). Controls actually operated (to be reconciled to the Vanta control set and confirmed by owners; map each to the criterion it supports):
- **CC6 (Logical access):** AWS IAM with least-privilege roles and a deactivated root key; application role tiers; JWT auth with 15-minute idle timeout; bcrypt password hashing; SSM-brokered host access; IP-restricted break-glass SSH. `[CONFIRM: MFA enforcement; recurring access reviews cadence — do not claim if not operating.]`
- **CC6 (Encryption):** TLS 1.2+ in transit; AES-256/KMS at rest (RDS, S3-KMS), SSE-S3 (working buckets), AES-256-GCM for stored secrets; annual KMS key rotation.
- **CC7 (Operations/monitoring):** CloudTrail multi-region with log validation; CloudWatch alarm on auth failures → SNS; `audit_logs` (90-day hot in PostgreSQL, 6-year cold in S3 Glacier IR); `[CONFIRM: vulnerability scanning cadence — dependency scans + OWASP ZAP.]`
- **CC8 (Change management):** protected branches, required CI, peer-reviewed PRs, health-gated deploys with automatic rollback.
- **CC1–CC5, CC9 (control environment, communication, risk assessment, monitoring, risk mitigation):** `[CONFIRM: these depend on the formal risk assessment, org chart/roles, policies, and vendor management — currently gaps; write these only once the underlying artifacts exist.]`

Mapping controls to criteria is not required but is requested by Sentry and speeds review — maintain it in Vanta and reference it here.

## DC6 — Complementary user entity controls (CUECs)
See `05_CUEC_MAPPING_TABLE.md`. Most SaaS organizations need very few genuine CUECs; BioMate should disclose only controls that user entities must operate for BioMate's stated commitments to hold, each traced to a commitment (DC2) and a complementary BioMate control. Generic "user entities should keep software patched" statements are not CUECs and will be returned.

## DC7 — Subservice organizations
**Amazon Web Services** is the primary subservice organization, providing the physical and environmental security of the data centers and the security of the managed services BioMate consumes (EC2, RDS, S3, ElastiCache, AWS Batch, Bedrock, Lambda, ECR, KMS, CloudTrail, SES). **Carve-out method** is elected `[CONFIRM]`. Complementary Subservice Organization Controls (CSOCs) BioMate assumes AWS operates include: physical/environmental data-center security; hypervisor and hardware isolation; availability and durability of the managed data stores; and key-management infrastructure for KMS. BioMate monitors AWS through its SOC 2 / ISO reports (AWS Artifact) `[CONFIRM cadence of review]`. State that BioMate's commitments can be achieved only if these CSOCs are suitably designed and operating effectively.

Other third parties consumed by the system (classify each as subservice org vs. vendor): Stripe (payments), Google (Gemini LLM), OpenAI (GPT-4o LLM), AWS SES (email), Google Analytics, Vanta (compliance tooling), and Workstreet (`[CONFIRM role]`). `[CONFIRM which, if any, warrant carve-out treatment vs. vendor-management treatment.]`

## DC8 — Criteria not relevant
For a Security-only examination, all Common Criteria are ordinarily relevant. If any specific criterion is determined not relevant to the system, identify it and explain why (a policy prohibiting an activity does not make a criterion irrelevant, and outsourcing to a carved-out subservice org does not remove relevance). Otherwise state that all applicable Common Criteria are relevant. Availability, Confidentiality, Processing Integrity, and Privacy are **not in the examination scope** (a scope election), which is distinct from "not relevant."

## DC9 — Significant changes during the period
`[CONFIRM]` Disclose significant changes to the system and controls during the observation period with dates and before/after detail (cloud migrations, security-leadership changes, new subservice organizations, architectural rewrites, and control rollouts such as MFA-in-production, VPN/access-broker changes, or the secrets-manager migration all qualify). If there were none, state that affirmatively. Do not let the description read as though the period were static if the evidence shows a change.
