# Display/Selection NGS for Cyclic Peptides — Accession Inventory, Feasibility, and One Harvested Dataset

**Date:** 2026-10-05 · **Author:** research session (Yaoyun Zhang / BioMate)
**Context:** the primary-signal data dependency for the inverted-data-dependency cyclic LLM
(`docs/20261005_INNOVATION_THESIS_CYCLIC_LLM.md` thesis; `docs/20261004_CYCLIC_PEPTIDE_DATA_WALL_STRATEGY.md`
Step 1 "free-but-heterogeneous SRA harvest"). The thesis asserts display/selection data is the way to
break the structural data wall — abundant, enrichment-labeled, and natively ncAA/N-methyl
(mRNA-display/RaPID). This note turns that assertion into a concrete, verified inventory + one real
harvested+processed dataset + a reusable processing path.

**TL;DR.** Round-over-round cyclic-peptide display NGS **does exist publicly in SRA/ENA**, but it is
**per-study, not a corpus**: each campaign has a bespoke amplicon design (anchors, codon scheme,
round/arm labels) that must be reverse-engineered from the deposit's design description. There is **no
index and no uniform schema** — harvest is per-study engineering, exactly as the strategy doc warned.
We verified ≥3 clean cyclic campaigns (2 RaPID mRNA-display + 1 SICLOPPS/PACE), harvested one end-to-end,
and extracted a **370,806-peptide enrichment-labeled table with a textbook selection-convergence signal**.
**Crucially, zero public cyclic-display NGS exists for OUR targets (PD-L1, αvβ6/integrins)** — confirming
the moat thesis: a proprietary campaign is required for target-specific binding data.

---

## 1. Accession inventory (verified via NCBI E-utilities + ENA Portal API, 2026-10-05)

All counts/sizes pulled programmatically from `eutils.ncbi.nlm.nih.gov` (esearch/efetch runinfo) and
`ebi.ac.uk/ena/portal/api/filereport`. Read structures taken from each deposit's `DESIGN_DESCRIPTION`.

| Accession (BioProject / SRA study) | Target | Display type | Rounds / arms | Runs | Total size (ENA fastq) | Total reads | ncAA / chemistry | Round labels? | License |
|---|---|---|---|---|---|---|---|---|---|
| **PRJNA1188087 / SRP546185** *(HARVESTED)* | human **PADI4** | **mRNA-display (RaPID), covalent** | 6 rounds × 3 arms (WT-1h, WT-15min, C645A-control) | 16 | **3,120 MB** | 121.3 M | **YES** — ClAc electrophilic-warhead initiator (reprogrammed AUG); thioether macrocycle; RaPID supports N-methyl/ncAA | **YES** — `Round{1..6}_PADI4_{1h,15min,C645A}` | SRA public / open |
| **PRJNA1406026** | multiple (P1_PhoL, P6_N3F, …) | **mRNA-display (XL RaPID), single-round** | input / output / purified-input **pairs**, replicates | 54 | **513 MB** | 23.8 M | **YES** — internal Met→photo-reactive AA reprogramming | **YES** — `P{n}_{tgt}_{input,output}_rep{k}` (enrichment = output/input directly) | SRA public / open |
| **PRJNA1170358 / SRP537232** | Aβ42, hIAPP (anti-aggregation) | **SICLOPPS cyclic peptide + PACE** (M13 phage, continuous evolution) | 8 continuous-selection samples (incl. negative selection) | 8 | 0 MB in ENA (SRA-only; NovaSeq) | 59.7 M | **NO** — head-to-tail cyclization via split intein → **canonical L-AAs only** | partial (sample-level, not discrete panning rounds) | SRA public / open |
| SRA free-text `"RaPID selection peptide"` | mixed | mRNA-display / RaPID | — | **103 runs total** | mixed (many 3–30 MB) | — | mixed | mixed | SRA public / open |

**Honest scoping notes on the table.**
- The `"RaPID selection peptide"` free-text search returns **103 runs** — the realistic ceiling of the
  *clean, discoverable* RaPID NGS pool in SRA today (many are the campaigns above + a long tail of
  single-arm deposits). Free-text searches for `"PD-L1 phage display"`, `"integrin phage display cyclic"`,
  `"bicyclic peptide phage display"`, `"cyclic peptide phage display panning NGS"` each returned **0** —
  phage-display cyclic-panning NGS is **largely NOT deposited** (phage campaigns usually report only the
  final hit sequences in the paper, not round-over-round reads).
- PRJNA1170358 fastq is **not mirrored to ENA** (SRA-only, NovaSeq), so it needs `prefetch`/`fasterq-dump`,
  not an ENA direct link — one reason it was not chosen for the harvest.

### DL-on-display precedents (from the thesis; deposition status noted honestly)
The innovation thesis cites two load-bearing precedents that DL on display data already works:
- **CfC/closed-form-continuous nets on ~15.7k mRNA-display ligands → pM binders.**
- **Ribosome-display enrichment prediction, DL r≈0.90.**

These are cited from `docs/20261005_INNOVATION_THESIS_CYCLIC_LLM.md`. **Their raw-NGS deposition status
could not be independently re-verified in this session** (the session's WebSearch budget was exhausted;
only the programmatic SRA/ENA APIs above were used). Several such ML papers train on **author-provided
processed enrichment tables (supplementary files), not SRA** — which is actually easier to consume than
raw reads. Follow-up (next session, with search budget): pull those papers' data-availability sections
and capture any Zenodo/figshare/supplementary tables directly. This is flagged, not claimed.

---

## 2. Feasibility assessment — how much is realistically free?

**Verdict: enough free data to *prototype and prove* the inverted-data-dependency model, NOT enough to
cover our targets. The free axis is "generic cyclic selection dynamics"; the paid axis is
"binding on PD-L1/αvβ6."**

| Question | Honest answer |
|---|---|
| Is round-over-round cyclic-display NGS free in SRA/ENA? | **Yes, but sparse and per-study.** Low tens of clean campaigns (~103 RaPID runs ceiling), each a separate engineering job. No corpus, no index, no uniform schema. |
| Is it enough to train a *general* sequence→enrichment model? | **Partially.** You can assemble maybe 10⁶–10⁷ enrichment-labeled cyclic sequences across a handful of RaPID campaigns — enough to pretrain a HELM/sequence LLM on *selection dynamics* and ncAA chemistry, and to prove the architecture. It is **not** the 10¹²–10¹⁴ library scale the thesis quotes (that lives only inside the selection, pre-sequencing; NGS samples ≤10⁷–10⁸ of it). |
| Is there free data on OUR targets (PD-L1, αvβ6)? | **No.** 0 hits. This is the gap the moat strategy predicted. **Requires a proprietary campaign** (phage ~\$30–80k/target; RaPID/PeptiDream partnership) per `docs/20261004_CYCLIC_PEPTIDE_DATA_WALL_STRATEGY.md` Step 2. |
| Is the raw data directly usable? | **No — it is DNA reads, not peptides.** Every dataset needs: (a) **translation** of the variable region located between study-specific constant anchors; (b) **cyclization inference** from the construct chemistry (thioether/ClAc-Cys for RaPID; head-to-tail split-intein for SICLOPPS; disulfide for many phage libs) — the FASTQ never states it; (c) **enrichment computation** from round/arm frequency ratios, with per-study denominators (round baseline vs input/output). |

**Per-dataset processing cost (what each needs):**
- **PRJNA1188087 (RaPID PADI4):** translate `(NNK)6-12` between `CATATG`(ATG) and `TGCGGCAGC`(Cys-GS); drop
  amber(TAG)/frameshift; cyclize = ClAc-init + variable + Cys thioether; enrichment = per-round log2FC.
  **(Done here — see §3.)**
- **PRJNA1406026 (XL RaPID input/output):** same anchor family but enrichment = **output/input ratio**
  per selection (cleaner, one number per peptide); extra step = decode photo-AA Met-reprogramming position.
- **PRJNA1170358 (SICLOPPS/PACE):** different construct (intein-flanked cyclization cassette in M13);
  canonical AAs only; "enrichment" is phenotypic/continuous, not discrete panning — needs custom
  per-sample handling; **excluded from the ncAA-primary signal** but useful as canonical-cyclic positives.

**Bottom line for the program:** the free harvest is a **real, non-trivial prototype substrate** (and we
now hold one worked example end-to-end), but it is **not a substitute** for the proprietary per-target
campaign. Mine-and-prototype now at \$0; commission PD-L1/αvβ6 campaigns for the moat.

---

## 3. The one harvested + processed dataset

**Chosen (smallest viable with clean round labels, ENA-mirrored, ncAA-native):**
**PRJNA1188087 / SRP546185** — *"Discovering Covalent Cyclic Peptide Inhibitors of PADI4 Using mRNA
Display with a Genetically Encoded Electrophilic Warhead"* (Imperial College London). Harvested the
**15-min WT arm, rounds R2–R6** (5 runs, ~280 MB compressed, ~11.8 M reads) via **ENA direct fastq**
(`ftp.sra.ebi.ac.uk/vol1/fastq/...`, preferred over SRA prefetch per guardrail).

Runs: R2=SRR31398313, R3=SRR31398311, R4=SRR31398310, R5=SRR31398309, R6=SRR31398312.

**Read structure (from SRA DESIGN_DESCRIPTION), single 151-cycle MiSeq v3:**
```
5'-TAATACGACTCACTATAGGG TTAACTTTAAGAAGGAGATATA CATATG (NNK)n TGCGGCAGCGGCAGCGGCAGC TAG GACGGGGGGCGGAAA-3'
   T7 promoter          Shine-Dalgarno          ATG↑   n=6..12  ↑Cys(TGC)+GSx3 linker  stop
```
Macrocycle = **ClAc-initiator (reprogrammed AUG) + (NNK)ₙ variable residues + fixed Cys**, closed as a
**thioether** (head-to-sidechain). The variable (NNK)ₙ region is the extracted diversity.

**Processing results (QC per round — the enrichment fingerprint):**

| Round | Reads | Productive (translatable, in-frame, no amber) | Productive % | Unique peptides |
|---|---|---|---|---|
| R2 | 3,906,522 | 1,379,992 | 35.3% | 780,697 |
| R3 | 3,140,620 | 953,963 | 30.4% | 525,913 |
| R4 | 2,950,565 | 1,595,672 | 54.1% | 547,149 |
| R5 | 710,554 | 517,934 | 72.9% | 158,257 |
| R6 | 1,100,989 | 298,327 | 27.1% | 28,936 |

Diversity collapses **780k → 29k** unique peptides R2→R6 and productive fraction rises as the library
converges — the signature of a working affinity selection.

**Validated biological signal (top enriched, min R6 count ≥20):** a dominant covalent-binder family
converges on the consensus **(V/A/M/L)YS·(M/T)·KEWKY**:

| Peptide | R2 | R3 | R4 | R5 | R6 | log2FC(R6/R2) |
|---|---|---|---|---|---|---|
| **VYSMKEWKY** | 510 | 4,442 | 61,634 | 166,216 | **220,874** | **10.96** |
| VYSMKERKY | 2 | 20 | 536 | 1,507 | 2,162 | 10.56 |
| AYSMKEWKY | 2 | 15 | 283 | 791 | 1,021 | 9.48 |
| MYSMKEWKY | 0 | 6 | 105 | 481 | 686 | 9.42 |
| VYSMKEWRY | 3 | 32 | 388 | 866 | 842 | 9.00 |

(De-enrichment is also captured, e.g. `RDHHYRHPKY` 550→9 = early-abundant non-binder washed out.)
This is a **real, point-mutant-coherent sequence→binding signal** — exactly the primary training label
the inverted-data-dependency LLM needs.

**S3 location:** `s3://knowledge-datasets-1759951976/cyclic_peptide/datasets/display_ngs_padi4_rapid/`
- `display_ngs_padi4_rapid_15min.csv.gz` (9.5 MB gz; **1,854,030 data rows** = 370,806 peptides × 5 rounds)
  — **long table, schema:** `sequence, n_residues, round, count, frequency, enrichment_log2fc_vs_baseline, cyclization, display_type`
- `display_ngs_padi4_rapid_15min_enrichment.csv.gz` (4.1 MB gz; **370,806 peptide rows**)
  — wide table: per-round counts+freqs + `log2fc_{R3..R6}_vs_R2` + `max_count`, sorted by abundance
- `display_ngs_padi4_rapid_15min_meta.json` — full provenance (anchors, codon range, per-round stats,
  enrichment definition, cyclization chemistry)

Peptide retention floor: max per-round count ≥ 3 (drops sequencing-error singletons); 370,806 of the
full union retained. Enrichment = `log2((freq_round+eps)/(freq_R2+eps))`, `eps = 1/min(round_total)`.

**Processing script (committed):**
`research/guangzhou_all_atom/harvest_display_ngs_rapid.py` — streaming gzip parser, dual-strand anchor
search, standard-codon translation, amber/frameshift QC, per-round + round-over-round enrichment, JSON
provenance. **Reusable** for other mRNA-display/RaPID studies via `--manifest/--up-anchor/--down-anchor/
--min-codons/--max-codons/--baseline-round` (e.g. point it at PRJNA1406026 with an input/output manifest).

**Reproduce:**
```bash
# 1. ENA direct fastq (no SRA toolkit needed)
for a in SRR31398313 SRR31398311 SRR31398310 SRR31398309 SRR31398312; do
  sub=${a:0:6}; d=00${a: -1}
  curl -sL -o $a.fastq.gz "https://ftp.sra.ebi.ac.uk/vol1/fastq/$sub/$d/$a/$a.fastq.gz"
done
# 2. manifest.tsv:  R2<TAB>SRR31398313.fastq.gz  ...  R6<TAB>SRR31398312.fastq.gz
python3 research/guangzhou_all_atom/harvest_display_ngs_rapid.py \
  --manifest manifest.tsv --outdir out --name padi4_rapid_15min --baseline-round R2
```

---

## 4. Recommendations / next steps
1. **Prototype now, \$0:** this table is immediately usable to extend the MVP cyclic HELM-LLM
   (`docs/20261005_INNOVATION_THESIS_CYCLIC_LLM.md` §MVP) from *property-conditioned* to
   *selection-round-conditioned* — train on (sequence, round, enrichment) to predict enrichment, the
   display primary signal. Natively ncAA (ClAc) + cyclic.
2. **Cheap expansion:** harvest **PRJNA1406026** (54 runs, 513 MB, input/output pairs → direct per-peptide
   enrichment) with the same script + an input/output manifest. Adds photo-ncAA chemistry.
3. **Verify the DL precedents' data** (next session, with search budget): pull the CfC-mRNA-display and
   ribosome-display-DL papers' data-availability + any Zenodo/supplementary enrichment tables.
4. **Moat (paid):** nothing public covers PD-L1/αvβ6 — commission the proprietary cyclic display campaign
   per `docs/20261004_CYCLIC_PEPTIDE_DATA_WALL_STRATEGY.md` Step 2 to get target-specific binding labels.

## 5. Sources (verified this session)
- **PRJNA1188087 / SRP546185** — RaPID covalent PADI4, Imperial College London. NCBI BioProject
  `https://www.ncbi.nlm.nih.gov/bioproject/PRJNA1188087`; ENA `https://www.ebi.ac.uk/ena/browser/view/PRJNA1188087`.
  Read structure from SRA experiment `SRX…` DESIGN_DESCRIPTION (SRR31398309 et al.).
- **PRJNA1406026** — "Single-round XL RaPID selections Next Generation Sequencing" (input/output pairs,
  photo-reactive ncAA). `https://www.ncbi.nlm.nih.gov/bioproject/PRJNA1406026`.
- **PRJNA1170358 / SRP537232** — Tina Wang lab (UW-Madison), "Rapid discovery of cyclic peptide protein
  aggregation inhibitors through continuous selection" (SICLOPPS + PACE, Aβ42/hIAPP).
  `https://www.ncbi.nlm.nih.gov/bioproject/PRJNA1170358`.
- Strategy/thesis: `docs/20261004_CYCLIC_PEPTIDE_DATA_WALL_STRATEGY.md`,
  `docs/20261005_INNOVATION_THESIS_CYCLIC_LLM.md` (source of the CfC-15.7k and ribosome-display-DL
  precedents — deposition status flagged unverified above).
- RaPID platform background: Goto & Suga, *Acc. Chem. Res.* (RaPID), as cited in the strategy doc.
