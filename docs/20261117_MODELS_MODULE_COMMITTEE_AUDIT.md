# 2026-11-17 — Models module: committee audit (scope, pillars, platform fit)

Four independent adversarial auditors (Product/UX, Scientific/ML, Platform/Architecture, End-to-end QA) reviewed the Models side-panel module and its three pillars — **training, adaptation, loop (DMTA)**. Four load-bearing claims were independently verified by the synthesizer (all held). This is the consolidated record.

## Headline verdict
**Useful and unusually honest at its core, but uneven: one strong pillar (the small-molecule DMTA loop), one under-cooked (the peptide/biologic modality), one vestigial (adaptation) — on a campaign engine that is a parallel stack bolted alongside the platform rather than wired through it.**

No fabrication was found anywhere (all four auditors; the honesty discipline is real). The problems are correctness, platform integration, security, and scope coherence — not dishonesty.

## Pillar scorecard
| Pillar | State | Why |
|---|---|---|
| **Loop (DMTA)** | Strong (small-molecule) / defective (sequence) | Small-molecule BO is sound + honest (Tanimoto-GP, real posterior, honest `can_discriminate`). Peptide/biologic works end-to-end but has real statistical defects (below) and the engine isn't multi-worker-safe or ownership-gated. |
| **Training** | Real but open-loop | sklearn baselines run as real tracked workflow runs with held-out metrics; Chemprop honestly NotImplementedError. **But you can't run what you trained** — trained models land in a separate registry explicitly "not deployed for inference," absent from the run-a-model catalog. |
| **Adaptation** | Vestigial / mislabeled | UI hidden (`HOUSE_STYLE_HIDDEN`); a full API/type/test layer has zero UI consumer (dead code); and the default `prompt_rules` mode is **few-shot exemplar retrieval, not weight learning** — the "training job" label overstates it (the real LoRA path is gated off). |

## Consolidated findings (ranked; ✓ = independently verified this session)

### Security / reliability
1. **[MAJOR · security] IDOR on `/api/drug-discovery/*` ✓.** Proxy is `optionalAuth` with no campaign-ownership check; backend ingest/compounds/retrain endpoints gate only on an audit decorator. A caller who knows a campaign id (== project UUID) can ingest/trigger/read another user's campaign — while the same store is owner-scoped and fail-closed via `/api/model-tracks/*`. (routes.ts:5641; api_router.py:454,501,2053+)
2. **[MAJOR · reliability] Auto-retrain background loop is not multi-worker-safe ✓.** `_active_loops`/`_loop_stop_events` are in-process dicts; under gunicorn `--workers=4`, Start/Stop/status land on random workers → status wrong ~3/4 of the time, Stop often no-ops, up to 4 duplicate daemons per campaign, killed silently on worker recycle. Same class as the documented `_runs[]` bug. (auto_retrain.py:583-652) *Note: the manual "Propose next round" (synchronous trigger) is unaffected; the "Start loop" auto-retrain is.*

### Correctness — DMTA sequence modality (added this session; mine to own)
3. **[MAJOR] Dead diversity on peptide/biologic proposals ✓.** `tanimoto_similarity` (binary-matrix) is applied to dense 31-d descriptors → similarity ≡ 0 → diversity term is inert AND the surfaced `diversity_score ≈ 1.0` is a meaningless number. Live run returned single-residue-apart near-duplicates. (bayesian_optimizer.py:461,505; fingerprint_surrogate.py:110-117)
4. **[MAJOR] Sequence Matérn GP over-parameterized.** 31 ARD length-scales + noise fit by MLL on ≤20 points → under-determined; posterior variance (→ EI/CIs shown to the user) driven by overfit hyperparameters. Small-molecule path deliberately avoids this. (sequence_surrogate.py:226-232)
5. **[MAJOR] 31-descriptor set is rank-deficient.** `gravy/arom_frac/aliphatic_frac/polar_frac/charged_frac/tiny_frac/unstable_frac` are exact linear functions of the 20-d AA composition that's also in the vector → collinear, inflates dimensionality for #4. (sequence_surrogate.py:105-136)
6. **[MAJOR] In-domain selection bonus mis-calibrated (added this session).** `combined = 0.8·acq + 0.2·div + 0.25·in_domain`; a flat +0.25 is ~25% of the acquisition range — it reshapes ~9/10 of the batch, not a "soft tie-break" as documented. (bayesian_optimizer.py:113,465-467)

### Correctness — general
7. **[MAJOR] `refit_and_propose` masks optimizer failures as an empty 422 ✓ (I hit this myself).** Any optimizer exception → `None` → "requires assay data and a cached virtual library" even when both exist. Hides real breaks. (auto_retrain.py:547-549; api_router.py:2106-2113)
8. **[MAJOR] Train→run loop is open.** Trained+registered models are in a separate non-servable registry, absent from the inference catalog → RunPretrained can't run them, `get_model` 404s. (owned-training-registry.tsx:21; models_inference.py:359-360)
9. **[MINOR→MAJOR] Repeated "propose" with no new data returns the identical batch but increments the round number** — false progress; `_screen_candidates` doesn't exclude previously-proposed-unmeasured compounds. (bayesian_optimizer.py:308-330,514)

### Platform integration
10. **[MAJOR] DMTA rounds + model inference are not first-class runs** — not billed, not in the Runs dashboard, not under the platform QC→remediation→retry auto-loop (which only the Boltz fold and Adapt retrain reach). The DMTA loop runs its own ad-hoc AD-gate + AuditStore self-correction. (models_inference.py; auto_retrain.py)
11. **[MAJOR · latent] Registry-path divergence.** `api_router._CAMPAIGN_REGISTRY_DB` is hard-coded; `models_inference` derives it from env. They agree only at defaults — set `BIOMATE_CAMPAIGN_DB_DIR` without `BIOMATE_CAMPAIGN_REGISTRY_DB` and the writer and the owner-reader fork → every Models track renders empty despite owned campaigns. (api_router.py:259-262; models_inference.py:172-174)
12. **[MINOR→MAJOR] Custom python-mode scorers can't run cross-worker** (callable lives in one worker's memory → stub on 3/4 GETs). (models_inference.py:1416-1451)

### Labels / status / dead code
13. **[MINOR] `optimise_track` reports `running: True` unconditionally ✓** — a stopped loop still shows green "running". (models_inference.py:1041)
14. **[MINOR] Stale tab-name copy after the "Design loop" rename** — empty-state strings point users at "Molecular models"/"分子学习" tabs that no longer exist (en + zh; zh worse). Shipped regression from the 2026-11-16 rename. (locales `no_model_chemical/genomic`, `launch_needs_smiles_file`)
15. **[MINOR] Duplicate training entry point** — identical launcher in Train and Design loop, no guidance which to use.
16. **[MINOR] Second project split-brain** — TrainingLauncher has its own project selector independent of the panel's `projectArg`; launch for a different project → run never appears in the list. (training-launcher.tsx:42; model-training-activity.ts:96)
17. **[MINOR] Shadowed/dead `train_track` + duplicate `virtual-library` route + ESMFold re-enable trap** — latent maintenance hazards. (routes.ts:5987 vs models_inference.py:655; api_router.py:1175 vs 2288; models_inference.py:95-99,1302-1316)
18. **[MINOR] `create_campaign` is destructive on re-create** — `INSERT OR REPLACE` with the ensure-campaign path wipes target/indication/sponsor/created_at. (api_router.py:2448-2463)
19. **[MINOR] Model-object detail largely inert from the panel** — compare/open-data/consumer affordances described in copy but not wired; `priorVersions` hardcoded `[]`.
20. **[MINOR · disclosed] PBPK `model_validation` metrics are tautological** (AUC computed from observed CL); honestly caveated but misleading if skimmed.

## Scope verdict
Scope is **right-shaped but over-packed, incoherent at the edges**: molecular training lives in the *Design loop* tab while *Train* also claims "molecular"; *Model library* does three jobs (catalog + owned registry + run-inference) with no bridge from "I trained this" to "I can run this"; the third pillar (adaptation) is carried as hidden dead code. It is **native to the execution platform, not bolted on** at the UI/run level — but the **campaign engine beneath the loop is a parallel stack** (own SQLite, own in-process loop, own auth posture, own self-correction).

## Proposed fix plan (tiers)
- **Tier 0 (do first — security + shipped regression):** #1 IDOR (owner-gate `/api/drug-discovery/*`), #14 stale tab names.
- **Tier 1 (correctness of what we just shipped — mine):** #3 sequence diversity (dense-space metric), #6 recalibrate AD bonus, #7 stop masking optimizer failures, #4/#5 de-ARD + prune redundant descriptors, #13 honest `running`.
- **Tier 2 (reliability/architecture — needs a design decision):** #2 move the loop off in-process dicts onto Redis/RunStateStore, #10 make DMTA rounds + inference first-class runs, #11 unify registry path, #8 close/relabel the train→run loop, #5(engine) adaptation's fate (surface or delete).
- **Tier 3 (hygiene):** #9, #12, #15–#20.

## Honesty note
Across ~20 findings, **zero fabrication**. The module's integrity is intact; its gaps are engineering and scope, which is the better failure mode to have.
