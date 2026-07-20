# 21 CFR Part 11 Compliance Plan

**Date:** 2026-07-19  
**Status:** Pre-compliance — audit trail exists; formal validation not started  
**Owner:** TBD (needs a QA lead or CSV consultant assigned)

---

## What 21 CFR Part 11 Actually Requires

21 CFR Part 11 (Title 21, Code of Federal Regulations, Part 11) is the FDA regulation that makes electronic records and electronic signatures legally equivalent to paper records and handwritten signatures in drug development. It applies to any computerised system used to create, modify, maintain, archive, retrieve, or transmit records required by FDA regulations.

**Key requirements:**

| Requirement | Description |
|-------------|-------------|
| **Audit trail** | Computer-generated, timestamped, tamper-evident record of all changes. Must capture who, what, when, and the original value before change. Cannot be deleted or modified by any user. |
| **Access controls** | Unique user IDs. Password complexity and expiry policies. System-enforced access limits by role. Documented procedure for granting, reviewing, and revoking access. |
| **Electronic signatures** | Two-component authentication (password + token, or biometric). Each signature cryptographically bound to the specific record being signed. Signature carries signer's full name, date/time, and the meaning of the signature (reviewed, approved, etc.). |
| **System validation** | IQ (Installation Qualification), OQ (Operational Qualification), PQ (Performance Qualification) — documented evidence that the system does what it claims, consistently, under real conditions. |
| **SOPs** | Written procedures covering how the system is used in a regulated context — change control, backup/restore, access management, training, incident response. |
| **Training records** | Evidence that all users have been trained on the system and relevant SOPs. |
| **Open/closed system controls** | BioMate is a closed system (access controlled). Specific requirements differ from open systems. |

---

## Current State — What BioMate Has Today

| Feature | Status | Notes |
|---------|--------|-------|
| Timestamped run records | ✅ | Every run has a UTC timestamp, user attribution, parameter log |
| Immutable output storage | ✅ | S3 with versioning; outputs not overwritten |
| User authentication | ✅ | Login system with unique user IDs |
| Parameter change log | ✅ | QC overrides and parameter edits recorded |
| Re-run hash | ✅ | Bit-identical re-run from a single hash |
| Reviewer sign-off (basic) | ✅ | Reviewer approval surface exists |
| Audit trail completeness | ⚠️ | Captures run-level events; unclear if all state changes (parameter edits mid-run, permission changes, config changes) are captured |
| Tamper-evident audit storage | ⚠️ | S3 versioning helps but not purpose-built; no cryptographic hash chain |
| Two-component e-signature | ❌ | Reviewer sign-off exists but is not a legally valid e-signature (no second factor, no cryptographic binding to the record) |
| Access control documentation | ❌ | Informal; no documented access review process |
| IQ/OQ/PQ validation package | ❌ | Not started |
| SOPs | ❌ | Not written |
| Training records system | ❌ | Not in place |

**Current marketing language (as of 2026-07-19):** "GxP-aligned audit trail" — accurate and defensible. "21 CFR Part 11 e-signature" language has been removed from index.html and features.html pending actual compliance.

---

## Gap Analysis

### Gap 1 — Audit Trail Completeness and Tamper-Evidence
**What's needed:** Every state-changing event in the system captured in an append-only log: parameter edits, permission changes, user provisioning/deprovisioning, configuration changes, failed login attempts. The log itself must be stored in a way that makes tampering detectable (cryptographic hash chain or WORM storage).

**Current gap:** Run-level events are captured. System-level events (admin actions, config changes) are likely not. No cryptographic hash chain.

**Effort:** 3–5 weeks engineering.

---

### Gap 2 — Electronic Signature Implementation
**What's needed:** A two-component signing flow where a reviewer:
1. Initiates a signature on a specific, versioned record
2. Re-authenticates (password + TOTP/hardware token — *not* just clicking "approve")
3. The signature is cryptographically bound to the record hash at signing time
4. The record cannot be modified after signing without breaking the signature
5. The signature carries: full legal name, date/time (UTC), and meaning (e.g., "reviewed and approved for submission")

**Current gap:** The reviewer sign-off button exists but is not a 21 CFR Part 11 signature. No second-factor re-authentication, no cryptographic binding.

**Effort:** 4–8 weeks engineering (re-auth flow, TOTP integration, record hashing, signature storage, UI).

---

### Gap 3 — System Validation Documentation (IQ/OQ/PQ)
This is the biggest gap and the one that takes the longest.

- **IQ (Installation Qualification):** Evidence that the system was installed correctly in its operating environment. Documents the infrastructure, software versions, configurations, and that they match the design specification.
- **OQ (Operational Qualification):** Evidence that the system operates as specified — every feature tested against written test scripts with expected and actual results recorded. This is essentially a formal test plan that becomes a permanent document.
- **PQ (Performance Qualification):** Evidence that the system performs consistently under real-world conditions — load testing, edge cases, long-run scenarios.

**Current gap:** Not started. This is primarily a documentation exercise but requires the engineering team to write test scripts, execute them with a witness, and maintain the records.

**Effort:** 3–6 months. Typically requires a CSV (computer system validation) consultant — budget $20–50k. Engineering team participates ~20% of the time during OQ execution.

---

### Gap 4 — Standard Operating Procedures (SOPs)
Minimum SOPs needed for Part 11 compliance:

1. SOP-001: System Access Management (provisioning, periodic review, revocation)
2. SOP-002: Change Control (how software changes are tested and deployed in a validated state)
3. SOP-003: Backup and Disaster Recovery
4. SOP-004: Incident Response and Deviation Handling
5. SOP-005: User Training and Competency Assessment
6. SOP-006: Electronic Records and Audit Trail Management
7. SOP-007: Electronic Signature Policy

**Effort:** 4–8 weeks to draft; requires review and approval from someone with GxP SOP experience.

---

### Gap 5 — Training Records System
**What's needed:** A system (can be simple — even a spreadsheet with controlled access) that records which users have been trained on which SOPs, when, and with what assessment. Training must be completed before a user can use the system in a regulated context.

**Effort:** 1–2 weeks to set up; ongoing operational overhead.

---

## Phased Roadmap

### Phase 1 — Foundation (Months 1–2) — Engineering-led
*Goal: Make the technical foundation audit-ready. No external consultant needed yet.*

- [ ] Extend audit trail to capture all state-changing events (not just run events)
- [ ] Implement cryptographic hash chain for audit log integrity (or switch to WORM storage)
- [ ] Implement two-factor re-authentication for reviewer sign-off
- [ ] Record cryptographic hash of the signed record alongside each signature
- [ ] Define and document the signature meaning vocabulary (reviewed / approved / rejected)
- [ ] Build audit trail export in FDA-compatible format (CSV + XML)
- [ ] Implement access control logging (who was granted/revoked access, when, by whom)

**Deliverable:** A technically defensible audit trail and a reviewable (not yet validated) e-signature flow.

---

### Phase 2 — Documentation Preparation (Months 2–4) — Engineering + QA
*Goal: Produce the raw material needed for the validation package.*

- [ ] Write the System Design Specification (SDS) — formal description of what the system does, its intended use, and its regulatory context
- [ ] Write Functional Specifications for audit trail, e-signature, access control
- [ ] Write User Requirements Specification (URS) — what regulated users need the system to do
- [ ] Draft SOP-001 through SOP-007 (see Gap 4 above)
- [ ] Establish a training records system
- [ ] Train all staff who will be involved in the validation

**Resource:** Hire or contract a CSV consultant by month 2. Budget $20–50k for months 3–12.

---

### Phase 3 — Validation Execution (Months 4–8) — CSV Consultant-led
*Goal: Execute and document IQ/OQ/PQ.*

- [ ] IQ: Document infrastructure, software versions, configurations — sign off
- [ ] OQ: Write and execute test scripts for every specified function. Record expected vs. actual. Any failures become deviations, resolved and re-tested.
- [ ] PQ: Execute representative real-world workflows under monitored conditions. Document results.
- [ ] Resolve all OQ/PQ deviations
- [ ] Produce completed validation report

**Deliverable:** A completed validation package that can be provided to an enterprise customer or FDA inspector on request.

---

### Phase 4 — Go-Live and Maintenance (Month 9+)
- [ ] Update marketing language from "GxP-aligned" to "21 CFR Part 11 compliant" (only after Phase 3 complete)
- [ ] Implement change control process — every software change to the validated system requires impact assessment and re-qualification of affected functions
- [ ] Annual periodic review of the validated state
- [ ] Maintain training records for all users

---

## Resource Requirements

| Resource | When | Cost Estimate |
|----------|------|---------------|
| Engineering time (Phase 1) | Months 1–2 | ~200 hrs (1 engineer, 10 weeks at 50%) |
| Engineering time (Phase 2) | Months 2–4 | ~80 hrs (documentation support) |
| CSV consultant | Months 3–8 | $20,000–50,000 |
| QA lead (part-time or fractional) | Months 2–12 | $30,000–80,000/yr fractional |
| Ongoing change control overhead | Month 9+ | ~5–10% engineering overhead per release |

**Total one-time cost estimate:** $50,000–130,000  
**Timeline to compliant:** 9–12 months with consistent effort

---

## When to Re-add the 21 CFR Part 11 Claim

Only after **all three** of the following are true:
1. Phase 3 (IQ/OQ/PQ) is complete and the validation report is signed off
2. SOPs are in place and training records exist for all system users
3. A change control process is active (so the validated state is maintained as the software evolves)

Until then, "GxP-aligned audit trail" and "audit-ready records" accurately describe the current capability without creating a compliance liability.

---

## Related Documents

- `docs/` — general BioMate project documentation
- `frontend/client/src/components/nextflow-workflow-viewer.tsx` — workflow execution audit trail display
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` — run state and audit logging
