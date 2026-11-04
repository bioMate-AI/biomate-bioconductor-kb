# Information Security Policy

| | |
|---|---|
| **Version** | 0.1 DRAFT |
| **Owner** | `[CONFIRM: e.g., CEO / Security Officer]` |
| **Approved by** | `[CONFIRM]` |
| **Effective date** | `[CONFIRM]` |
| **Review cadence** | Annual, or upon significant change |

## 1. Purpose
This policy establishes BioMate AI LLC's commitment to protecting the confidentiality, integrity, and availability of the information and systems that make up the BioMate AI Assistant Services System, and sets the framework under which all other security policies operate.

## 2. Scope
Applies to all BioMate personnel (employees and contractors), all systems and data within the production environment (AWS account 399683337364), and all third parties that access BioMate systems or data. It covers the application, backend, workflow-execution infrastructure, data stores, and supporting services described in the System Description.

## 3. Policy statements
1. **Security governance.** Management designates a security owner (`[CONFIRM]`) accountable for the information security program, its policies, and its review.
2. **Risk-based controls.** Security controls are selected and operated based on a documented risk assessment (see Risk Management Policy) and are mapped to the 2017 Trust Services Criteria (Security).
3. **Least privilege.** Access to systems and data is granted on a need-to-know, least-privilege basis and reviewed periodically (see Access Control Policy).
4. **Encryption.** Data is encrypted in transit (TLS 1.2+) and at rest (AES-256) per the Encryption & Key Management Policy.
5. **Change control.** Production changes follow the Change Management Policy (peer-reviewed pull requests, required CI, health-gated deployment).
6. **Monitoring & logging.** Security-relevant events are logged and monitored (CloudTrail, CloudWatch, application audit logs) and retained per the Data Retention Policy.
7. **Incident response.** Security incidents are handled per the Incident Response Policy.
8. **Third-party risk.** Vendors and subservice organizations are assessed and monitored per the Vendor Management Policy.
9. **Personnel security.** Onboarding, offboarding, background checks (where applicable), and training follow the HR/Personnel Security and Security Awareness policies.
10. **Acceptable use.** All personnel comply with the Acceptable Use Policy and the AI Acceptable Use Policy.
11. **Data protection.** Data is classified, retained, and disposed of per the Data Classification, Retention & Disposal Policy; regulated data (PHI) is handled per the HIPAA safeguards where applicable.

## 4. Roles & responsibilities
- **Security owner** — owns the program, policies, risk assessment, and vendor reviews.
- **Engineering** — implements and operates technical controls; performs change management.
- **All personnel** — comply with policies, complete training, report incidents.

## 5. Enforcement
Violations may result in disciplinary action up to and including termination, and where applicable, legal action. Contractors in violation may have engagements terminated.

## 6. Review
Reviewed at least annually and after any significant change to the system, organization, or risk environment. Version history maintained in Vanta.
