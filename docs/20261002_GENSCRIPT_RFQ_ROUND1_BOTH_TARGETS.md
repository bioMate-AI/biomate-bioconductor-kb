# GenScript RFQ — Round-1 Cyclic Peptides (PD-L1 + αvβ6): Synthesis → QC → Binding

> **INTERNAL REFERENCE ONLY — do NOT send this document to the CRO.** It is our checklist of what to
> ask for. The outward artifact is the short business email in `20261002_GENSCRIPT_OUTREACH_EMAIL.md`,
> with the **clean, score-free** attachments `results/CRO_SEND_pdl1_panelA.csv` + `CRO_SEND_avb6_panelB.csv`.
> The `*_CRO_order*.csv` files referenced below carry our internal design scores (ΔG/iPTM/etc.) and are
> **internal only** — never attach them. Send sequences only after confidentiality (NDA) is in place.

**Date:** 2026-10-02 · **Status:** internal spec; the send-ready email is the separate outreach doc.

**Contacts:** synthesis → peptide@genscript.com · binding/SPR → protein@genscript.com. Please quote both parts bundled, and the two panels together for a batch/library discount.

---

## 0. Summary of the request
We are placing a discovery-scale order for **22 head-to-tail cyclic (backbone-amide) peptides** across two targets, and request **synthesis + QC + affinity measurement (SPR/BLI)** with full raw-data return. All peptides are 8–16 residues, all-natural L-amino acids, no non-natural residues in this round. We want a bundled quote (synthesis → binding) and a timeline, including an expedited sub-set.

| Panel | Target | # peptides | Length range | Expedited (RUSH) |
|---|---|---|---|---|
| A | human **PD-L1** (CD274) | 10 | 12–16 | 6 |
| B | human **integrin αvβ6** (ITGAV/ITGB6) | 12 | 8–11 | 6 |

---

## PART A — Custom cyclic-peptide synthesis

**Cyclization (all peptides):** head-to-tail **backbone amide** (α-N of residue 1 to α-C of residue n). **No free N- or C-termini** — a pure backbone macrocycle. No disulfides, no side-chain staples in this round.

**Per-peptide spec:** ≥95% purity (RP-HPLC); **5 mg**; **acetate salt, TFA-free** (peptides go into SPR and cell assays — please perform TFA→acetate exchange, guaranteed <1% TFA); standard desalting.

**QC to return per peptide:** RP-HPLC chromatogram + purity %, ESI-MS (measured vs theoretical mass), **net peptide content** (AAA or nitrogen analysis — needed to set exact molar concentrations for SPR), and a CoA. Flag any sequence that fails or needs a non-standard synthesis route.

### Panel A — PD-L1 (10)
| ID | Sequence (N→C) | Len | RUSH |
|---|---|---|---|
| BMPDL1-R1-01 | GAYTSKSTGVTF | 12 | ✓ |
| BMPDL1-R1-02 | SSPFPVFKEFSP | 12 | ✓ |
| BMPDL1-R1-13 | SNGPAELEEAVGVKI | 15 | ✓ |
| BMPDL1-R1-11 | SAPEVLRPYSSNPK | 14 | ✓ |
| BMPDL1-R1-12 | AAPEVLRKYTSLP | 13 | ✓ |
| BMPDL1-R1-14 | SSNPAAKHIDPM | 12 | ✓ |
| BMPDL1-R1-05 | ARTPEDLEEAVRTGKP | 16 | |
| BMPDL1-R1-04 | GGYTSSATGVTF | 12 | |
| BMPDL1-R1-06 | LGVETSNPAIAELAKM | 16 | |
| BMPDL1-R1-10 | GGSGEGKKLAEELGLK | 16 | |

### Panel B — αvβ6 (12)
| ID | Sequence (N→C) | Len | RUSH |
|---|---|---|---|
| BMAVB6-R1-01 | GRGRNKYYP | 9 | ✓ |
| BMAVB6-R1-02 | NKYRSRRGK | 9 | ✓ |
| BMAVB6-R1-03 | GSLASLGIGRR | 11 | ✓ |
| BMAVB6-R1-04 | ARRGNLAPLG | 10 | ✓ |
| BMAVB6-R1-05 | KGLRGRSG | 8 | ✓ |
| BMAVB6-R1-06 | GLFGGRGRR | 9 | ✓ |
| BMAVB6-R1-07 | RGKLMPGRG | 9 | |
| BMAVB6-R1-08 | GTGTGSLGRLR | 11 | |
| BMAVB6-R1-09 | SSRSSLGHLLG | 11 | |
| BMAVB6-R1-10 | SRKGIVKGP | 9 | |
| BMAVB6-R1-11 | GTGIGSLGKLL | 11 | |
| BMAVB6-R1-12 | APRGALASLG | 10 | |

---

## PART B — Affinity measurement (SPR/BLI)

For **each** synthesized peptide, measure binding to the cognate target:
- **Panel A** → human **PD-L1** extracellular domain (SPR-grade). Please quote supplying the protein; we can also supply it.
- **Panel B** → human **integrin αvβ6** ectodomain (SPR-grade). Please quote supplying the protein; we can also supply it. Note αvβ6 is divalent-cation (Mn²⁺/Ca²⁺) dependent — please run binding in a Mn²⁺/Ca²⁺-containing running buffer appropriate for integrin–ligand interactions.

**Deliver per peptide:** ka (kon), kd (koff), **KD**, affinity ranking, Chi² (fit quality), and **sensorgrams** (exportable raw data, not just images). Instrument: **Biacore 8K+** preferred (Octet BLI acceptable). **Report every peptide including non-binders** — a peptide that shows no binding is a result we need; report it as a non-binder with its curves, do not omit it.

**Optional add-ons (please quote separately):**
- Panel A: PD-1/PD-L1 **competition assay** (ELISA or HTRF) on any binders → % blockade / IC50.
- Panel B: αvβ6 vs **αvβ3 / αvβ8 counter-screen** on any binders → selectivity ranking.

---

## PART C — Data-return format
One results package per panel: a table (ID · final purity % · measured mass · net peptide content · solubility · KD · ka · kd · Chi²) **plus** raw traces (HPLC chromatograms, MS spectra, SPR sensorgrams as exportable data). We use **every** outcome — binders and non-binders, synthesis successes and failures — as data, so the complete set matters more than the hits.

---

## PART D — Commercials / logistics (please quote)
1. Price + lead time **per panel** and **both panels bundled**, synthesis only.
2. Price + lead time **Part A + B bundled** (synthesis → SPR), per panel and combined.
3. **Expedited** tier for the 12 RUSH peptides (6 per panel) — cost + timeline delta.
4. **Batch/library discount** for ordering all 22 together.
5. Shipping terms and required paperwork.

---

## PART E — Ongoing relationship (optional, for discussion)
This is the first of a recurring series of discovery rounds — we expect a steady cadence of cyclic-peptide synthesis + affinity screening batches. We would like to understand GenScript's options for a **framework / preferred-pricing arrangement** at that volume (and any startup/accelerator credit programs), under terms where **the ordering party retains all IP and the work is covered by confidentiality**. A quote for this round is the priority; the framework conversation can follow once Round-1 quality and turnaround are established.
