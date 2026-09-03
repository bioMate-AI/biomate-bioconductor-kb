# SOC 2 / HIPAA — Action Tracker

Single place to drive the engagement. Owners are **suggested** (`[CONFIRM]` and adjust). Priority: **P1** foundational/gating · **P2** readiness gate · **P3** supplemental. Status: ☐ open · ◐ in progress · ✅ done. Update as items move.

## Contract (do first)
| ID | Item | Owner | Pri | Target | Status | Depends on |
|---|---|---|---|---|---|---|
| C1 | Send 5-item clarification email to Sentry/Workstreet (`01`) | Yaoyun | P1 | | ☐ | — |
| C2 | Confirm BioMate has zero residual payment exposure (Workstreet) | Yaoyun | P1 | | ☐ | C1 |
| C3 | Clarify basis + owner of the 20%+100% reschedule fee | Yaoyun | P1 | | ☐ | C1 |
| C4 | Decide Type 1-then-2 vs. straight Type 2 + tentative period | Yaoyun | P1 | | ☐ | — |
| C5 | Confirm HIPAA path + whether to add Confidentiality/Availability TSC | Yaoyun | P1 | | ☐ | C1 |
| C6 | Confirm Sentry CPA-firm licensure | Yaoyun | P2 | | ☐ | C1 |
| C7 | Sign PSA + SOW once C1–C6 resolved | Yaoyun | P1 | | ☐ | C1–C6 |

## P1 — Foundational (gate the System Description + scheduling)
| ID | Item | Owner | Target | Status | Depends on |
|---|---|---|---|---|---|
| P1-1 | Validate + approve risk assessment (`08`); set owners/dates; load into Vanta | Sec owner | | ☐ | — |
| P1-2 | Reconcile Vanta control set to reality using `10`; **assign a named owner to every control** | Eng + Sec | | ☐ | P1-1 |
| P1-3 | Adopt policies (`policies/`): resolve `[CONFIRM]`, approve, publish, collect acknowledgments | Sec owner | | ☐ | — |
| P1-4 | Resolve the `[CONFIRM]` fact cluster (see Engineering section below) | Eng | | ☐ | — |

## P2 — Readiness gates (before scheduling fieldwork)
| ID | Item | Owner | Target | Status | Depends on |
|---|---|---|---|---|---|
| P2-1 | Complete vendor register (`09`): collect each SOC 2/ISO, confirm DPAs/BAAs | Sec owner | | ☐ | — |
| P2-2 | Stand up recurring evidence: access reviews (`templates/`), onboarding/offboarding tickets | Sec + Eng | | ☐ | P1-3 |
| P2-3 | Select + operate a security-awareness training tool; assign + track | Sec owner | | ☐ | — |
| P2-4 | Drive Vanta Control Readiness ≥ 85% | Sec owner | | ☐ | P1-2, P1-3 |
| P2-5 | Resolve MFA-in-prod, VPN/access-broker, MDM (operate + evidence, or don't claim) | Eng + Yaoyun (Google Workspace MFA) | | ☐ | P1-4 |

## P3 — Supplemental evidence
| ID | Item | Owner | Target | Status | Depends on |
|---|---|---|---|---|---|
| P3-1 | Commission penetration test | Sec owner | | ☐ | — |
| P3-2 | Perform + document BC/DR restore test (`policies/07`) | Eng | | ☐ | — |

## Description & kickoff (Phase D/E)
| ID | Item | Owner | Target | Status | Depends on |
|---|---|---|---|---|---|
| D1 | Finalize System Description (`04`) — replace all `[CONFIRM]`; owners verify each control | Yaoyun + owners | | ☐ | P1-2, P1-4 |
| D2 | Finalize CUEC mapping table (`05`) | Yaoyun | | ☐ | D1 |
| D3 | Run self-review checklist + sign Management Acknowledgment (`06`) | Yaoyun | | ☐ | D1, D2 |
| D4 | Submit description package to Sentry **≥10 business days before kickoff** | Yaoyun | | ☐ | D3 |
| D5 | Set observation-period start date (only after P2-4 ✅) | Yaoyun | | ☐ | P2-4 |
| D6 | Sign Readiness Attestation (only when `02` is all-✅) | Yaoyun | | ☐ | P1,P2 |
| D7 | Sign Management Representation Letter (end of fieldwork) | Yaoyun | | ☐ | fieldwork |

## Engineering `[CONFIRM]` cluster (the "content double-check" list)
These facts were pulled from the repo and **must be verified as current** before they go into the System Description / questionnaire:
| ID | Fact to verify | Owner | Status |
|---|---|---|---|
| E1 | Primary **IdP** (Google Workspace / Entra) + which tools are federated | Eng | ✅ (answered with caveats — two members on personal Gmail, gap documented) |
| E2 | **HRIS** in use (source of employee/contractor population) | Yaoyun | ✅ (no HRIS — founding team only; Google Workspace user list is the population source; formal HRIS deferred until headcount grows) |
| E3 | **MFA** — enforced in production? (repo shows prototype only) | Eng | ✅ (confirmed: NOT enforced — gap documented as P2-5) |
| E4 | **VPN / access broker** current state (SSM confirmed; VPN was "planned Q3 2026") | Eng | ✅ (SSM confirmed as access broker; no VPN deployed) |
| E5 | **MDM** — any workstation management? (none found in repo) | Eng | ✅ (confirmed: none — MDM-1 failing in Vanta) |
| E6 | **RDS backup retention** actual value (recon saw both 7-day and 15-day) | Eng | ✅ (confirmed: 7-day retention on both `biomate-postgres` (prod) and `biomate-test-galaxy` (test) via SSO admin query 2026-09-03) |
| E7 | **Single-AZ vs multi-AZ** current topology (EC2/RDS/Redis) | Eng | ✅ (confirmed: ALL single-AZ — EC2 us-west-2a, RDS `biomate-postgres` us-west-2b, RDS `biomate-test-galaxy` us-west-2a, Redis `biomate-redis-enc` us-west-2d; Multi-AZ disabled on all; AutoFailover disabled on Redis) |
| E8 | **Secrets Manager migration** status (some secrets still in host `.env`?) | Eng | ✅ (confirmed: partial — primary secrets in SM but `.env` fallback still active; not complete) |
| E9 | **Vulnerability scanning** cadence (dep scans + OWASP ZAP) + where results live | Eng | ✅ (Trivy on every PR → GitHub Code Scanning SARIF; Inspector running; informational only, not hard gate; no ZAP/Dependabot) |
| E10 | **Change-mgmt SoD** — does PR approval record a distinct reviewer/approver? | Eng | ✅ (fixed 2026-09-02: enforce_admins+dismiss_stale+last-push-approval set; 64 historical exceptions documented in Vanta) |
| E11 | **Background-check** process (if any) | Yaoyun | ✅ (no formal process — all current team members are co-founding partners; no third-party hires at this stage) |
| E12 | **Customer status** — pre-customer vs. active | Yaoyun | ✅ (pre-customer — internal beta/testing phase; no paying customers as of filing date) |
| E13 | **Lab VLAN** — in audit scope or carved out? | Eng | ✅ (carved out; no prod data access; out-of-scope in System Description) |
| E14 | **run_code sandboxing** / prompt-injection controls (for R-06) | Eng | ✅ (code complete as of 2026-09-01; SANDBOX_ENABLED=False in prod — not yet active) |
| E15 | Break-glass **SSH IP/CIDR** current value | Eng | ✅ (prod SG `biomate-sg`=`sg-0b2188a4d48d989b8` queried directly: 4 /32 IPs allowed on port 22: `104.63.31.236/32`, `172.58.49.122/32`, `172.58.48.213/32`, `172.58.53.46/32`) |
