# Risk Management Policy

| | |
|---|---|
| **Version** | 0.1 DRAFT |
| **Owner** | `[CONFIRM: Security owner]` |
| **Effective date** | `[CONFIRM]` |
| **Review cadence** | Annual (assessment refreshed at least annually) |

## 1. Purpose
Establish how BioMate identifies, assesses, treats, and monitors risks to the security of its system and data. Supports CC3.x and CC9.x. This policy governs the process; the risk assessment itself is a separate, maintained artifact.

## 2. Scope
Risks to the confidentiality, integrity, and availability of the BioMate AI Assistant Services System, its data, and its supporting third parties — including AI-specific risks.

## 3. Policy statements
1. **Risk assessment.** A documented risk assessment is performed at least annually and upon significant change. It identifies assets, threats, vulnerabilities, likelihood, impact, and a risk rating.
2. **Scope of risks considered.** Includes technical (infrastructure, application, data), operational (change, access, availability), third-party/subservice-organization, and **AI/LLM-specific risks** (data leakage to model providers, prompt injection, model unavailability, output reliability for regulated decisions).
3. **Risk treatment.** Each material risk is assigned a treatment (accept, mitigate, transfer, avoid), an owner, and a target date; accepted risks are documented with rationale (e.g., lab-network `insecure=True` gRPC accepted because isolated with no internet exposure).
4. **Linkage to controls.** Controls are selected to address identified risks and mapped to the Trust Services Criteria; the risk→control linkage feeds the System Description (DC2→risk→DC5 chain).
5. **Fraud risk.** Fraud and misuse risks are considered as part of the assessment.
6. **Monitoring.** Risk status and treatment progress are reviewed by management on a `[CONFIRM: quarterly]` basis.

## 4. Roles & responsibilities
- **Security owner** — runs the assessment, maintains the risk register, reports to management.
- **Control owners** — execute treatments for risks assigned to them.

## 5. Enforcement & 6. Review
Per the Information Security Policy. Assessment and policy reviewed at least annually.
