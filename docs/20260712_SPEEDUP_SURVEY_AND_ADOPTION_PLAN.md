# Speedup Survey & Adoption Plan — Leverage Community Methods + Auto-Update

**Date:** 2026-07-12
**Frame:** BioMate's two strengths are (1) **Fast / acceleration** and (2) **QC-granted correctness**. This plan adopts recent community speedups **without breaking QC** — in fact QC is what *lets* us adopt aggressive fast methods safely (run fast, gate/verify on the exact method). Plus a second speedup dimension: getting the latest tools/data in fast via the **auto-update** module on a twice-weekly cadence.

---

## The synthesis insight: Fast × QC are complementary, not in tension

Every speedup below has an accuracy trade-off (MLIPs fail on charge/solvation; embedding search has no calibrated E-values; fast DIAMOND modes lose twilight-zone recall; implicit solvent loses water structure). BioMate can adopt them **because** its QC loop gates the failure: **fast method → QC verify on top hits / within validated domain → PROCEED / REFINE / PIVOT.** Reframed for marketing: *"aggressively fast, because QC-verified."*

Two reusable integration primitives cover almost everything:
- **Primitive A — prebuilt index, mounted read-only on Batch.** Build once, store on S3, reuse forever (Foldseek AFDB, MMseqs2 profile DBs, FPSim2 ChEMBL fingerprints).
- **Primitive B — persistent index microservice + Redis cache.** Keep the target DB hot in memory/GPU across queries (MMseqs2-GPU, Qdrant/FAISS vectors, MedCPT), fronted by a Redis (source, query) cache.

---

## Cross-domain "adopt first" — ranked by speedup ÷ effort (commercial-safe)

| # | Adopt | Domain | Speedup | License | Integration | QC gate |
|---|---|---|---|---|---|---|
| 1 | **Foldseek + prebuilt AFDB index** | Structure match | **~10³–10⁵×** vs TM-align/BLAST | GPLv3 (service OK) | Primitive A: `foldseek easy-search` workflow; AFDB/PDB indices are prebuilt on R2 | TM-align exact re-rank on top-N hits |
| 2 | **Redis query-cache + MCP descriptor caching** across 14 connectors | Multi-source search | Biggest multi-DB latency cut, near-zero risk | — (own infra) | Wrap each connector fetch in cache get/set + per-source TTL; cache schemas once | cache TTL by source volatility |
| 3 | **MMseqs2-GPU** persistent search service | Sequence match | ~6× BLAST, PSI-BLAST-beating sensitivity | **MIT** | Primitive B: target DB hot in GPU mem; CPU MMseqs2/DIAMOND fallback | confirm hits; E-value threshold |
| 4 | **FPSim2** chemical-similarity workflow | Ligand match | ChEMBL/PubChem scale, ms/query | **MIT** | Primitive A: prebuilt ChEMBL FPS file → `chem_similarity` tool | Tanimoto ≥0.7 pruning; exact re-score |
| 5 | **NNPOps + ANI-2x ML/MM in OpenMM** | MD | ~6× naïve ML; only **2.7× slower than classical** | Open (BSD) | `nnpops` conda pkg; ligand=ANI, env=MM via openmm-ml | gate to validated chemistry (neutral/±1) |
| 6 | **GB-Neck2 implicit-solvent "fast mode" toggle** | MD | several-× wall-clock | Open (native OpenMM) | flip to `GBn2` for conformer/ADMET pre-screen | off for binding-site/water-mediated work |
| 7 | **MedCPT + Qdrant/LanceDB** semantic retrieval | Literature/metadata | fast dense retrieval, SOTA biomedical | free weights / Apache | Primitive B: embed once, HNSW serve | hybrid dense+BM25; rerank |
| 8 | **BioEmu** protein-ensemble generation | Sampling | 1000 conformations in ~40 min/GPU | **MIT** | `pip install bioemu[md]`; feed ensembles to existing OpenMM stage | ensembles approximate — refine in MD |

**Phase-1 (do now):** #1, #2, #3, #4 — biggest wins, permissive/service-OK licenses, both integration primitives exercised.
**Phase-2:** #5, #6 (MD fast-modes), #7 (retrieval), #8 (ensembles).

---

## Licensing landmines — DO NOT adopt (commercial platform)

- **MACE-OFF** — best-in-class biomolecular MLIP, but **weights are non-commercial ASL.** Disqualified until a commercial license or a permissive equivalent (UMA / AIMNet2 / ORB) is validated in-house. UMA/ORB are the commercial-friendly MLIP candidates for an internal validation spike (both still >100 meV error on charged/long-range; UMA ignores solvent).
- **chemfp (commercial build)** — fastest CPU fingerprint search but its license **forbids service-bureau/hosting.** Use **FPSim2** instead.
- **SmallWorld/SPACE, Enamine REAL (40B+)** — the only fast tools at billion-scale, but **commercial/hosted** — integrate as an **API call**, do not try to wrap/index.
- **DIAMOND** — GPLv3/AGPL: fine to run as a workflow; keep the trusted CPU `--ultra-sensitive` baseline; watch static-linking into any proprietary binary.

---

## Per-domain notes (brief)

- **MD:** foundation MLIPs are NOT drop-in FFs — they fail on charge, spin, long-range electrostatics, solvation, and low force-error does not predict stable MD. Adopt only NNP/MM hybrids within validated chemical space (ANI-2x neutral, AIMNet2 charged), gated by QC. BioEmu complements (not replaces) MD for ensembles; mlcolvar+PLUMED is the Boltzmann-rigorous enhanced-sampling path when good CVs exist.
- **Sequence/structure:** Foldseek is the single biggest lever (structure conservation outruns sequence into the midnight zone); MMseqs2-GPU for sequence; keep DIAMOND ultra-sensitive as trusted baseline; ProtT5/ESM+FAISS as a *recall booster for distant homologs* (research-grade — no E-values, complement not replacement), Phase 3.
- **Data/chem search:** HNSW (<~50–100M vectors, in-RAM) / DiskANN (larger-than-RAM) / GPU CAGRA (frequent rebuilds); Qdrant as standalone service, LanceDB as an embeddable index artifact for batch. Redis cache is the highest-ROI/lowest-risk item overall.

---

## Second speedup dimension — Auto-Update (latest tools/data, fast)

**Status (audited + verified on disk 2026-07-12): production-grade code, NOT yet configured or scheduled.**
- 6-stage pipeline (DETECT→FETCH→GENERATE→VALIDATE→TEST→INTEGRATE + blog gen) updating `backend/database/galaxy_ai_tools.db`; discovers GitHub tools, generates wrappers, quality-scores, integrates with duplication detection + version checks.
- Entry point: `auto_update/scripts/daily_update.sh` (backs up DB first; 7-day retention). Manual: `python3 run_pipeline.py --mode full --days 1 --min-stars 10 --no-test`.
- **Idempotent + safe to repeat** (pre-run gzipped backup, 3-tier dedup, version skip, `--test-db` flag).
- **Gaps blocking go-live:** `.env` and `config/credentials.yaml` MISSING; `GITHUB_TOKEN` + `ANTHROPIC_API_KEY` unset; no cron installed; no prior run logs. Notifications stubbed (email/Slack TODO).

### Go decision: **GO, after ~10-min credential setup + a test-DB dry run.**

1. Create `auto_update/.env` with `GITHUB_TOKEN` + `ANTHROPIC_API_KEY` (secrets — user provides).
2. `cp config/credentials.yaml.example config/credentials.yaml`, fill GitHub token.
3. **Dry run on the test DB first** (mandatory): `python3 run_pipeline.py --mode full --days 1 --min-stars 100 --limit 5 --test-db --no-test` → check `logs/daily/`.
4. Schedule twice-weekly (Tue/Fri 02:00, ≥72 h spacing):
   `0 2 * * 2,5 /Users/kky/biomate/auto_update/scripts/daily_update.sh >> .../logs/cron.log 2>&1`

### DECIDED (2026-07-12): Scheduled CI, blog gen OFF
Created **`.github/workflows/auto-update-tools.yml`** — runs Tue+Fri 02:00 UTC (`0 2 * * 2,5`) + manual `workflow_dispatch`. Blog OFF (leaves `ANTHROPIC_API_KEY` unset → `run_pipeline.py` runs `enhance=False`, verified at line 710). Uses the built-in `GITHUB_TOKEN` for discovery (no new secret). Produces the updated DB + count-delta + logs as a **14-day artifact** for review. **Deploy stays manual** via `scripts/sync_to_dev.sh` (deploy_databases layer) — a QC/review gate on auto-discovered third-party tools, honoring the no-ad-hoc-sync rule.
- Validated: YAML parses (7 steps, correct cron/triggers); pipeline entry-point deps confirmed (`auto_update/requirements.txt` includes PyGithub); fixed a silent-failure `|| true` on the required dep install.
- **One secret to make it fully accurate:** `WORKFLOW_DB_SOURCE_URL` = an S3 URI or presigned URL to a current copy of `galaxy_ai_tools.db`. Without it the runner integrates into an EMPTY base (dedup/version-skip and counts inaccurate) — it still discovers, but the delta is meaningless. The DB is gitignored + bind-mounted, so a fetchable copy is required.
- **Activation:** schedules fire only from the DEFAULT branch — merge the workflow file there to start the cadence.

### (Superseded) Deployment-location options considered
The pipeline writes a 318 MB `galaxy_ai_tools.db` that must reach dev/prod via the **sanctioned `scripts/sync_to_dev.sh`**, never a direct dev cron/SSM edit. Options:
- **(a) Local/attended cron** — simplest; laptop must be on; DB syncs via the normal deploy path afterward.
- **(b) Scheduled CI (GitHub Action)** — durable; runs the pipeline, commits the updated DB, triggers the deploy pipeline. Recommended for reliability.
- **(c) Dedicated build host** — a small always-on instance running the cron.
Pick one before scheduling; (b) is the most robust and avoids the laptop dependency.

---

## Recommended sequencing
1. **Auto-update live** (this week): credentials → test-DB dry run → twice-weekly schedule via chosen hook. Fastest ROI, already built.
2. **Phase-1 speedups**: Foldseek AFDB (Primitive A) + Redis/MCP cache (own infra) first; then MMseqs2-GPU service + FPSim2.
3. **Phase-2**: MD fast-modes (NNPOps/ANI-2x, GB-Neck2), MedCPT retrieval, BioEmu.
4. Every adoption ships with its **QC gate** (exact re-rank / domain guard) — that's the differentiator, not an afterthought.
