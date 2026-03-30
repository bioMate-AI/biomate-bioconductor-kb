# License & Credential Gate — Phase 1 (AF3) + Phase 2 (CryoSPARC) + Chai-1/Boltz-2

**Date**: 2026-03-19
**Branch**: connection_formal
**Status**: COMPLETE — 3/3 E2E tests passing

## What was built

### Backend
- `license_registry.py`: Static registry with AF3 (docker_auth), Chai-1 (none — open source), Boltz-2 (api_key), CryoSPARC (license_key)
- `credentials_api.py`: Galaxy Vault + preferences fallback credential storage; `get_effective_credential(trans, tool_id)` returns (cred, source) = user|biomate|none
- Endpoints: GET /api/workflows/license-requirements, GET/POST/DELETE /api/users/credentials, GET /api/users/credentials/{tool_id}/value
- `nextflow_executor.py`: `Request` import added; credentials dict injected into Nextflow config (docker auth + env vars)
- `cryosparc_executor.py`: `license_key` param override

### Frontend
- `credential-modal.tsx`: docker_auth (username+token) and license_key forms
- `license-gate.tsx`: Fetches /api/workflows/license-requirements; green rows for resolved, amber with "Provide credentials" for unresolved
- `nextflow-workflow-viewer.tsx`: LicenseGate wired; `licenseBlocked` state gates Confirm & Run button
- `routes.ts`: Credential proxy routes (GET/POST/DELETE /api/users/credentials, GET /api/workflows/license-requirements)

### Nextflow Workflow: structure_prediction_docking
- `params.prediction_tool`: 'alphafold3' | 'chai1' | 'boltz2' (default: alphafold3)
- Added CHAI1_STRUCTURE_PREDICTION and BOLTZ2_STRUCTURE_PREDICTION processes
- Boltz-2: supports 'nim_api' mode (NVIDIA NIM) and 'local' mode (open weights)
- Chai-1: Apache 2.0, no auth required, chai-lab Python package
- All three tool processes have mock mode + live mode implementations
- All 5 processes verified with `nextflow inspect` and mock run tests

## Key verification results

### License Requirements API (LG-2):
- AF3: source=none (no master creds), alternatives=[chai1, boltz2]
- Chai-1: source=biomate (Apache 2.0, always available)  
- Boltz-2: source=none (no NVIDIA_NIM_API_KEY)
- CryoSPARC: source=biomate (CRYOSPARC_LICENSE in env)

### Credential store roundtrip:
- POST /api/users/credentials {tool:alphafold3, data:{username,token}} → 200 {ok:true}
- GET /api/users/credentials?tool=alphafold3 → {has_credential:true, source:'user'}
- DELETE /api/users/credentials/alphafold3 → source back to 'none'

## E2E Tests
- **File**: `frontend/e2e/license-gate-audit.e2e.ts`
- **Results**: 3/3 passing
- **Screenshots**: `frontend/e2e/screenshots/license-gate/`

## Fix applied
- `nextflow_executor.py` line 18: added `Request` to fastapi imports (boot error when loading new module)
- `credentials_api.py`: added `if not trans.user: return None` guard in `_get_credential` and `_delete_credential`

## Boltz-2 pricing note
- NVIDIA NIM: free tier ~1000 credits; ~$0.05-$0.10/inference after
- Local weights: free (MIT license), needs A100/H100 GPU

## AlphaFold3 account
- BioMate does NOT have credentials yet
- Apply at: https://alphafold.ebi.ac.uk/ (non-commercial research use)
- When approved: set ALPHAFOLD3_DOCKER_USER + ALPHAFOLD3_DOCKER_TOKEN in backend/.env
