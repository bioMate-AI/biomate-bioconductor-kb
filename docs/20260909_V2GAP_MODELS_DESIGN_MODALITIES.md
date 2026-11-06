# V2 Gap Analysis — Models + Design & Generate surfaces vs claude-design v2

**Date:** 2026-09-09
**Scope:** Deployed BioMate `Models` and `Design & Generate` surfaces vs `data_centroid_design_v2`, with emphasis on the **new v2 chapters** (Spec 10 model use cases, Spec 11 all-modalities design) and the new `ModelCase.jsx` component.
**Mode:** READ-ONLY audit. No source edited.

Reference sets:
- **NEW v2 spec/dataui:** `/Users/kky/biomate-review/reference/claude_design/data_centroid_design_v2/`
- **OLD diff base:** `.../scratchpad/old_design/reference/claude_design/data_centroid_design/`
- **DEPLOYED:** `/Users/kky/biomate-review/frontend/client/src/`

Deployed counterparts audited:
- `components/models/{models-panel,model-object,run-pretrained,inference-result,models-api,types}.tsx/.ts`
- `components/design-generate/DesignGenerate.tsx` (+ `.test.tsx`)
- `components/viewers/{plddt-chart,pae-heatmap,structure-viewer,seq-tracks,hit-grid}.tsx`
- Routes in `App.tsx` (`/models`, `/design`)

---

## Executive summary

| Surface | Verdict |
|---|---|
| **Spec 11 — all modalities (design)** | **UNDONE.** Deployed `DesignGenerate.tsx` is 100% small-molecule (SMILES / scaffold / MW·logP·TPSA / hERG). No Modality control, no peptide/protein example sets, no `modalityOf()`/`wfFor()` routing. This is the single biggest gap. |
| **Spec 10 — model use cases (ModelCase)** | **UNDONE.** No worked-case page deployed. `ModelCase.jsx` / `data-modelcases.js` have no counterpart; the four-case spine (given → came-back → floor → left-behind), the register helper, and per-case reports are absent. |
| **Spec 10.1 — track renames** | **PARTIAL/UNDONE.** Deployed labels are `Train · Adapt · Optimise · Run a pre-trained model · Registry`. v2 renamed to `Train · House style · Rounds · Run a model · Registry`. Adapt→House style and Optimise→Rounds renames NOT applied. |
| **Spec 03 (+43) — Run a pre-trained model track (new)** | **DONE.** `RunPretrained` track shipped with structure/genomic/chemical domains, honest stub handling, model-named results. |
| **Spec 03 §3.8 — domain viewers (new)** | **PARTIAL.** pLDDT chart, PAE heatmap, seq-tracks + flagged-interval list, hit grid all exist. But in the pretrained inference path the **3D structure view is a placeholder slot** and the pLDDT→3D **linkage is not wired** (`onSelectResidue` handler not passed). |
| **Spec 05 §5.5.1 — two views of one ranking (new)** | **PARTIAL.** HitGrid renders a table/grid of candidates; no explicit table↔2D-depiction toggle in DesignGenerate; "held" verdict is honoured. |
| **Model object (ModelObject.jsx unchanged in v2)** | **DONE.** `model-object.tsx` implements identity/evidence/lineage/consumers/interface/versions/supersede — matches the unchanged v2 component. |

**Count: UNDONE = 8, PARTIAL = 7** (across the tables below).

---

## Surface 1 — Spec 11: Design & generate, ALL MODALITIES (the key gap)

**What v2 requires:** one design module carrying **every modality** — small molecule, peptide, protein/biologic — with **modality as a property of the request**, not the module. A `Modality` control (three chips: Small molecule · Peptide · Protein / biologic) sits under the track sentence; it selects the example set, persists across track changes, and **reaches the run card** (substitutes the run card's Modality param + the "stay-on" slot: scaffold / sequence motif / framework). Router gains peptide and protein/biologic rules. 34 worked example phrasings.

**Deployed reality:** `DesignGenerate.tsx` has **zero** modality awareness. Grep for `modality|peptide|macrocycle|protac|nanobody|biologic|stapl|helicity|antibody` across `components/design-generate` and `components/models` returns **no hits**. The constraint form is chemistry-only: SMILES seed, scaffold policy (stay/hop/grow), MW/logP/TPSA envelope, SMARTS exclusions, hERG in the multi-objective view.

| Element | v2 spec says (Spec 11) | New in v2? | Deployed | Evidence (file:line) | Priority |
|---|---|---|---|---|---|
| Modality control (3 chips) | Row under track sentence: Small molecule · Peptide · Protein / biologic (§11.2) | Yes | **UNDONE** | `DesignGenerate.tsx` — no Modality UI; form is `dg-seed-smiles`/`dg-scaffold-policy`/`dg-envelope` (`:1440`, `:1450`, `:1469`) | **P0** |
| Modality persists across tracks + travels with example | Held in own state, outranks inference, cleared on composer edit (§11.4 "held") | Yes | **UNDONE** | no modality state in component | P0 |
| Peptide example set | Cyclic binders, stapled analogues, macrocyclise; helicity, serum-cleavage; serum stability; synthesisability (§11.3) | Yes | **UNDONE** | absent | P0 |
| Protein/biologic example set | Nanobody candidates, CDR graft, enzyme redesign; complex/interface filter; developability, humanise, thermostability; expression/manufacturability (§11.3) | Yes | **UNDONE** | absent | P0 |
| `modalityOf(text)` inference | peptide/macrocycle/staple/helicity→peptide; antibody/nanobody/CDR/framework/enzyme/thermostability/construct/expression→protein; else small molecule (§11.4) | Yes | **UNDONE** | no text→modality inference | P0 |
| `wfFor(dom, modality)` → run card | Substitutes run-card Modality param + "stay-on" slot (scaffold / sequence motif / framework) (§11.4) | Yes | **UNDONE** | run card is `buildBody()` — hard-codes `generator:"brics"`, chemistry objectives (`:1343-1358`) | P0 |
| Track rename "Predict activity" → "Predict & filter" | Structure and activity both filter a candidate set (§11.1) | Yes | **UNDONE** | Spec-05 track copy still "Predict activity"; DesignGenerate has no per-track label surface | P1 |
| Modality-neutral lane sentence | "This reads like molecular design…" → neutral + peptide/biologic wording keyed to matched domain (§11.1) | Yes | **UNDONE** | router/composer copy not in this component (owned by composer surface) | P1 |
| Router peptide rules | peptide·macrocycle·stapled·helicity·serum stability·proteolytic·cell permeability·reduce charge → Peptide design (§11.5) | Yes | **UNDONE** | not present in deployed design surface | P0 (backend/router) |
| Router protein/biologic rules | antibody·nanobody·CDR·humanise·framework·enzyme variant·thermostability·aggregation·viscosity·expression·interface quality·keep the fold·hydrophobic patch·manufacturability → Protein & biologic design (§11.5) | Yes | **UNDONE** | not present | P0 (backend/router) |
| Seed-audit (no rule claims another domain's sentence) | bare `expression`/`developability` qualified/removed; audit is part of the change (§11.5 rule) | Yes | **UNDONE** | no router seeds deployed here to audit | P1 |

**Note on scope:** §11 explicitly lists open items even in the design — "PROTAC" is **not** a named modality in Spec 11; the three required chips are Small molecule / Peptide / Protein-biologic, with nucleic-acid (siRNA/mRNA/guide) flagged as an open question (§11.6), and PROTAC would fall under small-molecule/bifunctional generation (not a separate chip). So the required deployed set is **3 modalities**, and deployed supports **1** (small molecule).

---

## Surface 2 — Spec 10: Worked examples — model use cases (ModelCase)

**What v2 requires:** a `ModelCase` page — one spine for all four tracks — answering: what model, what it was given, what came back, how much to trust, what it left behind. Anatomy (§10.4): model chip → "what this was given" (inputs to versions, exclusions with rules) → stages chips ("waiting" until eval) → "what came back" (headline + honest block) → boundary → floor table → artefacts (files, Open&edit / Open in Files) → next steps (decisions, incl. `register` new helper that moves registry row + card atomically). Four cases: `run_fold`, `train_potency`, `adapt_gen`, `opt_loop`. Each leaves its own report in `runs/models/`.

**Deployed reality:** no worked-case page. Grep for `MODEL_CASES|modelCaseFor|CASE_DOC|CASE_REGISTER` returns only unrelated test fixtures. The deployed Models tracks render descriptive/empty-state content or live registry rows — there is no example-click → case-page landing.

| Element | v2 spec says (Spec 10 / ModelCase.jsx) | New in v2? | Deployed | Evidence | Priority |
|---|---|---|---|---|---|
| Worked-case page (one spine, 4 tracks) | `ModelCase` component; `modelCaseFor(query,track)` resolves a case (§10.3-10.4) | Yes | **UNDONE** | no `ModelCase`/`modelCaseFor` in deployed source | **P1** |
| model chip (link into registry object) | Name+version, only registry-existing names (§10.4) | Yes | **UNDONE** | no case page; registry links exist separately in `models-panel.tsx:88` | P1 |
| "What this was given" (inputs→versions, excluded+rule) | e.g. training data v4, scaffold split, 311 censored excluded (data-modelcases.js:42-45) | Yes | **UNDONE** | absent | P1 |
| Stages chips ("waiting" pre-result) | Nothing reported until eval stage finishes (§10.4) | Yes | **UNDONE** | absent | P1 |
| "What came back" + honest block | Headline + one always-honest block (flag / round-in-flight) (§10.4) | Yes | **UNDONE** | absent | P1 |
| Boundary statement | What the result is NOT evidence for; present on all 4 (§10.4) | Yes | **UNDONE** | absent | P1 |
| Floor table (metric·value·threshold·verdict) | A floor not a ranking (§10.4) | Yes | **UNDONE** | absent (floor logic exists only inside model-object gate) | P1 |
| Artefacts as files (Open&edit / Open in Files) | Reports get Open&edit + download; tables/artefacts get Open in Files (§10.4) | Yes | **UNDONE** | absent | P2 |
| `register` helper (atomic registry+card move) | new: one helper moves registry row + card, marks prev superseded, re-reads live (§10.4) | Yes | **UNDONE** | no case register; `onSupersede` exists on model-object only (`model-object.tsx:104`) | P2 |
| Per-case reports (fold/train/adapt/loop_report.md) | Each case its own report in runs/models/ (§10.6) | Yes | **UNDONE** | absent | P2 |
| Registry additions (fold-predict v2.3, molgen v4.1) | Two models added so every case names an openable object (§10.5) | Yes | **UNDONE (data)** | depends on live `/api/models` catalog; not verifiable in client | P2 |

**Track renames (§10.1 / Models.jsx +21):**

| Element | v2 says | New in v2? | Deployed | Evidence | Priority |
|---|---|---|---|---|---|
| "Adapt" → "House style" (Models tab) | House-style surface: learns wording, never changes a number; points to Tune on our data (§10.1) | Yes | **UNDONE** | `MODELS_TRACKS = ["Train","Adapt","Optimise","Run a pre-trained model","Registry"]` (`models-panel.tsx:36-42`) | **P1** |
| "Adapt fine-tune" → "Tune on our data" | base frozen, your delta kept separate (§10.1) | Yes | **UNDONE** | Adapt track still labelled "Adapt" (`models-panel.tsx:38`) | P1 |
| "Optimise RL & active learning" → "Propose & test in rounds" | a budget you set, not an algorithm (§10.1) | Yes | **UNDONE** | tab is "Optimise" (`models-panel.tsx:39`); OptimiseTrack copy is DMTA-rounds already (good) but label unchanged | P1 |
| Workspace vs project Models entry (Models.jsx §3.4 revision) | Two entries: workspace registry always; project entry only after model work; `scope==='workspace'` chip + copy (Models.jsx diff) | Yes | **PARTIAL** | Registry track copy says "account-level" (`models-panel.tsx:75`), but no `scope` prop / workspace-vs-project split in `ModelsPanel` | P2 |

---

## Surface 3 — Spec 03 Models (revised +43) — deployed status

The revised Spec 03 additions are the **new 4th track** (Run a pre-trained model), the **domain viewers §3.8**, and copy/role additions. The deployed `ModelsPanel` predates the §10 renames but DID ship the §3.2.4 pre-trained track and the §3.8 viewers.

| Element | v2 spec says (Spec 03) | New in v2? | Deployed | Evidence | Priority |
|---|---|---|---|---|---|
| 4th track "Run a pre-trained model" | Inference from already-fitted model, with confidence (§3.2.4) | Yes (+43) | **DONE** | `RunPretrained` track, tab 3 (`models-panel.tsx:40`, `run-pretrained.tsx`) | — |
| Pre-trained: 3 domains stated as achievements | structure / genomic / chemical, "predict a structure and tell me where to trust it" (§3.2.4) | Yes | **DONE** | `DOMAINS[]` structure/genomic/chemical with goal+produces (`run-pretrained.tsx:45-82`) | — |
| Pre-trained evidence = published + local spot-check | Published by authors + local spot-check earns the gate (§3.2.4 table) | Yes | **PARTIAL** | model-object shows evidence gate; "published vs held-out" distinction not explicitly surfaced in pretrained result | P2 |
| Model named on the result, not front door | name+version accountable on result (§3.9 copy rule) | Yes | **DONE** | result card shows `modelId` (`run-pretrained.tsx:259`); why-row model+version (`DesignGenerate.tsx:250-261`) | — |
| §3.8.1 Structure: 3D view | Familiar viewer; alone insufficient (§3.8.1) | Yes | **PARTIAL** | pretrained path renders a **placeholder slot** ("3D structure viewer" label + file ref), not the real `structure-viewer.tsx` (`inference-result.tsx:86-100`) | **P1** |
| §3.8.1 Structure: per-residue confidence chart, **linked to 3D** | hover reads residue+score; click centres 3D; one selection (§3.8.1) | Yes | **PARTIAL** | `PlddtChart` exists and exposes `onSelectResidue` (`plddt-chart.tsx:42,95`) but `StructureView` does NOT pass a handler → **link not wired** (`inference-result.tsx:101`) | **P1** |
| §3.8.1 Structure: pairwise error heatmap | dark blocks confident, pale off-diagonal unresolved (§3.8.1) | Yes | **DONE** | `PaeHeatmap` rendered (`inference-result.tsx:102`) | — |
| §3.8.1 low-confidence regions listed in words | "Loop 43–57 · low confidence…"; each row centres 3D (§3.8.1) | Yes | **PARTIAL** | PlddtChart renders a regions list (`plddt-chart.tsx:182`), but row→3D centring inert (same missing handler) | P1 |
| §3.8.2 Genomic: tracks + flagged-interval list | flagged interval is the output; tracks are how you check (§3.8.2) | Yes | **DONE** | `SeqTracks` with `flagged` list (`inference-result.tsx:108-126`, `seq-tracks.tsx:34-50`) | — |
| §3.8.3 Chemical: ranked hit table + 2D depiction grid | chemist reads structures; held candidates no confident number (§3.8.3) | Yes | **PARTIAL** | `HitGrid` renders hits + held handling (`inference-result.tsx:130-152`); depiction-grid alternate view depends on HitGrid internals (not verified to render real 2D structures) | P2 |
| Registering requires Owner role | new: role gate + recorded name (§3.6 Registered row) | Yes | **UNDONE** | no role/RBAC gate on register in deployed models UI | P2 |
| Model object shape (identity/evidence/lineage/used-by/interface/versions) | §3.3 | (unchanged) | **DONE** | `model-object.tsx:106` destructures identity/evidence/lineage/consumers/versions; interface signature `:57`; supersede `:104` | — |

---

## Surface 4 — Spec 05 Design & generate (revised) — deployed status

Only material v2 change vs old is **§5.5.1 "Two views of one ranking" (new)** and the §5.8 "scoring model is pre-trained" row. The core pipeline (generate→predict→optimise→rank) is well-covered in `DesignGenerate.tsx`.

| Element | v2 spec says (Spec 05) | New in v2? | Deployed | Evidence | Priority |
|---|---|---|---|---|---|
| §5.5.1 Two views of one ranking (table ⇄ 2D grid toggle) | Same ranking/verdicts, switched by a control; grid renders from structures (§5.5.1) | Yes | **PARTIAL** | HitGrid is used (`DesignGenerate.tsx:1634`) but there is **no explicit table↔depiction-grid toggle** in the design surface; MultiObjectiveView is a table only | **P1** |
| §5.5.1 held candidate marked, ranked nowhere | held: shown, ranked nowhere, no confident number (§5.5.1) | Yes | **DONE** | `reRank` sends held to end (`DesignGenerate.tsx:531-540`); WhyRow held note (`:277`) | — |
| §5.8 scoring model pre-trained, not ours | prediction still names model+version; object says published (§5.8) | Yes | **PARTIAL** | why-row names model+version (`:250-261`); "published vs held-out" label not surfaced in design why-row | P2 |
| Constraints ARE the interface (§5.2) | target/scaffold/envelope/exclusions/count+cost | (existing) | **DONE** | constraints composer (`:1425-1573`) | — |
| Chemistry validity gate, counted+characterised (§5.2) | "412 of 500 passed; 61 failed SA…" | (existing) | **DONE** | `RejectionProfile` buckets by cause (`:871-930`) | — |
| No composite score; per-objective units (§5.4) | never a blended number; weights the user's | (existing) | **DONE** | `MultiObjectiveView` + score-is-ranking-key copy (`:295-405`) | — |
| Safety a gate; rejected stays visible (§5.4) | rejected with reason, kept | (existing) | **DONE** | `RejectedSet` (`:411-459`) | — |
| Editable criteria/weights re-rank without re-run (§5.5) | changing weights re-ranks, no re-prediction | (existing) | **DONE** | `CriteriaStrip` + client `reRank` (`:542-636`, `:531`) | — |
| Trade-off / Pareto shown not collapsed (§5.4) | front shown | (existing) | **DONE** | `ParetoView` inline SVG (`:647-838`) | — |
| Order sheet export (§5.5/§5.7) | candidate ids ↔ registry ids, per-objective units | (existing) | **DONE** | `buildOrderSheetCsv` + `OrderSheetButton` (`:951-1027`) | — |
| Predicted-vs-measured record (§5.7) | measured vs predictions, contradictions flagged | (existing) | **DONE** | `PredictedVsMeasured` (`:1144-1256`) | — |
| Entry routes: dataset / Models / Search (§5.6) | three in-app navigations, `?from=design` marker | (existing) | **DONE** | `EntryRoutes` + `ENTRY_ROUTE_TARGETS` (`:1050-1124`) | — |

---

## Coverage checklist

Spec 11 (all modalities) — deployed design surface
- [ ] Modality control (3 chips) — **UNDONE**
- [ ] Modality persists + travels with example — **UNDONE**
- [ ] Peptide example set — **UNDONE**
- [ ] Protein/biologic example set — **UNDONE**
- [ ] `modalityOf(text)` inference — **UNDONE**
- [ ] `wfFor(dom, modality)` reaches run card — **UNDONE**
- [ ] Router peptide + protein/biologic rules — **UNDONE**
- [ ] "Predict activity" → "Predict & filter" — **UNDONE**
- [ ] Modality-neutral lane sentence — **UNDONE**

Spec 10 (model use cases) — ModelCase + renames
- [ ] Worked-case page (4-track spine) — **UNDONE**
- [ ] given / came-back / floor / left-behind / boundary / next — **UNDONE**
- [ ] `register` atomic helper — **UNDONE**
- [ ] Per-case reports — **UNDONE**
- [ ] Adapt → **House style** — **UNDONE**
- [ ] Optimise → **Rounds / Propose & test in rounds** — **UNDONE**
- [ ] "Run a pre-trained model" → **"Run a model"** — **UNDONE (label)**
- [~] Workspace vs project Models entry — **PARTIAL**

Spec 03 §3.8 (domain viewers)
- [x] Pre-trained track — **DONE**
- [x] PAE heatmap — **DONE**
- [x] Genomic tracks + flagged intervals — **DONE**
- [~] 3D structure real viewer in pretrained path — **PARTIAL** (placeholder slot)
- [~] pLDDT chart LINKED to 3D (click centres) — **PARTIAL** (handler not wired)
- [~] Chemical 2D depiction grid — **PARTIAL**
- [ ] Owner-role gate on register — **UNDONE**

Spec 05 §5.5.1 (two views)
- [~] Table ⇄ 2D grid toggle — **PARTIAL**
- [x] Held candidate handling — **DONE**
- [~] Published-vs-held-out label in why-row — **PARTIAL**

Model object (unchanged in v2)
- [x] identity/evidence/lineage/used-by/interface/versions/supersede — **DONE**

---

## Recommended priority order

1. **P0 — Spec 11 modality control end-to-end** (chips → state → `modalityOf`/`wfFor` → run card) + router peptide/protein rules. This is the headline gap: a protein or peptide designer currently finds an empty small-molecule form. Biggest user-visible correctness issue.
2. **P1 — Track renames** (Adapt→House style, Optimise→Rounds, "Run a pre-trained model"→"Run a model") — cheap, high legibility payoff, and unblocks the §10 vocabulary.
3. **P1 — Wire pLDDT→3D linkage + real 3D viewer** in the pretrained structure path (`onSelectResidue` handler + swap placeholder slot for `structure-viewer.tsx`). The pieces already exist; they are just not connected.
4. **P1 — ModelCase worked-case page** (the §10 spine) — larger build; port `ModelCase.jsx` + `data-modelcases.js` to a deployed component.
5. **P1 — §5.5.1 table↔2D-grid toggle** in DesignGenerate.
6. **P2 — Owner-role register gate, published-vs-held-out labels, workspace/project Models split.**

---

## Tallies

- **UNDONE:** 8 distinct areas — Spec 11 modality (counts as one large area spanning ~10 elements), ModelCase worked-case page, 3× track renames, register helper, per-case reports, Owner-role register gate. Element-level UNDONE rows across all tables ≈ **28**.
- **PARTIAL:** 7 areas — 3D-in-pretrained slot, pLDDT→3D linkage, low-confidence region centring, chemical 2D grid, §5.5.1 toggle, published-vs-held-out label, workspace/project split.
- **DONE:** pre-trained track, PAE heatmap, genomic tracks+flagged, model object, and the entire Spec-05 core pipeline (constraints, validity gate, no-composite multi-objective, rejected-set, criteria re-rank, Pareto, order sheet, predicted-vs-measured, entry routes).

**Headline:** The deployed surfaces are strong on the **pre-v2** Spec 03/05 core (model object + design pipeline), but the **two new v2 chapters are essentially unbuilt**: Spec 11 all-modalities design (0 of 3 modalities → only small molecule) and Spec 10 model-use-case pages (no ModelCase). Plus the §10 track renames and the §3.8.1 pLDDT↔3D linkage are unshipped/unwired.
