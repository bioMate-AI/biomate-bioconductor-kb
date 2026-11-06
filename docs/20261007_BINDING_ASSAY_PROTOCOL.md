# Binding-Assay Protocol — Macrocycle Validation vs αvβ6 and GRPR

**Date:** 2026-10-07
**For:** wet-lab execution (membrane-protein / structural background assumed)
**Purpose:** measure binding affinity (Kd / IC50 → Ki) of designed cyclic peptides against the two
program targets, as the TEST arm of the self-driving loop
([[project_self_driving_lab]], [[project_act_application_status]]).
**Data back to:** `sdl-macrocycle` `sdl/assays/fp_binding.py` (`fit_direct_kd`, `fit_ic50`,
`ic50_to_ki`) — raw plate values in, Kd/Ki out, straight into the model.

> **Two targets, two assay classes.** αvβ6 is a soluble **integrin ectodomain** → biochemical
> assay with purified protein (FP / ELISA / BLI). GRPR is a **GPCR** (membrane) → **cell-based**
> competition binding. Pick the method per target from the tables below using whatever the lab
> already has; don't buy an instrument for this.

---

## 0. Method selection (by equipment on hand)

| Target | If you have… | Use | Readout | Output |
|---|---|---|---|---|
| αvβ6 | plate reader w/ **fluorescence polarization** | **FP competition** (primary) | mP / anisotropy | IC50 → Ki |
| αvβ6 | only **absorbance** plate reader | **solid-phase (ELISA-style) competition** | OD (TMB) | IC50 |
| αvβ6 | access to a **BLI/SPR** core | **BLI/SPR** (confirmation + kinetics) | kon/koff | Kd, ka, kd |
| GRPR | **flow cytometer** | **whole-cell competition**, fluorescent tracer | median fluor. | IC50 → Ki |
| GRPR | fluor. plate reader + adherent cells | **plate whole-cell competition** | fluor. | IC50 |
| GRPR | (orthogonal function check) | **IP-1 / Ca²⁺ flux** (Gq) | HTRF / Fluo-4 | agonist/antagonist |

Recommended first pass: **αvβ6 → FP competition**, **GRPR → whole-cell competition by flow**.
Both are homogeneous-ish, no radioactivity, and scale to a plate of macrocycles.

---

## 1. αvβ6 — FP competition (primary)

### Reagents
- Recombinant human integrin **αvβ6 ectodomain** (e.g., R&D Systems 3817-AV; or ACROBiosystems) —
  *verify catalog # and that it's the activatable ectodomain, not a single subunit.*
- **Fluorescent tracer:** a labeled αvβ6-selective ligand — **FITC- (or TAMRA-) A20FMDV2**
  (sequence `NAVPNLRGDLQVLAQKVART`, FMDV-VP1 derived, αvβ6-selective). Commission labeled from the
  same peptide vendor, or label in-house (NHS-ester on an added Lys/N-term).
- **Binding buffer:** 25 mM HEPES pH 7.4, 150 mM NaCl, **1 mM MnCl₂** (integrins need divalent
  cation to adopt the active conformation), 0.01% Tween-20, 0.1% BSA. (Mg²⁺/Ca²⁺ 1 mM each is an
  alternative to Mn²⁺.)
- 384-well **black, non-binding** plates.

### Step A — tracer Kd (do once)
Fix tracer at a low constant (e.g., 5–10 nM); titrate αvβ6 (2-fold, ~12 points, 0 → ~1 µM).
Incubate 60 min RT in the dark, read FP. Fit anisotropy vs [αvβ6] → tracer Kd with
`fit_direct_kd(protein_conc, anisotropy, tracer_conc=…)`. Use this Kd and the chosen [αvβ6]/[tracer]
in the IC50→Ki conversion.

### Step B — competition (per macrocycle, the throughput assay)
- Fix **tracer** (≈ its Kd) + **αvβ6** (≈ tracer Kd, so ~50–80% tracer bound at baseline).
- Titrate each **macrocycle competitor** 3-fold, ~10 points, 0 → ~100 µM.
- Incubate 60 min RT, dark; read FP.
- Fit with `fit_ic50(competitor_conc, anisotropy)` → IC50; convert → Ki with
  `ic50_to_ki(ic50, tracer_kd, tracer_conc, protein_conc)`.

### Controls (every plate)
- **Positive competitor:** unlabeled A20FMDV2 (should give a clean IC50 ≈ its known affinity).
- **Negative:** scrambled / unrelated peptide (flat curve).
- **Specificity:** +10 mM **EDTA** well — chelates cation, abolishes integrin binding → confirms
  signal is integrin-specific, not aggregation.
- **Tracer-only** (max mP) and **tracer + excess cold ligand** (min mP, nonspecific floor).
- Compute **Z′** from pos/neg; proceed only if Z′ > 0.5.

### No-FP-tracer fallback — solid-phase ELISA competition (absorbance only)
Coat plate with an αvβ6 ligand (e.g., LAP-TGFβ1 or an RGD-fibronectin fragment) → block → add
αvβ6 + titrated macrocycle → wash → detect captured αvβ6 (anti-αv or anti-β6–HRP) → TMB → read
A₄₅₀. Competition lowers signal; fit IC50 with `fit_ic50` on OD.

---

## 2. GRPR — whole-cell competition binding (primary)

GRPR is a GPCR; use cells, not purified protein.

### Reagents
- **Cells:** PC-3 (ATCC CRL-1435) endogenously express GRPR; or HEK293 stably transfected with
  human GRPR (plus a GRPR-null parental line as the specificity control).
- **Fluorescent tracer:** a labeled GRPR ligand — fluorescent **bombesin/GRP analog** or the
  antagonist **RM2/RM26** conjugated to Cy5/FITC (commission or source commercially; *confirm it
  retains GRPR affinity after labeling*).
- **Assay buffer:** HBSS + 25 mM HEPES pH 7.4, 0.1–1% BSA, protease inhibitors; keep **cold (4 °C)**
  to block receptor internalization during the assay.

### Procedure
- Harvest cells (non-enzymatic, e.g., EDTA dissociation; trypsin can clip surface receptors),
  ~1–2 ×10⁵ cells/well, keep on ice.
- Fix **tracer** near its Kd; titrate each **macrocycle** 3-fold, ~10 points, 0 → ~100 µM.
- Incubate 1–2 h at **4 °C**; wash 2–3× cold buffer to remove unbound tracer.
- Read **median tracer fluorescence by flow cytometry** (gate live single cells), or plate
  fluorescence for adherent format.
- Fit `fit_ic50` → IC50; `ic50_to_ki` → Ki (use tracer Kd from a parallel saturation titration).

### Controls
- **Positive competitor:** unlabeled bombesin or RM2 (clean IC50).
- **Negative:** scrambled peptide (flat).
- **Specificity:** GRPR-null parental line (tracer signal should drop to background) **and** a
  cold-bombesin excess well (nonspecific floor).
- **Orthogonal function (optional but strong):** GRPR is Gq-coupled → an **IP-1 (IP-One HTRF)** or
  **Ca²⁺ flux (Fluo-4)** assay tells you whether a binder is an **agonist vs antagonist** — useful
  biology the binding assay alone can't give.

---

## 3. Selectivity counter-screens (for confirmed hits)

Run the same competition format against the off-targets:
- **αvβ6 selectivity:** αvβ3, αvβ5, αvβ8, α5β1 (other RGD integrins). A good αvβ6 macrocycle should
  be ≥10–100× selective.
- **GRPR selectivity:** NMBR (BB1) and BRS-3 (BB3) — the other bombesin-receptor subtypes.

---

## 4. Plate layout for a batch of macrocycles

- 384-well: one 10-point titration per compound (+ duplicate) → ~17 compounds/plate with controls,
  or run singlicate at the screening stage and confirm hits in triplicate dose-response.
- Always co-plate the positive/negative/specificity controls on **every** plate (drift + Z′).
- Export raw values as CSV: `compound_id, replicate, conc_uM, signal` → the loop's ingest turns the
  fits into `AssayResult(FP_BINDING, value=Ki, unit="nM")`.

---

## 5. Data → model (closing the loop)

For each compound, the fit output feeds back:
- `Kd`/`Ki` (nM), fit `r²`, Hill slope, and a QC pass flag (Z′ ok, r² > 0.9, specificity controls
  behaved). The orchestrator stores these and the ranker re-prioritizes the next synthesis batch.
- Python: `from sdl.assays.fp_binding import fit_ic50, ic50_to_ki` — hand it the titration arrays.

---

## 6. Safety / notes

- No radioactivity in any route above (classic `[¹²⁵I]`-bombesin GRPR binding is avoided on purpose).
- BSL-1/2 cell culture (PC-3 / HEK) — standard.
- Integrin assays are **cation-sensitive**: keep Mn²⁺/Mg²⁺ consistent; a stray EDTA/phosphate carryover
  will kill αvβ6 signal (that's also why EDTA is the specificity control).
- Confirm every catalog number and that **labeled tracers retain affinity** (label can disrupt
  binding — run the saturation titration before trusting any competition IC50).

---

## 7. Open items to confirm before ordering reagents

- [ ] αvβ6 ectodomain source + lot (activatable form).
- [ ] FP tracer: label + position on A20FMDV2 that preserves αvβ6 affinity (titrate to confirm Kd).
- [ ] GRPR cell line choice (PC-3 vs transfected HEK + null control) and fluorescent GRPR tracer.
- [ ] Which reader/flow the lab has → fixes FP vs absorbance vs flow route (see §0).
