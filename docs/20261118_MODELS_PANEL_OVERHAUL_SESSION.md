# Models Panel + Adaptation Overhaul — session record (2026-11-18)

**Live on dev at `abd6a0cac4`** (healthy, smoke passed). Rebased onto the auth-fix
line `eb1382938e` on every deploy so nothing regressed. Branch: `feat/models-gpu-tier`.

## Shipped + live
The panel was "confusing + too limited ML/DL" (user). Fixed, in order:
- **Adaptation backend** (`4a1fea1612`, `b4c24d7fc5`): `adapt_of` threads config→plan→ga;
  an adaptation registers as the base model's NEXT version (same campaign+name) and
  surfaces `priorVersions`. `workflow_type:"adaptation"` run-tagging flows automatically.
- **Adapt-a-model UI** (`c53a3f95c8`, `95cee3241f`, `6c2eb957c2`): the Adapt tab FUNCTIONS —
  always offers a built-in base to fine-tune (SmolLM2-135M) + your registered models to
  version; picking the LLM base constrains the launcher to LLM methods + guides to text
  data. Node `PLAN_FORWARDED_FIELDS` += `adapt_of` (was silently stripped).
- **Broken options fixed** (`2fe58b2a3e`): TabDDPM + Chemprop GNN were offered but failed
  on launch → now blocked with an honest reason (pattern of `protein_diffusion`).
- **Clarity pass** (`2281e6d7a1`, `1e1c9ea917`, `3c0d2484a6` + the deep-link fix `ecbaa55669`):
  Train model-list is data-dependent (explained); Design-loop reads as "the loop's own
  model" (vs standalone Train) with dev-jargon cut; Library sections framed browse-vs-run.
- **Rule-following** (`abd6a0cac4`): GRPO `composite` reward surfaced — a JSON rule list
  (`contains_any`/`banned`/`regex`/`numeric_threshold`/`implies`/`order`…) the RL run
  optimizes toward; plan accepts composite WITH a reward_spec. Completes all 4 methods
  (SFT · DPO · RL · rule-following).
- **GPU tier code** (`fd22b1fba6`, flag OFF): routing + GPU `.nf` wrapper + bf16-on-GPU,
  gated by `ML_TRAINING_GPU_LLM`. See `docs/20261118_ML_TRAINING_GPU_TIER.md`.

Tested throughout: tsc clean; frontend vitest **4024 passed**; ml_training backend tests.

## Open / deferred (for the team — nothing blocking)
- **GPU tier activation** = AWS infra + cost decision: build the CUDA trl-training image
  (CI), executor image selection under the flag, provision a GPU Batch queue sized for the
  target model, flip `ML_TRAINING_GPU_LLM=1`, validate one small run. Full checklist in
  `docs/20261118_ML_TRAINING_GPU_TIER.md`. Per CLAUDE.md, no GPU job runs speculatively.
- **Other disabled families:** `chemprop_gnn` (no training loop yet), `protein_diffusion`
  (RFdiffusion container unprovisioned), `tabular_diffusion` (no run wrapper) — each
  infra/code work, all currently blocked honestly in the UI.
- **Structural clarity (user-deferred, product calls):** dedup training across Train +
  Design-loop; restructure Library so "Run" launches from the catalog row.
- **Adaptation auto-loop billing:** rounds fired by the backend auto-retrain loop don't
  pass through the Node tagging; billing those needs a backend-emitted run event. See
  memory `general-model-adaptation-plan`.
- **House-style / IND path** stays dormant (its only consumer, the IND editor, is
  commented out). The Adapt tab's general path is the live one.

## Cross-session coordination
Ran concurrently with kky-fd (auth fix `eb1382938e`, chat-history 401 cascade) + kky-17
(disk/manuscripts). Caught that deploying my branch on its `ecbaa55669` base would have
regressed the auth fix → rebased onto the live tip each time. Each deploy I pinged kky-fd
the new tip so their pending sidebar/delete rebases cleanly. Regression audit:
`docs/20261118_MODELS_PANEL_REGRESSION_AUDIT.md`.
