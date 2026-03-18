# PM Plan: Software License & Registration Collection
**Date**: 2026-03-18
**Status**: ACTIVE — scoped to 3 phases
**Trigger**: AlphaFold3 (`catgumag/alphafold3`) pull fails on Batch because BioMate does not hold user credentials/license for third-party tools that require registration.

## Decisions Made (2026-03-18)
- **Demo users**: Use BioMate's own master credentials (stored in backend env / AWS Secrets Manager). Demo users never see a license gate.
- **Registered users**: Can optionally provide their own credentials; fall back to BioMate's master where available.
- **Phase 1**: AlphaFold3 (docker_auth)
- **Phase 2**: CryoSPARC (registration/license key)
- **Phase 3**: Drug discovery paid tools — catalog + credential collection (Schrödinger, AMBER, MOE)

---

## Problem Statement

Many bioinformatics tools used in BioMate workflows require end-user registration, license acceptance, or institutional credentials before the container or binary can be accessed:

| Tool | Restriction Type | Required Action |
|------|-----------------|-----------------|
| AlphaFold3 (catgumag/alphafold3) | Non-commercial license + Google form | Register at alphafold.ebi.ac.uk, accept T&C |
| GROMACS (some editions) | Academic license | Institution email required |
| Schrödinger Glide | Commercial license | License server host:port |
| AutoDock-GPU | Academic use agreement | Click-through accept |
| GATK (Broad Institute) | Genomic data sharing agreement | Broad agreement signed |
| AMBER | Commercial license | License key file |
| MOE (CCG) | Commercial license | License key + host |

When a user requests a workflow that depends on one of these tools, BioMate currently:
1. Silently submits the job
2. The Batch task fails with `pull access denied` or similar
3. User sees a generic workflow failure with no actionable guidance

---

## Goals

1. **Detect** licensed tool dependencies at workflow-selection time, before execution
2. **Collect** the required credentials/registration from the user via a structured UI flow
3. **Store** credentials securely (encrypted at rest, per-user, scoped to tool)
4. **Inject** credentials into the workflow execution (Docker auth, license server URLs, env vars)
5. **Guide** users to registration pages when they don't have credentials yet

---

## User Stories

### US-1: License Gate at Workflow Selection
> As a researcher, when I request a workflow that requires a licensed tool, I want to be told upfront what I need to provide — before I click "Confirm & Run" — so I don't waste time on a doomed execution.

**Acceptance Criteria:**
- During the AWAITING REVIEW phase, if any workflow step requires a licensed tool: show a "License Required" panel listing the tool name, restriction type, and a link to the registration page
- The "Confirm & Run" button is disabled until the license is resolved (credential stored or user confirms free-tier access)
- Panel distinguishes: (a) user already has credential stored, (b) needs to provide, (c) free-tier available

### US-2: Credential Collection Modal
> As a researcher, I want to provide my AlphaFold3 access token once and have BioMate use it automatically in all future AlphaFold3 runs.

**Acceptance Criteria:**
- Clicking "Provide Credentials" opens a tool-specific modal with: field labels, validation hints, link to where to obtain the credential
- Supported credential types: API key / token, Docker registry auth (username + password), license server (host:port), license key file upload, click-through acceptance
- Credentials stored encrypted in user's profile, not logged or exposed
- "Test Credential" button validates before saving (e.g., dry-run docker pull)

### US-3: Automatic Credential Injection
> As a researcher, once I've provided my AlphaFold3 registration, I want it to be automatically used in all future runs without needing to re-enter it.

**Acceptance Criteria:**
- Stored credentials are automatically retrieved and injected at execution time
- Docker registry: injected via `~/.docker/config.json` scoped to the Batch task
- License server: injected as env var (e.g., `LM_LICENSE_FILE=...`) in Nextflow process
- API key: injected as workflow parameter (masked in logs)

### US-4: Registration Guidance
> As a new user who doesn't have an AlphaFold3 license, I want BioMate to guide me to the right registration page and tell me what to expect.

**Acceptance Criteria:**
- License gate panel shows: tool name, vendor/institution, registration URL, typical approval time, cost (free/academic/commercial)
- For tools with automated approval (click-through): one-click accept flow within BioMate
- For tools requiring external approval: "I've registered, enter credentials" button appears after user confirms they've completed registration

### US-5: Alternative Tool Suggestion
> As a researcher, if I cannot get an AlphaFold3 license, I want BioMate to suggest an open alternative (ESMFold, ColabFold) automatically.

**Acceptance Criteria:**
- License gate panel shows "Open Alternatives" section when available
- Clicking an alternative re-runs workflow selection with the open-source tool substituted
- User sees a brief comparison (accuracy, speed, citation) to help decide

---

## Technical Architecture

### Backend: License Registry
**File**: `backend/lib/galaxy/webapps/galaxy/api/license_registry.py`

```python
LICENSE_REGISTRY = {
    "alphafold3": {
        "display_name": "AlphaFold3",
        "vendor": "Google DeepMind / EBI",
        "type": "registration",        # registration | license_key | docker_auth | click_through
        "registration_url": "https://alphafold.ebi.ac.uk/",
        "approval_time": "~1 day",
        "cost": "free (non-commercial)",
        "container_registry": "registry.hub.docker.com",
        "registry_namespace": "catgumag",
        "open_alternatives": ["esm2", "colabfold"],
        "inject_as": "docker_auth",
    },
    "gromacs_gpu": {
        "display_name": "GROMACS",
        "vendor": "GROMACS consortium",
        "type": "click_through",
        "registration_url": "https://www.gromacs.org/",
        "approval_time": "instant",
        "cost": "free (LGPL)",
        "inject_as": "none",   # publicly available, just needs accept
    },
    "schrodinger_glide": {
        "type": "license_server",
        "inject_as": "env_var",
        "env_var": "SCHRODINGER_LICENSE_FILE",
    },
    # ...
}
```

**Endpoint**: `GET /api/workflows/license-requirements?nextflow_path=...`

Scans the `.nf` file for container references, cross-references `LICENSE_REGISTRY`, returns list of required licenses with user's stored-credential status.

### Backend: Credential Store
**File**: `backend/lib/galaxy/webapps/galaxy/api/credential_store.py`

- Encrypted storage in Galaxy user data (`encrypted_credentials` column or separate table)
- AES-256-GCM encryption, key from Galaxy `id_secret`
- Per-tool, per-user scoping
- TTL support (some registry tokens expire)

**Endpoints**:
- `POST /api/users/credentials` — store credential for a tool
- `GET /api/users/credentials?tool=alphafold3` — check if credential exists (returns existence, expiry, NOT the value)
- `DELETE /api/users/credentials/:tool` — revoke
- `POST /api/users/credentials/:tool/test` — validate credential (docker pull dry-run, license ping)

### Frontend: License Gate Component
**File**: `frontend/client/src/components/license-gate.tsx`

Props: `{ licenseRequirements: LicenseRequirement[]; onResolved: () => void; }`

States:
1. `checking` — spinner while fetching requirements
2. `required` — shows list of required licenses with credential entry/status
3. `all_resolved` — green checkmarks, Confirm & Run enabled

**Integration**: Rendered inside `NextflowWorkflowViewer` between the review panel and the "Confirm & Run" button.

### Frontend: Credential Collection Modal
**File**: `frontend/client/src/components/credential-modal.tsx`

Rendered per-tool. Tool-type-specific form fields:
- `docker_auth`: username + password/access-token fields
- `license_server`: host + port
- `license_key`: file upload or paste
- `click_through`: accept button + terms text
- `api_key`: single secret field

---

## Affected Workflows (Initial Scope)

| Workflow | Tool | License Type |
|----------|------|-------------|
| `structure_prediction_docking` | AlphaFold3 | Registration |
| `molecular_dynamics_gromacs` | GROMACS | Click-through |
| `structure_prediction_docking` | DiffDock | MIT (open, no gate) |
| `drug_docking_schrodinger` | Schrödinger Glide | Commercial |
| Any workflow with `amber` process | AMBER | Commercial |

---

## Out of Scope (v1)

- Sharing credentials between team members (defer to org/team feature)
- SSO-based license federation (e.g., institutional SAML for GROMACS)
- Credential rotation automation
- Billing passthrough for commercial licenses

---

## Open Questions for PM

1. Should BioMate store Docker registry credentials, or let users configure their own Docker Hub auth and BioMate only validates it's present? (Security vs. convenience tradeoff)
2. For commercial tools (Schrödinger, AMBER): should BioMate validate the license server is reachable before the run, or fail gracefully?
3. For tools with open alternatives (AlphaFold3 → ESMFold): should BioMate automatically downgrade when user lacks license, or always ask?
4. How do we handle expiring credentials (Docker Hub tokens, short-lived API keys)?
5. Should unauthenticated demo users see license gates, or should demo workflows only use fully open tools?

---

## Definition of Done

- [ ] `LICENSE_REGISTRY` dictionary with at minimum AlphaFold3, GROMACS, AMBER entries
- [ ] `GET /api/workflows/license-requirements` returns correct requirements for `structure_prediction_docking`
- [ ] `LicenseGate` component renders correctly in AWAITING REVIEW view when license required
- [ ] `CredentialModal` successfully stores and retrieves AlphaFold3 Docker credentials
- [ ] Subsequent `structure_prediction_docking` run uses stored credentials → pull succeeds
- [ ] `US-5` alternative suggestion shows ESMFold as alternative to AlphaFold3
- [ ] E2E test: full flow from "license required" → "enter credentials" → "run succeeds"
