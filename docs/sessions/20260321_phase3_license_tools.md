# Phase 3 License Tools — Implementation

**Date**: 2026-03-21
**Branch**: connection_formal
**Status**: COMPLETE — 3 tools added to registry, credential injection wired

## What was done

### Research (reference docs)
- `reference/20260321_amber_feasibility.md` — highest priority, free academic
- `reference/20260321_schrodinger_feasibility.md` — medium, FEP+ unique
- `reference/20260321_moe_feasibility.md` — low, covalent docking

### License Registry (`license_registry.py`)
Added 3 new tools — total registry now has 7 tools:

| Tool | Type | Source |
|------|------|--------|
| alphafold3 | docker_auth | none (apply at EBI) |
| boltz2 | api_key | none (apply at NVIDIA) |
| chai1 | none | biomate (open) |
| cryosparc | license_key | biomate (CRYOSPARC_LICENSE) |
| **amber** | **license_agreement** | **biomate (always — no key)** |
| **schrodinger** | **license_server** | **none (bring own FlexLM)** |
| **moe** | **license_server** | **none (bring own FlexNet)** |

### Credential API (`credentials_api.py`)
Added two new type handlers in `get_effective_credential()`:
- `license_server` → reads env var (e.g. `SCHRODINGER_LICENSE_FILE`) → returns `{license_server: "27008@host"}`
- `license_agreement` → always returns `({}, "biomate")` — no runtime key needed

### Frontend (`credential-modal.tsx`)
- `license_server`: text field, placeholder `27008@your-flexlm-host.example.com` + port@host hint
- `license_agreement`: checkbox "I confirm academic/non-profit use" → Submit = "Confirm"
- Type union updated to include all 6 type values

### Credential Proxy (`routes.ts`)
Added `proxyToGalaxyCredential()` helper + 4 routes:
- `GET /api/workflows/license-requirements`
- `GET /api/users/credentials`
- `POST /api/users/credentials`
- `DELETE /api/users/credentials/:tool_id`

### Credential Injection (`nextflow_executor.py`)
- `NextflowExecuteRequest.credentials: Optional[Dict[str, Dict[str, str]]]` field added
- `_inject_credentials_to_env()` helper: injects FlexLM/FlexNet env vars, Docker auth, API keys
- Execution path in routes.ts: calls license-requirements + credential/value before execute → passes in body

## Verified (live)
```
GET /api/users/credentials?tool=amber    → source=biomate, has_credential=true ✅
GET /api/users/credentials?tool=schrodinger → source=none, has_credential=false ✅
GET /api/users/credentials?tool=moe     → source=none, has_credential=false ✅
GET /api/workflows/license-requirements?nextflow_path=.../structure_prediction_docking/main.nf
  → alphafold3(none), boltz2(none), chai1(biomate) ✅
```

## Next actions
- AMBER: build ECR image with pmemd.cuda; register ambermd.org
- Schrödinger: request dev trial at schrodinger.com/freeTrial
- MOE: monitor user demand; request CCG trial if 3+ users ask
