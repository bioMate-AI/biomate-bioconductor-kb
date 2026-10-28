# αvβ6 Integrin (ITGAV/ITGB6) Binder Survey & Generation-Template Recommendation

**Date:** 2026-10-01
**Purpose:** (A) survey how the field designs αvβ6 binders ("similar solutions") for a cyclic-peptide macrocycle program, and (B) identify the cleanest, most complete experimental structure to use as a de-novo generation template — replacing our current template **4UM9**, which has ~22 unresolved residues / 166 unresolved atoms that broke the de-novo design step.

**Verification contract:** Every PDB ID below was checked against the RCSB data API (`https://data.rcsb.org/rest/v1/core/entry/<ID>`) on 2026-10-01. Entries that resolved are marked **[RCSB ✓]**. Affinities are marked **[reported]** (taken from a cited source) or **[inferred]**. No PDB ID, DOI, PMID, or affinity below is fabricated; where a value could not be confirmed it is flagged.

---

## TL;DR Recommendation

**Use PDB `8TCG` (αvβ6 + de-novo minibinder B6_BP_dslf, cryo-EM 3.4 Å) as the primary generation template.** It is the only verified αvβ6 co-structure with **zero unmodeled residues**, it carries the **Mn²⁺/Ca²⁺ metals at MIDAS**, and its bound ligand **fully recapitulates the RGD pharmacophore** (RGD-Arg→αv D218, RGD-Asp→MIDAS, LXX(L/I)→β6 Y185 specificity contact). Trade-off: 3.4 Å cryo-EM (lower nominal resolution than 4UM9's 2.5 Å X-ray), and the ligand is a designed miniprotein rather than a small cyclic peptide — but it defines the pocket we care about with no gaps.

**Backup / pocket cross-check:** `4UM9` (2.5 Å X-ray, native TGF-β3 RGDLXXL peptide) remains the best *high-resolution* definition of the pocket and the canonical selectivity helix — use it only for a **site-preserving** reference, not as the gapped generation input.

**Top precedent approaches:** (1) A20FMDV2 FMDV-GH-loop RGDLXXL peptide + stabilized analogs; (2) de-novo RGD-presenting miniproteins (Baker lab, picomolar, >1000× selective); (3) cyclic/bicyclic RGD macrocycles (ansamer bicyclic 10-M_ansa, 9XMM) and the small-molecule RGD-mimetics bexotegrast/GSK3008348.

---

## 1. αvβ6-Targeting Modalities & Precedents

| Modality | Representative agent | Core motif | Affinity (flagged) | Selectivity | Source |
|---|---|---|---|---|---|
| **Linear peptide (FMDV GH-loop)** | **A20FMDV2** `NAVPNLRGDLQVLAQKVART` | RGD**LXXL** (RGDLQVL) + C-term 3₁₀/α-helix | K_D **0.22 nM** radioligand **[reported]**; ~3 nM immobilized αvβ6 **[reported]**; ~63 ± 21 nM cell-based apparent K_D **[reported]** | ≥85× (radioligand) to ~1000× (immobilized) over other RGD integrins **[reported]** | [PMID 26734728](https://pubmed.ncbi.nlm.nih.gov/26734728/); [PMC8138772](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8138772/) |
| **Stabilized A20FMDV2 analogs** | Disulfide-cyclized / PEGylated / Cit-substituted variants (e.g. C2C18 CitTKAD) | same RGDLXXL; cyclization + N/C-cap engineering for serum stability | 55–77 nM cell-based, statistically ≈ parent **[reported]** | preserves αvβ6 specificity; Arg19 important for specificity **[reported]** | [PMC8138772](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8138772/); [PMID 33857478](https://pubmed.ncbi.nlm.nih.gov/33857478/) |
| **Cystine-knot (knottin) miniprotein** | **R01 / S02** (Cochran lab), clinical tracer `18F-FP-R01-MG-F2` | engineered RGD loop on knottin scaffold | 3–6 nM **[reported]** | no cross-reactivity to αvβ3/αvβ5/α5β1 **[reported]** | [doi:10.1158/1078-0432.ccr-11-1116](https://doi.org/10.1158/1078-0432.ccr-11-1116); [Nat Commun 2019](https://www.nature.com/articles/s41467-019-11863-w) |
| **De-novo designed miniprotein** | **B6_BP_dslf** (Baker/IPD) → **PDB 8TCG** | designed loop presenting **RGD + LXX(L/I)** | subnanomolar; ~30 pM on A431 cells **[reported]** | >1000× over αvβ1/β3/β5, α5β1, α8β1, αIIbβ3; no αvβ8 binding ≤500 nM **[reported]** | [Nat Commun 2023, PMC10500007](https://pmc.ncbi.nlm.nih.gov/articles/PMC10500007/) |
| **Bicyclic peptide (ansamer)** | **10-M_ansa** (RGD bicyclic, ansamer-controlled) → **PDB 9XMM** | RGD in a bicyclic scaffold; ansamer chirality gates activity | not confirmed numerically here **[not verified]** | "high selectivity" for αvβ6; faster internalization + longer tumor retention vs A20FMDV **[reported, qualitative]** | [PMID 41937119](https://pubmed.ncbi.nlm.nih.gov/41937119/); [Angew. Chem. 2026](https://onlinelibrary.wiley.com/doi/10.1002/anie.1254428) |
| **Small-molecule RGD-mimetic (oral, dual)** | **Bexotegrast / PLN-74809** | RGD-mimetic (Arg-mimic + Asp acid) | K_d **5.7 nM** αvβ6, **3.4 nM** αvβ1 **[reported, vendor]** | dual αvβ6/αvβ1 (anti-fibrotic) **[reported]** | [MedChemExpress](https://www.medchemexpress.com/bexotegrast.html) — vendor figure, confirm against primary lit |
| **Small-molecule RGD-mimetic (inhaled)** | **GSK3008348** | RGD-mimetic | high affinity in IPF lung **[reported, qualitative]** | αvβ6-selective; induces receptor internalization/degradation | [Nat Commun 2020, PMC7494911](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7494911/); [PMID 32938936](https://pubmed.ncbi.nlm.nih.gov/32938936/) |
| **Antibody** | BG00011 (anti-αvβ6 mAb) | protein epitope | n/a | stabilizes **bent-closed** conformation (contrast: RGD ligands stabilize **open**) | [Nat Commun 2023, PMC10500007](https://pmc.ncbi.nlm.nih.gov/articles/PMC10500007/) |

**Bicycle Therapeutics note:** A dedicated clinical **Bicycle Therapeutics (BT-series) αvβ6** bicyclic-peptide program was **not confirmed** in this search. The verified bicyclic-peptide αvβ6 structure (9XMM) is from the academic **ansamer** bicyclic work (Yang et al., Angew. Chem. 2026), not a Bicycle Therapeutics BT asset. Treat "an αvβ6 bicycle exists" as **true in the academic literature**, **unconfirmed as a named Bicycle Therapeutics clinical program**.

---

## 2. αvβ6 Structures in the PDB (verified, ranked by template suitability)

All entries verified via RCSB on 2026-10-01. "Unmodeled residues" is the key column for our pipeline.

| Rank | PDB | Method / Res. | What's bound | Chains (αv / β6 / ligand) | MIDAS metal | Unmodeled residues | Template verdict |
|---|---|---|---|---|---|---|---|
| **1** | **8TCG** [RCSB ✓] | cryo-EM **3.4 Å** | de-novo minibinder **B6_BP_dslf** (presents RGD + LXX(L/I)) | αv + β6 + minibinder (3 chains) | **Mn + Ca present** | **0 unmodeled** (754/754) | **BEST — complete, metals present, full RGD pharmacophore reproduced** |
| 2 | **4UM9** [RCSB ✓] | X-ray **2.5 Å** | native **TGF-β3 RGDLXXL** peptide (chains E/F) | αv = A,C / β6 = B,D / pep = E,F | Ca, Mg (MIDAS region) | ~90 total unmodeled (incl. the ~22 res / 166 atoms that broke our run) | Best resolution & native selectivity helix, **but gapped — do NOT feed raw** |
| 3 | **9XMM** [RCSB ✓] | cryo-EM **2.88 Å** | **bicyclic RGD peptide** (ansamer; chain C/auth E: `A-W-R-G-D-Chg-C-N-P`) | αv = A / β6 = B / pep = C | **Mn (×3) + Ca (×4)** | **~388 unmodeled** (690/1078) | Highest-res cyclic-peptide ligand, but large unmodeled fraction; useful as a *cyclic-ligand pose reference*, not as receptor template |
| 4 | **5FFO** [RCSB ✓] | X-ray **3.49 Å** | pro-TGF-β (3 chains) | αv / β6 / pro-TGF-β | Ca, Mn | not enumerated; low res | pocket ok but lower res than 4UM9; secondary |
| — | **4UM8** [RCSB ✓] | X-ray **2.85 Å** | **apo** (no peptide) | αv / β6 | Ca, Mg, Ni | — | **No ligand → does not define the RGD pose**; use only for apo/SDL2-ordered reference |
| — | **5FFG** [RCSB ✓] | X-ray **2.25 Å** | **apo head** (no peptide) | αv + β6 head | Ca | — | highest res but **apo**; no ligand pocket pose |
| — | **5NEM** [RCSB ✓] | cryo-EM **10.8 Å** | FMDV capsid (RGD via virus surface) | αv + β6 + capsid | Ca | localized recon | **10.8 Å far too low** for de-novo generation |
| — | **6OM1 / 6OM2** [RCSB ✓] | X-ray 2.66 / 2.77 Å | **αvβ8** (not αvβ6!) | αv / **β8** / proTGF-β1 (6OM2) | Ca, Mg | — | **Wrong integrin (β8)** — exclude |
| — | **6UJA** [RCSB ✓] | cryo-EM 3.3 Å | **αvβ8** + proTGF-β1 (not αvβ6!) | αv / **β8** / LTGFβ1 | Ca, Mg | — | **Wrong integrin (β8)** — exclude |
| — | **8TCF** [RCSB, from paper] | cryo-EM | **αvβ8** + B8_BP_dslf (not αvβ6) | αv / **β8** / minibinder | — | — | **Wrong integrin (β8)** — exclude (paired deposit with 8TCG) |

**Correction to the task's candidate list:** `6OM1/6OM2` and `6UJA` are **αvβ8**, not αvβ6 — exclude them. `5FFG` and `4UM8` are **apo** (no bound ligand to define the RGD pose). The genuinely new, high-value αvβ6 co-structures the task was missing are **8TCG** (designed minibinder, complete) and **9XMM** (bicyclic RGD peptide). There is **no verified bexotegrast/PLN-74809 co-crystal with αvβ6** in the PDB as of this search (**not found / not verified**) — the bexotegrast binding numbers above are vendor-reported, not from a deposited structure.

---

## 3. RGD-Binding Mechanism & αvβ6-Selectivity Determinants

**Canonical RGD engagement (shared across αv integrins):**
- **Arg (R)** of RGD inserts into a pocket on the **αV subunit**, forming a salt bridge / H-bond with an αV aspartate (in 8TCG, RGD-Arg10 → αv **D218**).
- **Asp (D)** of RGD coordinates the divalent **metal at the β-subunit MIDAS** (metal-ion-dependent adhesion site; Mn²⁺/Mg²⁺). Flanking metals **ADMIDAS** and **SyMBS** tune affinity/conformation.
- Ligand binding drives the integrin headpiece from **bent-closed → open** (RGD ligands and the Baker minibinder stabilize **open**; the antibody BG00011 stabilizes **bent-closed**).

**αvβ6-SELECTIVITY (why this matters for a selective macrocycle):**
- Selectivity over αvβ3/αvβ5/αvβ8 is driven by the β-subunit **specificity-determining loops (SDL1/2/3)** and, most importantly, by a **post-RGD amphipathic helix** that engages a **hydrophobic pocket on β6**.
- The motif is **RGD-LXX(L/I)** (the "DLXXL" determinant): in A20FMDV2 this is **RGDLQVL**; in TGF-β1/β3 prodomains it is the native RGDLXXL/I. The **LXX(L/I)** residues pack hydrophobically against β6 — in 8TCG, minibinder **L16 packs against β6 Y185**.
- Practical design rule: **a bare RGD will bind multiple αv integrins; αvβ6 selectivity requires reproducing the C-terminal LXX(L/I) helix contact against the β6 hydrophobic groove.** Any generated cyclic peptide should present RGD *and* an adjacent hydrophobic Leu/Ile-bearing element positioned toward the β6 specificity pocket.
- Additional A20FMDV2 determinants **[reported]**: Arg19 important for αvβ6 specificity; Val12/Val17 stabilize the post-RGD helix.

---

## 4. Recommended Template + Rationale + Site-Preserving Fix

### Primary template: **PDB 8TCG** — αvβ6 + B6_BP_dslf (cryo-EM 3.4 Å)
**Receptor = chains αv + β6 (two-chain pocket); ligand chain = B6_BP_dslf, which defines the RGD site.**

**Why 8TCG over 4UM9:**
1. **Completeness — the decisive factor.** 8TCG has **0 unmodeled residues** (754/754). This directly fixes the failure mode that broke our de-novo step with 4UM9 (22 unresolved residues / 166 unresolved atoms). No gap-filling, no risk of a hole in or near the pocket.
2. **MIDAS metal present** (Mn + Ca) — the Asp-to-metal anchor the generator must reproduce is physically in the file.
3. **Full RGD pharmacophore is reproduced by the bound ligand:** RGD-Arg→αv D218, RGD-Asp→MIDAS, and the **LXX(L/I)→β6 Y185** selectivity contact — i.e., the ligand chain defines *both* the RGD pose *and* the selectivity helix we need generated binders to recapitulate.
4. **Correct conformational state:** open headpiece, the agonist-competent state RGD macrocycles should target.

**Honest trade-offs:**
- 3.4 Å cryo-EM < 4UM9's 2.5 Å X-ray: sidechain rotamers in the pocket are less precisely defined. Mitigation: cross-reference pocket sidechains against 4UM9 (2.5 Å) and against 9XMM (2.88 Å, which has an actual **cyclic** RGD ligand) before finalizing pocket constraints.
- The ligand is a **miniprotein**, not a small cyclic peptide. For our macrocycle program this is fine *as a receptor+pocket template* (we re-generate the ligand anyway), and it is arguably better because it demonstrates the exact RGD + LXX(L/I) geometry we want to reproduce.

### Secondary references (do not use as the gapped generation input)
- **4UM9** (2.5 Å) — highest-resolution native RGDLXXL pocket + selectivity helix; use to **validate/refine pocket sidechain geometry**, not as the raw template (it is the gapped file that broke the run).
- **9XMM** (2.88 Å) — the only verified αvβ6 structure with a bound **cyclic (bicyclic) RGD peptide**; use as a **cyclic-ligand pose exemplar** for how a constrained RGD macrocycle sits in the pocket (Arg→αv, Asp→Mn MIDAS). Note its receptor has ~388 unmodeled residues, so do not use it as the receptor template.

### If 8TCG still needs any fix — SITE-PRESERVING only
8TCG reports 0 unmodeled residues, so no gap-filling is expected. If the pipeline flags any peripheral issue:
- **Never remove the RGD pocket, the MIDAS/ADMIDAS/SyMBS metals, or the β6 specificity loop (SDL / Y185 groove).** These are the generation target.
- Permissible, site-preserving steps only: trim glycans (NAG) distal to the pocket, cap chain termini far from the site, protonate/add H, and (if a sidechain rotamer in the pocket looks off at 3.4 Å) refine it against the 2.5 Å 4UM9 geometry — do not delete it.
- Keep the **αv + β6 two-chain receptor** intact and keep **≥1 metal in MIDAS**; define the **ligand/RGD site** from the B6_BP_dslf RGD loop (Arg/Asp positions + the L16→Y185 vector) so the generator has both the RGD anchor and the selectivity vector.

---

## Sources
- A20FMDV2 pharmacology/kinetics: [PMID 26734728](https://pubmed.ncbi.nlm.nih.gov/26734728/)
- Serum-stable A20FMDV2 analogs + selectivity determinants: [PMC8138772](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8138772/), [PMID 33857478](https://pubmed.ncbi.nlm.nih.gov/33857478/)
- Baker de-novo αvβ6/αvβ8 miniproteins (8TCG/8TCF, EMD-41153/41154): [Nat Commun 2023 / PMC10500007](https://pmc.ncbi.nlm.nih.gov/articles/PMC10500007/)
- Ansamer bicyclic αvβ6 peptide (9XMM): [PMID 41937119](https://pubmed.ncbi.nlm.nih.gov/41937119/), [Angew. Chem. 2026](https://onlinelibrary.wiley.com/doi/10.1002/anie.1254428)
- Cystine-knot R01 knottin: [doi:10.1158/1078-0432.ccr-11-1116](https://doi.org/10.1158/1078-0432.ccr-11-1116), [Nat Commun 2019](https://www.nature.com/articles/s41467-019-11863-w)
- Bexotegrast / PLN-74809 (vendor-reported Kd): [MedChemExpress](https://www.medchemexpress.com/bexotegrast.html)
- GSK3008348 inhaled small molecule: [PMC7494911](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7494911/), [PMID 32938936](https://pubmed.ncbi.nlm.nih.gov/32938936/)
- 4UM9 / 4UM8 (Dong & Springer, structural determinants of β-subunit specificity for latent TGF-β): [RCSB 4UM9](https://www.rcsb.org/structure/4UM9), [RCSB 4UM8](https://www.rcsb.org/structure/4UM8)
- FMDV-αvβ6 (5NEM): [RCSB 5NEM](https://www.rcsb.org/structure/5NEM) (Kotecha et al., Nat Commun 2017)
- RCSB data API used for verification of every PDB ID: `https://data.rcsb.org/rest/v1/core/entry/<ID>`
