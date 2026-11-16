# 2026-11-15 — Models surfaces UX E2E verification (sidebar panel + cold-start examples)

**Env:** live DEV `https://dev-public.biomate.ai`, tip `77969b9c` (Option A DMTA UX + reinvent4 fixes deployed).  
**Method:** Claude-in-Chrome driving the real SPA in the fixture session (userId `fd5a73ac`, project "test"). Rendered-content + live-API verification, no mocks.  
**Scope:** every tab's content on both Models surfaces, plus a representative end-to-end send for each routing class.

## Surface A — Sidebar Models panel (`/models`) — ALL TABS VERIFIED

`MODELS_TRACKS = ["train","library","molecular"]`; Adapt tab hidden (`HOUSE_STYLE_HIDDEN=true`) — **confirmed absent** in UI.

| Tab | Content verified (rendered on DEV) |
|-----|-----------------------------------|
| **Train (0)** | Purpose text; **No-code / Code** path toggle. No-code: "Train a model" launcher (Project=test, Dataset picker, Upload, Start training) + **Training runs** list with a real completed run ("potency predictor, MAE 0.943, Gate passed, 11/13/2026"). Code: Run-code sandbox ("same run_code engine as chat"), Project + Input picker, Python/R/Bash toggle, editor with `INPUT_FILES`/`OUTPUT_DIR` scaffold, Run. |
| **Model library (1)** | Model library table (real row **Boltz-2 2.0 · structure · BioMate compute · Used by 0**); **Registered training artifacts** ("Refresh versions", honest empty state); **Run a model** inference (Structure/Genomic/Chemical families; Boltz-2 → 3D structure/pLDDT/PAE). |
| **Molecular learning (2)** | Purpose text; **Train a molecular model** launcher (Chemprop GNN = chemprop_train.nf note); **Rounds · design · make · test · analyse** with honest "not generative lead design" framing + controls **Create campaign / Start loop / Stop / Propose next round** (Bayesian round). |

**Rounds exercised live (not just rendered):**
- **Create campaign** → `"Campaign ready. Seeded 203 Train-split assay rows and 500 virtual-library SMILES from cold-start loop fixtures — you can propose a round now."` (real campaign API + dmta-loop-fixtures seed).
- **Propose next round** → `"Propose / refit requested — refresh rounds below when the proposal lands."` (real trigger, honest async).
- **Start loop** deliberately NOT clicked (would launch the auto-retrain compute loop).

## Surface B — Cold-start Models module — ALL TABS VERIFIED

Cold-start dashboard → **Models** module ("Train, adapt or optimise a model on your data") → 3 track tabs. "Each example comes with sample data. Click to prepare a draft; review before sending."

| Track tab | Seed cards (content verified) | Representative E2E send → routing |
|-----------|-------------------------------|-----------------------------------|
| **Train** | "Train a potency predictor…", "Train an hERG classifier…", "Train a solubility model…" | **Sent "Train a potency predictor…"** → attached `bace_assays.csv` (189.9 KB) → **ML TRAINING** card "potency predictor", `bace_assays.csv` bound, **Target column = pIC50**, Smiles Col = smiles. ✓ (ml_training/chemprop path, not reinvent/diffusion). herg/solubility share this verified path. |
| **Adapt** | "Adapt the generative model to our chemical series.", "Fine-tune this property predictor on our measured compounds." | **Sent "Adapt the generative model…"** → attached 4-file molecules fixture → card = **REINVENT4 Generative Lead Design** (`reinvent4_lead_design`, DRUG DISCOVERY, 5 phases; Receptor=1IEP.pdb, Custom Toml=pilot_target_info.json). **⚠ DISCREPANCY:** the audit catalog expects this seed → `reinvent4_finetune_rl`, which **is a separate workflow in the DB** ("Reinvent4 Finetune Rl"). Routing reached the REINVENT4 family (correctly NOT Train/chemprop or DMTA) but **not the dedicated fine-tune workflow**. Not a crash — a routing/expectation mismatch to reconcile (see §Finding-correctness). The fine-tune-property seed shares the Train chemprop path (not separately sent). |
| **Optimise** | "Run the design–make–test loop … 96-assay budget.", "Propose the next round and refit on the results." | Verified earlier via `/api/chat/stream`: both → `chat_only`, **no workflow card**, deep-link to `/models?tab=molecular` ("not reinvent4_lead_design"). ✓ |

## Coverage summary

- **6 panel tab-states** (Train no-code, Train code, Library, Molecular + Rounds create + Rounds propose) — all rendered with real content/data.
- **3 cold-start track tabs** — all seed cards rendered; sample-data attachment confirmed per seed.
- **3 routing classes** exercised end-to-end on the live build: Train→`ml_training`, Adapt→`REINVENT4`, Optimise→DMTA deep-link.
- **Honesty checks pass:** provenance framing on Train ("public tutorial data, not in-house"); "predicted not measured" on Adapt; "not generative lead design" on Rounds/Optimise.
- Did **not** click Confirm & Run on the generated Train/Adapt cards or Start loop (avoid launching training/generation compute). Routing/content is what this verification targets; execution of the REINVENT4 generative path was already proven separately (run `388bb16a`, see `20261115_COLDSTART_MODELS_MODULE_AUDIT.md`).

**Verdict:** Both Models surfaces render correct content in every tab on the live DEV build; Train→`ml_training` and Optimise→DMTA deep-link are correct end-to-end. One open item (below).

## Finding-correctness check (outputs / reports / findings re-verified, not just asserted)

Done after the initial write-up, in response to "output, report, finding correctness checked?".

**Reinvent4 run `388bb16a` outputs — CORRECT, with one honest caveat.**
- Params honored: `design_summary.json` / `validated_input.json` show `n_steps=20, batch_size=16`, `molecules_generated=80`, `molecules_after_filter=20` (= my `top_n=20`). `filter_stats.json`: 80→20. Counts consistent across files (`top_compounds.csv`=20 rows, `raw_molecules.csv`=80).
- Molecules valid: `reinvent.log` = "Parsed 309 valid unique SMILES", "Removed 11 invalid SMILES" (the "failed to sanitize" lines are expected INFO, correctly filtered); QED/SA/MW descriptors computed per compound (server-side RDKit) ⇒ SMILES parse. No errors/traceback; peak mem 572 MiB; "Finished REINVENT".
- **CAVEAT (now stated honestly):** this was a deliberate **20-step toy run**; the RL score trajectory *declines* (epoch1 mean 0.88 → epoch20 0.38), so the outputs are **not optimized leads** — the run proves the pipeline *executes* (the procps/`"""`/layout/prior_path fixes work), it does **not** demonstrate generative quality. `top_compounds` are the best from early sampling. Earlier phrasing "real generative chemistry" is accurate (valid molecules) but should not be read as "good leads".

**Reports — CORRECT.** `design_report.html` is a real "BRICS Lead Design Report" (styled HTML, Seed/Mode header, ranked 20-row SMILES/Score/QED/SA/MW table matching `top_compounds.csv`), not an error page. (`report.html` 3 MB = fuller version, not separately opened.)

**Findings:**
- Train potency → `ml_training` "potency predictor", `target_col=pIC50`, `bace_assays.csv` bound — **CORRECT** (matches audit expectation).
- Optimise ×2 → `chat_only`, no card, deep-link `/models?tab=molecular` — **CORRECT**.
- Adapt generative → `reinvent4_lead_design`, **expected `reinvent4_finetune_rl`** — **DISCREPANCY** (both workflows exist; routing picks the generic generative one, not the dedicated fine-tune). Recommend: either add routing for "adapt/fine-tune the generative model to our series" → `reinvent4_finetune_rl`, or correct the audit catalog if lead_design-with-reference-actives is the intended realization. Flagged, not silently passed.
