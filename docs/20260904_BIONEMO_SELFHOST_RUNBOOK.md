# Runbook — self-hosting BioNeMo NIMs for BioMate

**Date:** 2026-09-04
**Scope:** Turn BioMate's DL inference/generation stubs into real calls by
running NVIDIA BioNeMo NIM containers **inside your own AWS tenant**. Data never
leaves the tenant — the data-governance posture locked in
`docs/20260903_ARCH_DECISIONS_BIONEMO_AND_GALAXY_EXIT.md` §1.
**Audience:** the operator provisioning GPU + NGC access.
**Code this wires up:** `backend/lib/galaxy/ai/bionemo_client.py` (mode switch),
consumed by `models_inference.py` and `denovo_pipeline.py` / `generators.py`.

> **Honesty contract.** Until the NIMs below are running and BioMate is pointed
> at them, every DL call returns an *honest stub shape* (empty result + a
> `reason`), never a fabricated structure/sequence/molecule. This runbook is how
> you flip stub → real. Nothing here has been run against a live GPU/NGC in this
> environment — the image tags are **placeholders you must confirm on NGC**.

---

## 0. How the three modes work (why this is safe to ship un-provisioned)

`BioNeMoClient` runs in one of three modes (env `BIONEMO_MODE`):

| Mode | When | Behaviour |
|---|---|---|
| `self_host` | `BIONEMO_SELF_HOST_URL` set | POST to your NIM gateway per-model path. **Production.** |
| `hosted_api` | `NVIDIA_API_KEY` set (no URL) | POST to NVIDIA's hosted NVCF API. Dev/parity only — sends data off-tenant. |
| `stub` | neither set, **or** the chosen backend is unreachable | Return the empty-but-typed shape + a `reason`. No network. |

Auto-detect (no `BIONEMO_MODE`): self-host if URL set → else hosted if key set →
else stub. **Unreachable self-host degrades to stub**, so a scaled-down or
mid-deploy NIM never fabricates output — it returns empty and `health()` says why.

Verify current mode from the backend at any time via the health helper
(§6) — no inference call burned.

---

## 1. NGC access + `docker login nvcr.io`

1. Create/join an NGC org with BioNeMo NIM entitlement:
   <https://catalog.ngc.nvidia.com> (NIMs require the NVIDIA AI Enterprise /
   BioNeMo entitlement — confirm your org has it; some NIMs are gated).
2. Generate an API key: <https://ngc.nvidia.com/setup/api-key>.
3. Log the GPU host's Docker into NGC (username is the literal `$oauthtoken`):

   ```bash
   echo "$NGC_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin
   ```

4. Install the **NVIDIA Container Toolkit** on the host so Docker can pass GPUs
   (`--gpus`/device reservations). On the AWS **Deep Learning AMI (GPU)** it's
   preinstalled; otherwise install `nvidia-container-toolkit` and restart Docker.
   Verify: `docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi`.

---

## 2. Which models, and GPU/VRAM sizing

BioMate's client maps these methods → NIMs (compose service in parentheses):

| Client method | Model | NIM status (confirm on NGC) | Rough VRAM / GPU |
|---|---|---|---|
| `boltz2()` | Boltz-2 (structure, AF3-class) | catalog-listed 2026 web check — **verify** | ~24–40 GB → 1×A100/H100 40–80GB |
| `genmol()` | GenMol (NVIDIA, mol-gen) | NVIDIA model, catalog-listed — **verify** | small, ~8–16 GB → 1×A10G/L4/A100 |
| `molmim()` | MolMIM (NVIDIA, mol-gen) | NVIDIA model, catalog-listed — **verify** | small, ~8–16 GB → 1×A10G/L4 |
| `evo2_generate()` | Evo2-7B (Arc, genomics) | catalog-listed — **verify** | 7B: ~24–40 GB → 1×A100 40GB |
| `evo2_generate(model="evo2_40b")` | Evo2-40B | catalog-listed — **verify**; large | 40B: multi-GPU / ≥80GB → own host |
| `diffdock()` | DiffDock (MIT, docking) | catalog-listed — **verify** | ~16–24 GB → 1×A100/L40S |
| `esmfold()`, `rfdiffusion()`, `proteinmpnn()`, `alphafold2()`, `openfold2/3`, `msa_search()`, `esm2_embed()`, `moflow()` | (client already supports; **commented out** in compose) | most are published NIMs — **verify per model** | see NGC model card |

**Honesty on status:** the "catalog-listed" column is from the 2026 web check
recorded in the arch-decision doc, **not** a live verification in this
environment. Before you pull, open each model's page on
<https://catalog.ngc.nvidia.com>, confirm (a) it's a published NIM, (b) the exact
`nvcr.io/...` repository path, (c) the tag, and (d) the model card's stated GPU
requirement. The VRAM figures above are order-of-magnitude planning numbers —
**use each model card's stated requirement**, not this table, for instance
selection.

**AWS instance guidance (planning, not prescriptive):**
- Mol-gen (GenMol/MolMIM): `g5.2xlarge` (1×A10G 24GB) is usually enough.
- Structure/docking/Evo2-7B: `p4d.24xlarge` (A100 40GB) or `p5` (H100 80GB);
  pin one GPU per NIM.
- Evo2-40B / AlphaFold2: dedicate a large GPU host; keep scaled-to-zero when idle.
- A single 8-GPU host will **not** hold every model above simultaneously —
  provision per-model hosts or an autoscaling GPU pool (see `k8s-notes.md`).

---

## 3. Configure + pull

```bash
cd deploy/bionemo
cp .env.bionemo.example .env.bionemo
# edit .env.bionemo:
#   NGC_API_KEY=nvapi-...            (your real key)
#   BOLTZ2_TAG / GENMOL_TAG / ...    (the EXACT tags you confirmed on NGC)
```

⚠️ **Do not run with the placeholder tags.** `PLACEHOLDER_CONFIRM_ON_NGC` will
fail to pull by design — it forces you to set a real, confirmed tag. If a
model's NGC repository path differs from the `nvcr.io/nim/<vendor>/<model>`
pattern in `docker-compose.bionemo.yml`, edit the `image:` line to match the
catalog.

Pre-pull (optional, so `up` doesn't block on multi-GB downloads):

```bash
docker compose -f docker-compose.bionemo.yml pull
```

---

## 4. Start the stack

```bash
docker compose -f docker-compose.bionemo.yml up -d
docker compose -f docker-compose.bionemo.yml ps
# First start is SLOW: each NIM downloads + loads weights (many minutes).
# Watch readiness:
docker compose -f docker-compose.bionemo.yml logs -f boltz2
curl -sf http://localhost:8101/v1/health/ready && echo "boltz2 ready"
```

Each service publishes its in-container `:8000` on a distinct host port
(8101–8105). Confirm each NIM's actual OpenAPI routes at `/docs`
(`http://localhost:8101/docs`) — the routes BioMate calls are in
`bionemo_client._SELF_HOST_PATHS`; if a NIM's route differs, either front it with
a gateway that normalizes paths, or set `BIONEMO_SELF_HOST_PATH_<MODEL>` on the
backend to the real route.

### Gateway (recommended)
`BIONEMO_SELF_HOST_URL` is a **single base URL**; the client appends per-model
paths. Put a reverse proxy (Caddy/nginx/ALB) in front that fans those paths to
the right service port. One-model-per-host is the alternative — point the URL at
the host and override paths with `BIONEMO_SELF_HOST_PATH_<MODEL>`.

---

## 5. Point BioMate at the self-host

Set these on the **Galaxy backend container** (not the NIM host):

```bash
BIONEMO_MODE=self_host
BIONEMO_SELF_HOST_URL=http://<gateway-or-nim-host>:8000
# optional, only if a NIM's route differs from _SELF_HOST_PATHS:
# BIONEMO_SELF_HOST_PATH_BOLTZ2=/boltz2/predict
```

On dev/prod these live wherever the backend's env is materialized
(AWS Secrets Manager → `/opt/biomate/.env`, per `deploy/docker-compose.deploy.yml`).
**Do NOT** set `NVIDIA_API_KEY` in self-host mode — leaving it unset keeps data
on-tenant (self-host wins in auto-detect anyway, but be explicit).

Restart the backend so the new env is read.

---

## 6. Verify via the health endpoint

The client exposes `BioNeMoClient().health()` — surface it through whatever API
route your ops uses (it reports mode, effective mode, gateway reachability, and
per-model probe status). Expected shape:

```json
{
  "mode": "self_host",
  "effective_mode": "self_host",
  "self_host_url": "http://gateway:8000",
  "api_key_present": false,
  "reachable": true,
  "models": {
    "boltz2":   {"reachable": true,  "detail": "HTTP 405 at /biology/mit/boltz2/predict"},
    "genmol":   {"reachable": true,  "detail": "HTTP 422 at /biology/nvidia/genmol/generate"},
    "molmim":   {"reachable": true,  "detail": "HTTP 405 at /biology/nvidia/molmim/generate"},
    "evo2_7b":  {"reachable": true,  "detail": "..."},
    "diffdock": {"reachable": true,  "detail": "..."}
  }
}
```

`"reachable": false` or a missing model → that NIM is down / the route is wrong;
BioMate will return honest stub shapes for it until fixed. A quick end-to-end
smoke (from a backend shell):

```python
from galaxy.ai.bionemo_client import BioNeMoClient
c = BioNeMoClient()
print(c.health())
print(c.genmol("", num_molecules=3))   # [] if unreachable, real mols if up
```

---

## 7. Data governance

- **Self-host = data stays in tenant.** Sequences/structures POST only to your
  NIM host inside your VPC; nothing goes to NVIDIA's hosted API. Keep the NIM
  subnet private (no public egress needed after image pull); allow the backend's
  security group to reach the gateway port only.
- **`hosted_api` mode sends data off-tenant** — use it only for dev against
  non-sensitive inputs, never for pharma IP. The auto-detect prefers self-host
  whenever `BIONEMO_SELF_HOST_URL` is set.
- **NGC key is a secret** — it lives in `.env.bionemo` (git-ignored) on the NIM
  host and in Secrets Manager for the backend if you use `hosted_api`. Never
  commit it.

---

## 8. Caveats / what still needs a human

- **Model NIM availability + tags are UNVERIFIED here** — confirm each on the NGC
  catalog at provision time (the compose tags are deliberate placeholders).
- **Exact NIM routes vary** — confirm against each `/docs`; use the gateway or
  `BIONEMO_SELF_HOST_PATH_<MODEL>` overrides to reconcile with
  `_SELF_HOST_PATHS`.
- **DrugCLIP is NOT a NIM** — it is a bespoke, MIT-licensed ultra-fast screening
  model and stays a separate BioMate service. Do not try to add it to this stack.
- **Evo2-40B / AlphaFold2 are heavy** — provision them deliberately (own host,
  scale-to-zero when idle) rather than co-locating.
- **Licensing** — some NIMs require NVIDIA AI Enterprise entitlement; verify your
  org's coverage per model before relying on it in production.
