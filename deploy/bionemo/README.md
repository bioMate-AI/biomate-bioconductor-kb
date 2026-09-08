# BioMate self-hosted BioNeMo NIM stack

Turnkey scaffolding to run the NVIDIA BioNeMo NIM containers BioMate's DL layer
calls (`backend/lib/galaxy/ai/bionemo_client.py`) **inside your own AWS tenant**,
so sensitive sequences/structures never leave your infrastructure.

- **Full step-by-step runbook:** `docs/20260904_BIONEMO_SELFHOST_RUNBOOK.md`
- **Decision context:** `docs/20260903_ARCH_DECISIONS_BIONEMO_AND_GALAXY_EXIT.md` §1

## Files

| File | Purpose |
|---|---|
| `docker-compose.bionemo.yml` | Single-host reference stack: Boltz-2, GenMol, MolMIM, Evo2, DiffDock NIMs with GPU reservation + weight cache volume |
| `.env.bionemo.example` | Copy to `.env.bionemo`, fill `NGC_API_KEY` + confirmed image tags |
| `.gitignore` | Keeps the real `.env.bionemo` out of git |
| `k8s-notes.md` | How to translate the compose stack to Kubernetes (GPU node pool + Deployments/Services) |

## Quick start (see runbook for the honest, full version)

```bash
cd deploy/bionemo
cp .env.bionemo.example .env.bionemo         # then edit NGC_API_KEY + tags
echo "$NGC_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin
docker compose -f docker-compose.bionemo.yml up -d
# then on the BioMate BACKEND container:
#   BIONEMO_MODE=self_host
#   BIONEMO_SELF_HOST_URL=http://<gateway-host>:8000
```

## What is real vs needs operator provisioning

- **Real / working now:** the client mode switch + graceful stub fallback +
  `health()` (all unit-tested); this compose/k8s scaffolding; the per-model
  path map in the client.
- **Needs the operator (you) at provision time:** a GPU host + NGC account;
  **confirming each NIM's exact image path + tag on the NGC catalog** (the tags
  here are placeholders — see the ⚠️ in the compose file); a reverse-proxy/gateway
  that maps `BIONEMO_SELF_HOST_URL`'s per-model paths to the published ports (or
  a one-model-per-host layout with `BIONEMO_SELF_HOST_PATH_<MODEL>` overrides).

## Not a NIM

**DrugCLIP is intentionally absent.** It is a bespoke, MIT-licensed ultra-fast
screening model, not a BioNeMo NIM, and stays a separate BioMate service. Do not
try to add it here.
