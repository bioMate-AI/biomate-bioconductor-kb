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
| E1 | Primary **IdP** + federated tools | not found in repo | AWS IAM Identity Center is the IdP (SAML provider `AWSSSO_9ce4e5ae50e484e9_DO_NOT_DELETE` confirmed in IAM). GitHub Actions is federated to AWS via OIDC (`token.actions.githubusercontent.com`). Google Workspace is the probable upstream directory for AWS SSO but not programmatically confirmed. GitHub and Slack have no SSO/federation evidence. **Gap:** two team members (Georgiy Mamedaliev, Jian Lv) are on personal Gmail and outside Workspace management. |
| E3 | **MFA enforced in prod?** | prototype only (70/70 tests, not integrated) | NOT enforced. `mfa-service.ts` exists with 70 tests passing but MFA is user-optional — no middleware enforces it before granting access. Google Workspace MFA also not enforced (Vanta test failing as of 2026-09-02). Gap documented as P2-5. |
| E4 | **VPN / access broker** now | SSM confirmed; VPN "planned Q3 2026" | SSM Session Manager confirmed as the access broker (no open SSH). No VPN is deployed — remains planned, not delivered. Port 22 on biomate-sg is IP-restricted for break-glass only. |
| E5 | **MDM** on laptops? | none found | None. Confirmed via Vanta (MDM-1 control failing) and absence of any MDM config in repo. |
| E6 | **RDS backup retention** | conflicting 7-day vs 15-day | [CONFIRM] — galaxy-dev IAM user lacks rds:DescribeDBInstances permission. Must be verified in AWS console by someone with RDS access. |
| E7 | **Single-AZ vs multi-AZ** (EC2/RDS/Redis) | single-AZ | EC2 instance (`i-06696b0d91f4346e0`) confirmed in us-west-2a (single AZ). RDS and Redis AZ configuration cannot be confirmed via current credentials — verify in AWS console. |
| E8 | **Secrets Manager migration** complete? | some secrets still in host `.env` | Partial. Primary secrets (galaxy-env bundle, RDS password, billing keys) are in Secrets Manager. However: (1) deploy.sh has a fallback to `/opt/biomate/.env` if SM fetch fails, so `.env` is still actively maintained; (2) `.env.example` contains `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` — unclear if static keys are fully eliminated. Migration is not complete. |
| E9 | **Vuln scanning** cadence + result location | dep scans + monthly ZAP (unconfirmed) | Trivy runs on every PR; results uploaded to GitHub Code Scanning (SARIF format) — confirmed in `.github/workflows/ci-tests.yml`. Amazon Inspector is running (EventBridge managed rule `DO-NOT-DELETE-AmazonInspectorEc2ManagedRule` confirmed). **However:** Trivy is informational only — explicitly NOT a hard merge gate (confirmed by comment in CI config). No DAST/ZAP confirmed. No Dependabot. |
| E10 | **Change SoD** — PR approval records distinct reviewer/approver? | protected branches + CI confirmed | As of 2026-09-02: YES — `enforce_admins=true`, `dismiss_stale_reviews=true`, `require_last_push_approval=true` set on both biomate and stack repos. Historical gap: 64 PRs merged without approval Aug 4–Sep 1 2026, acknowledged as exceptions in Vanta with documented reason (small team, controls not yet enforced, no PHI risk). |
| E13 | **Lab VLAN** in scope or carved out? | isolated, insecure gRPC/HTTP | Carved out. No code or infra evidence of lab VLAN accessing production data. System Description correctly lists it as out of scope. Confirm with team that lab instruments are on an isolated network with no production data access. |
| E14 | **run_code sandboxing** / prompt-injection controls | not confirmed | Code complete (compute-platform-v2, Stages 1–4 merged 2026-09-01). `SANDBOX_ENABLED` defaults to `False` — sandboxed execution is NOT active in production as of 2026-09-02. Cannot assert sandboxed execution for the observation period start. |
| E15 | Break-glass **SSH IP/CIDR** current | `104.63.31.236/32` (may be stale) | **Confirmed (production SG).** `biomate-sg` (`sg-0b2188a4d48d989b8`) is the production security group used by EC2 `i-06696b0d91f4346e0`. Port 22 allows 4 CIDRs: `104.63.31.236/32`, `172.58.49.122/32`, `172.58.48.213/32`, `172.58.53.46/32`. All 4 are individual /32 IPs (team members). |

Non-eng answers (Yaoyun, 2026-09-03):
- **E2 (HRIS):** No HRIS system in use. Team size is small (founding partners only); formal HRIS will be adopted when headcount grows. Employee population is derivable from the Google Workspace user list.
- **E11 (Background checks):** No formal background-check process. All current team members are co-founders/partners. No third-party hires requiring background screening at this stage.
- **E12 (Customer status):** Pre-customer — platform is in internal beta/testing phase. No paying customers as of the filing date.

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
