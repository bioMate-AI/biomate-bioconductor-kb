# Pre-registration — αvβ6 metal-aware FEP benchmark against the gold standard (2026-10-24)

**Purpose.** Demonstrate capability *without wet lab* by showing our physics pipeline (CaDA-Mn relative
FEP; control edge already validated, `docs/20261022_CYCLIC_LLM_CLOSED_CYCLE_CONTROLS.md` §6c) **reproduces
the measured gold standard** for αvβ6 — affinity ranking and αvβ6-vs-αvβ3 selectivity — then score novel,
FTO-clear candidates through the same validated pipeline. Written **before** running any benchmark edge.

**Why this is the honest contribution path (and not renal):** renal is engineerable and field-owned (no
gap). The genuinely hard, under-done problem is **metal-coordinated (MIDAS) relative-FEP for integrin
affinity + selectivity**. If our CaDA-Mn FEP recovers the gold standard, that is a real, publishable methods
capability, validated retrospectively against measured data.

## Gold-standard set (from the verified survey `docs/20261001_AVB6_BINDER_SURVEY_AND_TEMPLATE.md`)
| Compound | Measured affinity | Selectivity (measured) | Structure (MIDAS metal) | Source |
|---|---|---|---|---|
| A20FMDV2 `NAVPNLRGDLQVLAQKVART` | K_D 0.22 nM (radioligand); ~3 nM immobilized; ~63 nM cell | ≥85×–~1000× over αvβ3/αvβ5/α5β1 | — (seq; dock into 4UM9/8TCG) | PMID 26734728; PMC8138772 |
| Stabilized A20FMDV2 analogs (Cit/cyclized; Arg19, Val12/17 determinants) | 55–77 nM cell (congeneric series) | αvβ6-selective preserved | — | PMC8138772; PMID 33857478 |
| Knottin R01 | 3–6 nM | no αvβ3/αvβ5/α5β1 | — | CCR 2011; NatComm 2019 |
| B6_BP_dslf (de novo) | ~30 pM (A431) | >1000× over αvβ1/3/5, α5β1, αIIbβ3; no αvβ8 | **PDB 8TCG, cryo-EM 3.4 Å, Mn+Ca, 0 unmodeled** | PMC10500007 |
| ansamer bicyclic 10-M_ansa | not numeric (qualitative) | high (qual) | **PDB 9XMM, 2.88 Å, Mn×3+Ca×4** | PMID 41937119 |
| native TGF-β3 RGDLXXL | — | — | **PDB 4UM9, X-ray 2.5 Å** | Dong & Springer |

**Receptor side is gold-standard-ready** (usually the hard part): complete αvβ6 co-structures with MIDAS
metals exist — 8TCG (complete, Mn+Ca), 4UM9 (2.5 Å native RGDLXXL), 9XMM (bound *cyclic* RGD, Mn×3).

## FEP edge design, tiered by ground-truth availability (pre-committed)
- **Tier A — quantitative ΔΔG (primary).** Congeneric point-variant edges on a measured series (candidate:
  the A20FMDV2 Ala/Cit/Arg19 analog set, PMC8138772 / PMID 33857478), run as relative FEP on an αvβ6
  co-structure (4UM9 / 8TCG) with CaDA-Mn. **Metric: FEP ΔΔG vs measured ΔΔG, RMSE (target ≈1–1.5 kcal/mol,
  the field FEP bar) + rank correlation.** *Gating dependency:* a clean per-variant measured affinity table
  must be extracted and locked first (one verification step; see Blocker).
- **Tier B — selectivity sign (independent, lower-data).** For A20FMDV2 (known ≥85× αvβ6 over αvβ3), compute
  ΔΔG_selectivity = ΔG(αvβ6) − ΔG(αvβ3) and test it recovers the known **sign/direction** (αvβ3 built from a
  standard αvβ3-RGD structure). Qualitative ground truth, still decisive for the selectivity claim.
- **Novel-candidate arm.** Score FTO-clear generated candidates through the *same* validated pipeline →
  propose novel αvβ6-selective candidates meeting the validated bar.

## Circularity / exclusion controls
- Our **rule gates** (acceptance_gate, liability) were written from A20FMDV2/Trivehexin SAR → "recovering"
  these with the rules is circular and is **excluded** from any capability claim. **FEP is physics, not fit
  to these compounds**, so FEP benchmarking on them is non-circular and valid.
- Any compound used in any ML/fit step is held out. Measured ground-truth values are locked before scoring.

## Pre-committed decision rule
- **PASS (capability demonstrated):** CaDA-Mn FEP reproduces the Tier-A congeneric ΔΔG within ≈1–1.5
  kcal/mol RMSE **and** recovers the Tier-B αvβ6/αvβ3 selectivity sign → publishable methods result
  ("metal-aware FEP recovers αvβ6 affinity + selectivity vs the gold standard"), + the novel-candidate arm.
- **FAIL / partial:** report straight; if the metal model is the cause, fix it (constrain M–D / vsite CaDA)
  and re-run — do not relabel. If no clean Tier-A measured series exists, scope the claim to Tier-B
  (selectivity sign) and say so.

## Blockers (must clear before GPU spend)
1. **Ground-truth extraction (Tier A):** lock a per-variant measured-affinity table from PMC8138772 /
   PMID 33857478 (or an equivalent congeneric αvβ6 series). If none is clean enough for ΔΔG edges, Tier A is
   not anchorable and the benchmark is Tier-B-only — decide before spending.
2. **FEP tractability:** A20FMDV2 is a 20-mer — larger/more flexible than the 9-mer control edge; confirm
   per-edge cost on spot and prefer the smallest congeneric edges (single-residue) for convergence.
3. **Compute:** GPU spot only (validated fan-out pipeline `fep_production.py`); no on-demand.
4. **Environment:** local disk was at 100% on 2026-10-24, which blocked runs — must be cleared.
