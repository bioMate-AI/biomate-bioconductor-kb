# SOC 2 Type 2 + HIPAA — Package Summary for Engineering Review

**For:** BioMate engineering team
**From:** Yaoyun (compliance workstream)
**Purpose:** alignment + **content double-check**. This package was drafted largely from the repo/config, so before any of it goes to the auditor, **engineering needs to verify the technical facts are current and correct.**
**Where it lives:** `security/` (branch `security/soc2-hipaa-package`).

---

## 1. What's happening
BioMate is pursuing a **SOC 2 Type 2 (Security / Common Criteria only)** examination with **Sentry Assurance**, managed on **Vanta**, funded via **Workstreet**, plus a parallel **HIPAA** readiness track. This folder is the full prep package: contract review, readiness gap analysis, the auditor's scoping questionnaire (filled), a management-authored System Description draft, a policy pack, a risk assessment, a vendor register, a control-to-TSC matrix, and evidence templates.

Start at `security/README.md`; the plan is `00_PLAN_SOC2_HIPAA.md`.

## 2. Three things that shape everything
1. **Management writes the System Description — the auditor won't, and Vanta template language gets it rejected.** So `04_SYSTEM_DESCRIPTION_DRAFT.md` is built from our *real* architecture and needs your verification.
2. **SOC 2 has no remediation window.** Controls must be live + evidenced from day one of the observation period — so we set that start date only after we're genuinely ready.
3. **Overstated controls = audit findings.** Nothing in the package claims a control we don't run (e.g., MDM is *not* asserted). Every unverified fact is marked `[CONFIRM]`. **Do not "fix" a `[CONFIRM]` by asserting something we don't actually do — tell us the real state.**

## 3. What I need from engineering (the double-check)
Please verify each fact below against production reality and reply inline (owner + answer). Full list + tracker in `11_ACTION_TRACKER.md` (E1–E15).

| # | Verify | Repo said | Your answer |
|---|---|---|---|
| E1 | Primary **IdP** + federated tools | not found in repo | |
| E3 | **MFA enforced in prod?** | prototype only (70/70 tests, not integrated) | |
| E4 | **VPN / access broker** now | SSM confirmed; VPN "planned Q3 2026" | |
| E5 | **MDM** on laptops? | none found | |
| E6 | **RDS backup retention** | conflicting 7-day vs 15-day | |
| E7 | **Single-AZ vs multi-AZ** (EC2/RDS/Redis) | single-AZ | |
| E8 | **Secrets Manager migration** complete? | some secrets still in host `.env` | |
| E9 | **Vuln scanning** cadence + result location | dep scans + monthly ZAP (unconfirmed) | |
| E10 | **Change SoD** — PR approval records distinct reviewer/approver? | protected branches + CI confirmed | |
| E13 | **Lab VLAN** in scope or carved out? | isolated, insecure gRPC/HTTP | |
| E14 | **run_code sandboxing** / prompt-injection controls | not confirmed | |
| E15 | Break-glass **SSH IP/CIDR** current | `104.63.31.236/32` (may be stale) | |

Non-eng `[CONFIRM]`s (Yaoyun/HR): HRIS (E2), background checks (E11), customer status pre/active (E12).

## 4. What the package says about our posture (honest)
**Strong / already true (the technical spine):**
- Encryption everywhere — TLS 1.2+ in transit; AES-256/KMS at rest (RDS, S3), AES-256-GCM for stored secrets; annual KMS rotation.
- Access — AWS IAM least-privilege, root key deactivated, SSM-brokered host access (no open SSH), JWT+bcrypt+15-min timeout, app role tiers.
- Logging/monitoring — CloudTrail multi-region, CloudWatch auth-failure alarm→SNS, `audit_logs` (90-day hot / 6-year Glacier IR).
- Change management — protected branches, required CI, peer-reviewed PRs, health-gated deploy + auto-rollback.
- AI data protection — PHI-stripping guardrail before LLM calls; Claude via AWS Bedrock BAA.

**Real gaps engineering owns (not draftable — need doing):**
- ❌ **Penetration test** (P3-1)
- ❌ **BC/DR restore test** (P3-2) — backups exist but restore is unproven
- ◐ **MFA in production** (E3/P2-5)
- ◐ **Secrets Manager migration** finish (E8)
- ◐ **MDM / endpoint** decision (E5)
- ◐ **Vuln-scan cadence** made real + evidenced (E9)
- ◐ **Multi-AZ** (availability; only matters if we add the Availability TSC)

**Process gaps (mostly Yaoyun/Sec, with eng support):** control-owner assignment in Vanta, policy adoption + acknowledgment, access-review cadence, security-awareness training, vendor SOC 2/BAA collection, and the formal risk-assessment approval.

## 5. Specifically review these files for accuracy
- **`04_SYSTEM_DESCRIPTION_DRAFT.md`** (DC1–DC9) — the audited subject matter. Read DC3 (components) and DC5 (controls) closely; that's where architecture facts live.
- **`10_control_tsc_matrix.xlsx`** — every control mapped to CC1–CC9 with status; use it to reconcile the Vanta control set.
- **`03_scoping_questionnaire_FILLED.xlsx`** — the tech-stack answers going to the auditor.
- **`08_risk_register.xlsx`** — 20 risks; sanity-check ratings + that we haven't missed a real one.
- **`09_vendor_register.xlsx`** — confirm the subprocessor list is complete (did I miss any external service that touches prod data?).

## 6. How to give feedback
Comment on the PR (`security/soc2-hipaa-package`) or edit the files directly. Priority is the §3 table (E1–E15) — those block finalizing the System Description. Once those are answered, we resolve the `[CONFIRM]`s, adopt policies, drive Vanta readiness ≥85%, and only then set the observation-period start date.
