# 2026-11-16 — Design requirements: "Design loop" + multi-modality DMTA UI (for the Claude design reference & tutorial demos)

**Why this doc:** the work shipped this session introduces UI that does **not** exist in the Claude design reference (`localhost:7779`): the renamed **Design loop** tab, a **modality selector** (small molecule / peptide / biologic), a **candidate-library generator**, and the first **sequence (peptide/biologic) design–make–test loop**. These are the requirements to (a) add these surfaces to the Claude design reference and (b) build tutorial demos around them. Everything below reflects the as-built, deployed behavior on DEV (verified end-to-end), not a proposal.

Audience: design-reference authors and tutorial authors. Companion docs: `20261115_MODELS_MODULE_UX_CLARITY_PLAN.md` (why the IA changed), `20261116_SEQUENCE_DMTA_MODALITY.md` (the engine).

---

## 1. Scope of the new surfaces

All live inside the **Models side panel → "Design loop" tab** (route value unchanged: `/models?tab=molecular`).

1. **Design loop tab** — renamed from "Molecular learning"; the DMTA **Rounds** section now leads, with the property-model launcher demoted beneath it.
2. **Modality selector** — Small molecule · Peptide · Biologic.
3. **Candidate-library generator** — seed input + "Generate candidate library" (peptide/biologic only).
4. **Rounds controls** — Create campaign · Start loop · Stop · Propose next round.
5. **Loop surrogate launcher** — "Train or refit the loop's model" (molecular property model).

## 2. Layout & component spec (top → bottom)

```
┌─ Models ─ [N registered] ──────────────────────────────────────────┐
│ Train a model on your data, reuse your saved and built-in models,   │  ← panel subtitle (orientation)
│ or run a design–make–test loop.                                     │
│ [ Train ] [ Model library ] [ Design loop* ]                        │  ← 3 tabs; Design loop selected
├─────────────────────────────────────────────────────────────────────┤
│ Run an iterative design–make–test cycle to improve a molecule       │  ← tab purpose (goal-framed)
│ series — propose candidates, add results, refit each round.         │
│                                                                      │
│  Rounds · design · make · test · analyse                             │  ← RoundsSection (LEADS)
│  Bayesian propose / refit under an assay budget — campaign APIs,     │
│  not generative lead design.                                         │
│  [honest empty state when no campaign is active]                     │
│                                                                      │
│  Modality:  [Small molecule*] [Peptide] [Biologic]                   │  ← MODALITY SELECTOR (new)
│  ┌ (peptide/biologic only) ──────────────────────────────────────┐  │
│  │ [ seed sequence input ]  [Generate candidate library]  hint    │  │  ← GENERATOR (new)
│  └────────────────────────────────────────────────────────────────┘  │
│  [Create campaign] [▶ Start loop] [□ Stop] [⟳ Propose next round] ⓘ  │  ← Rounds controls
│  [action success / error line]                                       │
│                                                                      │
│  The loop ranks candidates with a property model. Train or refit     │  ← loop_model_note
│  the one this loop uses here:                                        │
│  ┌ Train or refit the loop's model ────────────────────────────────┐ │  ← surrogate launcher (demoted)
│  │ Project ▾  Dataset ▾ [Upload]  [▶ Start training]               │ │
│  └──────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

### 2.1 Modality selector (`data-testid="optimise-modality"`)
- Three segmented buttons: **Small molecule** (default, filled), **Peptide**, **Biologic** (`optimise-modality-{small_molecule|peptide|biologic}`).
- Changing modality is a local choice; it is written to the campaign at **Create campaign** time and fixes the loop's engine (small molecule → Morgan/Tanimoto GP; peptide/biologic → sequence-descriptor Matérn GP).
- Design requirement: the selector must sit **above** the create controls and be visually a "mode" control (segmented), not an action.

### 2.2 Candidate-library generator (`data-testid="optimise-generate"`) — peptide/biologic only
- **Hidden entirely for small molecule** (small molecule uses REINVENT4 generative design, a separate surface).
- Monospace **seed sequence** input (placeholder: "Seed sequence (e.g. GQVGRQLAIIGDDINR)") + **Generate candidate library** button + a one-line hint ("Enumerates point mutants of the seed as the virtual library.").
- On success: "Generated N candidate sequences and cached them as the virtual library — propose a round now."

### 2.3 Rounds controls (`data-testid="optimise-controls"`)
- **Create campaign** (`optimise-create-campaign`): small molecule seeds the real public BACE demo ("Seeded 203 Train-split assay rows and 500 virtual-library SMILES…"); peptide/biologic creates an **empty** campaign with an honest message ("Peptide campaign created. Ingest your measured sequences … no demo data is seeded for this modality.").
- **Start loop / Stop / Propose next round** — hit the real campaign APIs; errors surface verbatim (honesty requirement — never fabricate a round).

## 3. States (required coverage in the design reference)

| State | What the panel shows |
|-------|----------------------|
| **No campaign** | Honest empty copy; Create enabled; Start/Propose surface "no data" if clicked |
| **Small-molecule campaign created** | Seeded-count success line; Propose produces a round |
| **Sequence campaign created (empty)** | "Ingest measured sequences" guidance; generator visible |
| **Library generated** | "Generated N candidates…" line |
| **Propose — success** | Ranked candidates + predicted scores + an **honest `can_discriminate` flag** ("the loop reports when it cannot confidently rank") + applicability-domain status |
| **Propose — insufficient data** | Real 422 ("need at least 16 observations") surfaced, not hidden |
| **No project selected** | "Select a project" and controls disabled |

**Honesty rules (non-negotiable in demos):** no fabricated scores or rounds; `can_discriminate:false` must be shown when true; the surrogate report names the actual kernel (Tanimoto for small molecule, **Matérn(nu=2.5)** for sequences) and featuriser (`sequence_descriptors_v1`, 31 physicochemical descriptors for sequences).

## 4. Tutorial demo flows (ready to script, all verified live on DEV)

### Demo A — Small-molecule DMTA (regression of the existing loop)
1. Design loop tab → **Small molecule** (default) → **Create campaign** → "Seeded 203 assays + 500 SMILES".
2. **Propose next round** → ranked compounds with scores + `can_discriminate`.

### Demo B — **Peptide design–make–test loop (new, headline tutorial)**
1. Design loop tab → **Peptide**.
2. Enter a seed (e.g. the BAK BH3 helix `GQVGRQLAIIGDDINR`) → **Generate candidate library** → "Generated ~120 candidates".
3. **Create campaign** (peptide) → ingest measured sequences (a small CSV of sequence + IC50; tutorial supplies a real or clearly-labelled-demo set — never fabricated as measured).
4. **Propose next round** → the Matérn-GP surrogate ranks sequence candidates; top proposals should track the structure–activity signal (e.g. charge-increasing K/R substitutions when the series rewards charge), with `can_discriminate` and applicability-domain flags shown.

### Demo C — Biologic (antibody/scFv) loop
Same as Demo B with **Biologic** and a CDR-H3-style seed (e.g. `ARDYYGSGSYYNAFDI`). Identical engine; different descriptor regime.

**Cold-start parity:** these map to the cold-start "Models → Optimise" (now "Design loop") intents. New tutorial seed candidates for the Models module: *"Run a peptide design–make–test loop on this BH3 series"* and *"Improve this antibody CDR for affinity under a budget"* — both deep-link to `/models?tab=molecular` and set the modality.

## 5. Data-testids (for reference-page parity tests)
`models-panel-subtitle`, `models-track-2` (Design loop tab), `tab-purpose-molecular`, `optimise-modality`, `optimise-modality-{modality}`, `optimise-generate`, `optimise-gen-seed`, `optimise-generate-library`, `optimise-create-campaign`, `optimise-start`, `optimise-stop`, `optimise-trigger`, `loop-surrogate-section`.

## 6. APIs the UI drives (for demo fixtures / connectors)
- `POST /api/drug-discovery/campaigns` `{campaign_id, modality}`
- `POST /api/drug-discovery/{id}/generate-library` `{seed, max_size}` (peptide/biologic)
- `POST /api/drug-discovery/{id}/ingest-assay` (multipart CSV; sequence entities accepted when modality is peptide/biologic)
- `POST /api/drug-discovery/{id}/propose` `{virtual_library_smiles, n_propose}` → ranked candidates (+ `surrogate_report`, `can_discriminate`, `ad_statuses`)
- `POST /api/drug-discovery/{id}/retrain/{start|stop|trigger}` (the panel's loop buttons)

## 7. i18n
All copy comes from `models.*` in `frontend/client/src/locales/{en,zh}/common.json`; the design reference must use the same strings (both locales exist and are kept in parity). New keys: `rounds_modality_*`, `rounds_gen_*`, `rounds_created_sequence`, `loop_model_note`, `panel_subtitle`.
