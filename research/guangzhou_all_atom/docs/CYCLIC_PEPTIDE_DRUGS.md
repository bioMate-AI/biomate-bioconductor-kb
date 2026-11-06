# Approved cyclic-peptide drugs — master reference + discovery-method analysis

Compiled from 4 parallel cited surveys (anti-infectives, antifungals/antivirals, hormones/neuropeptides,
oncology/immuno/recent) plus a dedicated antibacterial deep-dive, reconciled against enumerative reviews
(Zorzi/Deyle/Heinis 2017; Zhang & Chen, *RSC Chem Biol* 2022; Muttenthaler et al., *Nat Rev Drug Discov*
2021). Structured data: `data/approved_cyclic_peptide_drugs.csv` (54 entries incl. regional/veterinary).
The dedicated antibacterial survey independently reproduced the discovery-method split (~67% natural-product
isolation, ~33% semisynthetic, 0% de-novo for that class), corroborating the analysis below. This is the **positive-control set** the transfer
survey called for — designs/predictors should rank these highly, and their chemistry is what we should generate.

Scope: genuinely cyclic/macrocyclic peptides & depsipeptides (head-to-tail lactam, side-chain lactam,
disulfide rings, cystine knots, depsipeptide lactones, macrocyclic lipopeptides, cross-linked glycopeptides).
Excluded (linear or non-peptide): enfuvirtide, bulevirtide, icatibant, etelcalcetide, difelikefalin,
afamelanotide, leuprolide/goserelin, insulin/GLP-1, angiotensin II, bivalirudin; tacrolimus/sirolimus/
everolimus (macrolides, not peptides). Borderline flagged in the CSV (glycopeptides, streptogramins, salmon
calcitonin's single loop).

## Discovery-method breakdown (47 entries) — the strategically important read

| Discovery method | # | Examples |
|---|---|---|
| **Natural-product isolation / fermentation** | 17 | ciclosporin, romidepsin, dactinomycin, daptomycin, vancomycin/teicoplanin, polymyxins, bacitracin, gramicidin S, tuberactinomycins |
| **Rational / analog design** | 17 | octreotide, lanreotide, pasireotide, desmopressin, terlipressin, atosiban, linaclotide, plecanatide, setmelanotide, bremelanotide, rusfertide |
| **Semisynthetic (from a natural product)** | 9 | echinocandins (caspo/mica/anidula/rezafungin), lipoglycopeptides (telavancin/dalbavancin/oritavancin), voclosporin |
| **Venom-derived** | 2 | ziconotide (cone-snail ω-conotoxin, direct), eptifibatide (snake-disintegrin KGD motif → designed) |
| **mRNA display** | 1 | **zilucoplan (2023) — the first display-derived approved cyclic peptide** |
| **Phage-display lineage** | 1 | pegcetacoplan (compstatin phage-display ancestry, then heavily re-engineered — not a marketed selected clone) |

**Note on the boundary:** "rational/analog design" and "semisynthetic" overlap heavily for the hormone analogs
(they modify an endogenous or natural scaffold). Grouping those with natural-product origins: **~55% of approved
cyclic peptides come from Nature (isolation or semisynthesis of a natural product), ~36% from rational analog
design of a known (usually endogenous) scaffold, and only ~4% from venom or display.**

## The three findings that matter for our program

1. **Essentially ZERO approved cyclic peptides came from de-novo *computational* design.** Every drug on the
   market traces to (a) Nature doing the scaffold discovery (fermentation/venom/endogenous hormone) or (b)
   medicinal-chemistry analoging of such a scaffold. This is simultaneously the **whitespace** for a
   generate-verify-learn engine and a **humbling bar**: the hard part (finding a bindable macrocyclic scaffold)
   was historically solved by evolution, not by design.

2. **Display technology has *just* cracked the market (2021–2023).** Zilucoplan (mRNA display, 2023) is the first
   display-derived approval; pegcetacoplan (2021) carries phage-display ancestry. This is the closest precedent to
   a "designed/selected-from-a-library" cyclic peptide reaching patients — and it is very recent, which is
   encouraging for a computational/library-adjacent approach and validates the direction rather than the
   architecture.

3. **The approved corpus is dominated by exactly the chemistry we flagged as our levers.** N-methylation
   (ciclosporin — the archetypal *orally bioavailable* macrocycle), D-amino acids and disulfide/lactam/carba
   bridges (octreotide, desmopressin, bremelanotide, atosiban), head-to-tail cyclization (ciclosporin, pasireotide,
   gramicidin S), and truncation-to-pharmacophore + re-cyclization (the somatostatin analogs). These confer the
   protease resistance, permeability, and selectivity that make a peptide a drug — so generating *and scoring* for
   this chemistry is directly validated by what actually got approved.

## Recent approvals to watch (≥2018)
Lu-177-dotatate (2018), bremelanotide (2019), setmelanotide (2020), voclosporin (2021), pegcetacoplan (2021),
terlipressin/Terlivaz (2022), motixafortide (2023), zilucoplan (2023), rezafungin (2023), rusfertide (2026).
Clinical-stage display-derived to watch: Bicycle Therapeutics' bicyclic BTCs (zelenectide pevedotin, Ph2/3),
PeptiDream RaPID mRNA-display programs (Ph1), Merck's oral macrocyclic PCSK9 peptide enlicitide (Ph3).

## Use in our pipeline
- **Positive controls** for the permeability/stability/binding predictors and the physics oracle (they must rank
  these known drugs highly; ciclosporin is the canonical permeable-macrocycle control).
- **Chemistry priors** for generation (N-methylation, D-AAs, bridge types) and the monomer alphabet.
- **Target/indication precedent** — the categories where cyclic peptides win (proteases, GPCRs/receptor families,
  complement, PPIs) inform target selection.
