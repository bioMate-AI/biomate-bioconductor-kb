# Incident Response Tabletop Exercise — Meeting Minutes

**Date:** 2026-09-02  
**Duration:** ~30 minutes  
**Participants:**
- Yaoyun Zhang (yaoyun.zhang@biomate.ai) — Incident Commander
- Jian Lv (soda.lj@gmail.com) — Technical Lead

**Facilitator:** Internal (Yaoyun Zhang)  
**Document owner:** Yaoyun Zhang

---

## Objective

Validate BioMate AI's Incident Response Plan by walking through a realistic security incident scenario. Identify process gaps and establish action items for remediation.

---

## Scenario

> GuardDuty triggered an alert on 2026-09-02: an AWS Access Key associated with account `399683337364` was observed making `s3:ListBuckets` and `s3:GetObject` API calls from an unknown external IP address (`185.220.101.x`, identified as a Tor exit node).

---

## Exercise Walkthrough

### Step 1 — Detection & Initial Triage
**Q: How do you identify which key was compromised and who owns it?**

The team would log into the AWS Console → IAM → Access Keys to identify the key by its Access Key ID (visible in the GuardDuty finding) and determine which IAM user or role it belongs to.

### Step 2 — Containment
**Q: What is the immediate action after identifying the key?**

Immediately deactivate the key in IAM before continuing the investigation. Investigation continues in parallel via CloudTrail — containment is not delayed to complete the log review.

### Step 3 — Impact Assessment
**Q: How do you determine whether user data was accessed?**

Query CloudTrail for all API calls made by the compromised key's `userIdentity`. Filter for `s3:GetObject` events targeting production buckets (user-uploaded bioinformatics files, workflow outputs, PDF reports).

**Finding in this exercise:** CloudTrail showed only `ListBuckets` and `ListObjects` calls. No `GetObject` events were recorded. User data was not read or exfiltrated.

### Step 4 — Notification Decision
**Q: Is user or regulatory notification required?**

Decision: **Yes — proactively notify affected users** even though no data was read. BioMate AI's policy is to maintain full transparency. Notification will include:
- A complete timeline of the incident
- Confirmation that no data was accessed
- Steps taken to remediate and prevent recurrence

HIPAA breach notification threshold was not met (no PHI accessed), but voluntary disclosure was chosen in the interest of user trust.

### Step 5 — Root Cause Analysis
**Q: How did the key get compromised?**

Root cause was not definitively established during this exercise. The team identified three plausible vectors:
1. Accidental commit of credentials to a GitHub repository (including git history)
2. Developer local environment leak (`.env` file, shell history)
3. External attack via phishing or social engineering

A full post-incident investigation would be required to determine the actual vector.

### Step 6 — Roles & Responsibilities
| Role | Owner | Responsibilities |
|---|---|---|
| Incident Commander | Yaoyun Zhang | Declare incident, coordinate response, notify users, write post-mortem |
| Technical Lead | Jian Lv | Revoke key, CloudTrail forensics, Secrets Manager migration, secret scanning |

---

## Gaps Identified

1. **No secret scanning in CI/CD** — PRs can currently be merged with hardcoded credentials without automated detection
2. **Static AWS Access Keys still in use** — migration to Secrets Manager + IAM roles is incomplete
3. **No pre-defined user notification template** — drafting a breach notification email took time during the exercise

---

## Action Items

| # | Action | Owner | Due |
|---|---|---|---|
| 1 | Enable GitHub secret scanning on all repos (free, built-in) | Jian Lv | 2026-09-09 |
| 2 | Scan git history for committed secrets (`truffleHog` / `git-secrets`) | Jian Lv | 2026-09-09 |
| 3 | Complete migration of remaining static AWS keys to Secrets Manager | Jian Lv | 2026-09-30 |
| 4 | Draft user breach notification email template | Yaoyun Zhang | 2026-09-16 |
| 5 | Schedule next tabletop exercise | Yaoyun Zhang | 2027-03-01 |

---

## Exercise Outcome

The team successfully walked through all phases of the Incident Response Plan: detection, containment, impact assessment, notification decision, and root cause analysis. The IR Plan was validated as operable. Three process gaps were identified and assigned as action items.

**Overall assessment:** IR Plan is functional. Key improvements needed in automated secret detection and static credential elimination.

---

*This document serves as evidence of BioMate AI's annual incident response plan test per IRO-1 (SOC 2) and the Incident Response Plan policy approved 2026-07-27.*
