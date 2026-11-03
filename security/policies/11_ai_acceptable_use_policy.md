# AI Acceptable Use Policy

| | |
|---|---|
| **Version** | 0.1 DRAFT |
| **Owner** | `[CONFIRM: Security owner]` |
| **Effective date** | `[CONFIRM]` |
| **Review cadence** | Annual (acknowledged on hire + annually) |

## 1. Purpose
Govern the use of artificial intelligence and large language models (LLMs) — both as a core component of BioMate's service and in internal operations — so that AI use does not compromise the security or confidentiality of BioMate or customer data. The Sentry scoping questionnaire specifically probes AI risk controls; this policy is the direct response.

## 2. Scope
All AI/LLM use touching BioMate or customer data: the platform's LLM integrations and any AI tools used internally by personnel.

## 3. AI in the service (product)
1. **Providers.** The BioMate AI Assistant routes requests through an LLM fallback chain: Google Gemini (primary), Anthropic Claude (via AWS Bedrock under the AWS BAA), OpenAI GPT-4o, and a local Ollama offline fallback. These providers are in the vendor register and reviewed per the Vendor Management Policy for data-use and retention terms.
2. **Data minimization to models.** A PHI-detection guardrail strips 18-identifier patterns (SSN, DOB, MRN, Patient ID, NPI, insurance) from text before it is sent to any external LLM and logs a hash, not the value. Only the minimum necessary content is sent to models.
3. **PHI routing.** Where PHI may be involved, processing routes through AWS Bedrock under the AWS BAA; providers without appropriate data protections are not sent regulated data.
4. **Output reliability.** AI outputs used for regulated or clinical decisions are subject to user independent review (see CUEC); the platform does not represent AI outputs as validated medical advice.
5. **Auditability.** AI-relevant events are recorded in `audit_logs`.

## 4. AI in internal operations
1. **Approved tools.** Personnel use only approved AI tools with company or customer data; new tools require review.
2. **No secrets or Restricted data** are pasted into consumer AI tools that may train on inputs or that lack an appropriate data-processing agreement.
3. **Customer data** is not submitted to external AI tools outside the platform's controlled integrations without authorization and de-identification.

## 5. AI risk governance
1. **Risk assessment.** AI-specific risks (data leakage to providers, prompt injection, model unavailability/fallback, output reliability) are included in the Risk Management Policy and the risk register.
2. **BC/DR.** The LLM fallback chain (including offline Ollama) addresses provider-unavailability risk; this is reflected in BC/DR.
3. **Vendor management.** AI/LLM providers are assessed for training-on-data, retention, and regional processing.

## 6. Roles, enforcement & review
- **Security owner** — maintains this policy, the AI risk entries, and acknowledgment records.
- **All personnel** — comply and acknowledge on hire + annually.
Enforcement per the Information Security Policy; reviewed annually and upon significant change to the AI stack.
