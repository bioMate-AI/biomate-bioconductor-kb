# Incident Response Policy

| | |
|---|---|
| **Version** | 0.1 DRAFT |
| **Owner** | `[CONFIRM: Security owner]` |
| **Effective date** | `[CONFIRM]` |
| **Review cadence** | Annual (+ post-incident) |

## 1. Purpose
Define how BioMate detects, triages, responds to, and learns from security incidents. Supports CC7.3–CC7.5. Formalizes the existing operational runbook (`docs/runbooks/incident.md`).

## 2. Scope
Any event that compromises, or threatens to compromise, the confidentiality, integrity, or availability of the BioMate AI Assistant Services System or its data, including unauthorized access, data exposure, malware, denial of service, and PHI exposure.

## 3. Policy statements
1. **Definitions & severity.** Events are classified by severity (`[CONFIRM: e.g., SEV1 critical / SEV2 high / SEV3 moderate / SEV4 low]`) with defined criteria. An event that rises to high/critical system-wide is treated as an incident.
2. **Detection.** Incidents are detected via CloudWatch alarms (e.g., `biomate-auth-failures-alarm` → SNS), application audit logs (`audit_logs` security event types), user/customer reports, and vendor notifications.
3. **Intake & tracking.** Incidents are recorded and tracked in `[CONFIRM: ticketing system]` with a unique identifier, timeline, responders, and disposition. Written/informal lists are not sufficient as the incident population — records must be query-backed.
4. **Response phases.** Triage → contain → eradicate → recover → post-incident review, per the runbook. First-response actions and common root causes are documented in `docs/runbooks/incident.md`.
5. **Roles.** An incident commander is designated per incident; the security owner is accountable overall.
6. **Communication.** Internal escalation to management; external/customer notification as required by contract and law.
7. **Breach notification.** Suspected breaches involving personal data / PHI trigger the Breach Notification procedure, including the HIPAA 60-day timeline where applicable `[CONFIRM committed windows]`.
8. **Post-incident review.** A post-mortem is completed for high/critical incidents, capturing root cause and corrective actions (using the runbook template).
9. **Testing.** The incident response process is exercised at least `[CONFIRM: annually]` (tabletop or live).

## 4. Roles & responsibilities
- **Security owner** — owns the process, reporting, and post-mortems.
- **Incident commander** — coordinates a specific incident.
- **All personnel** — report suspected incidents promptly.

## 5. Enforcement & 6. Review
Per the Information Security Policy. Reviewed annually and after significant incidents.
