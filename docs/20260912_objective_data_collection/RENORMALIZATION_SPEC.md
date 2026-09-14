# H4 Immunopeptidome Renormalization Spec (v1)

**Date:** 2026-09-14 · **training_eligible:** false (data-fix / evaluation artifact)
**Outputs:** `RENORMALIZED_H4_CORPUS.json` (this dir) + per-deposit tables at
`s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions/immunopeptidome/renormalized_v1/`

## Why (the problem this fixes)

Raw total-peptide counts are **NOT comparable across immunopeptidome deposits** because the
enrichment method differs:

- **Antibody-IP** (W6/32 pan-HLA-I or allele-specific IP) → clean surface HLA-I ligand.
- **Mild-acid-elution (MAE / MHC1-TIP)** → HLA-I ligand **PLUS** a large B2M-independent
  intracellular/membrane peptide background that IP excludes.
- **DIA-NN proteome matrices co-deposited** with an immunopeptidome study → mostly tryptic
  proteome, not ligand.

The worked proof is `A375_B2M_KO_DIAGNOSTIC.md`: A375 B2M-KO looked like it retained 88% of its
immunopeptidome on naive total-peptide count (contradicting the obligate B2M→HLA-I dependence), but
on **genuine-HLA-ligand space** it collapsed to ~12% — agreeing with the HAP1 B2M-KO PASS set (3%).
The 88% was MAE background. **All H4 scoring must therefore be on genuine-HLA-ligand space**, and
every deposit must be renormalized so IP and MAE deposits become comparable.

## Procedure (per deposit / per condition)

1. **Load the peptide table** (format heterogeneity handled — see Parsers). Extract, per condition
   (= per cell line and/or per treatment column), a map `peptide → summed presentation measure`
   (intensity where present, else spectral/PSM count). Peptide sequences are stripped of
   modifications (`(UniMod:x)`, `[..]`, non-AA) and uppercased; non-standard-AA rows dropped.
   Same-sample **MaxLFQ** duplicate columns are skipped so a condition is not double-counted.

2. **Get the deposit's HLA-I alleles.** Reported alleles (e.g. HeLaM-B*44 lines) or recovered
   cell-line genotypes (Cellosaurus / TRON-TCLP / source paper), reconciled in `hla_genotypes`
   (embedded in the run scripts; provenance in `RENORMALIZED_H4_CORPUS.json._meta`). **HAP1 was
   corrected** from A*03:01/B*51:01/C*01:02 (unsupported; used in the earlier diagnostic) to
   **A*02:01/B*40:01/C*03:04** (expression-validated in HAP1 immunopeptidomics). Using the wrong
   genotype had depressed HAP1 ligand-fraction ~20-fold (0.04 → 0.79).

3. **Genuine-HLA-I-ligand filter.** A peptide is a genuine ligand iff:
   - length **8–12** (canonical HLA-I; 9mer peak is the signature), **AND**
   - **exact-sequence match** to the union of the deposit's own alleles' peptides in the
     mono-allelic ligand reference
     (`monoallelic_ref/combined_monoallelic_hlaI_human.tsv.gz` — MHCflurry-2.0-MS ∪ SysteMHC
     AlleleLibs, **201 alleles / 642,003 peptides / 1.39M peptide-allele pairs**).
   - **Tooling note:** NetMHCpan / MHCflurry are **NOT installed** on the host (probed). This is an
     **anchor-overlap heuristic = conservative lower bound** (a true binder absent from the finite
     reference is miscounted as background, symmetrically in every condition). Same method as the
     diagnostic. A predicted-affinity re-score (v2, if MHCflurry is installed) would refine but is
     very unlikely to overturn the 9mer-peak + anchor-hit signals.

4. **Within-deposit normalization.** The presentation measure is converted to a **quantile rank in
   [0,1]** over all peptides in the condition (`(rank+0.5)/n`). Cross-lab absolute intensity scales
   therefore do not leak; only within-condition ordering is retained. Emitted per ligand in the
   renorm table column `ligand_quantile_norm`.

5. **Tag enrichment method** (`antibody-IP` / `mild-acid-elution` / `other`) from PRIDE metadata +
   the corpus inventory.

6. **QC per condition/deposit:**
   - `ligand_fraction = n_ligands / n_raw_distinct_peptides`
   - `ligand_fraction_of_8to12 = n_ligands / n_(len 8–12)` — the **anchor-hit rate among plausible
     HLA-I lengths**; this is the shape-robust, cross-method-comparable measure (removes the n_raw
     inflation from PSM-level vs peptide-level tables).
   - `frac_9mer` — HLA-I signature check (independent of reference coverage).

   **Classification** per deposit: `clean_HLA_ligand_space` (frac_9mer ≥ 0.30 AND
   ligand_fraction_of_8to12 ≥ 0.30), `method_confounded_or_proteome` (frac_9mer < 0.15 OR
   ligand_fraction_of_8to12 < 0.10), else `mixed`/`intermediate`.

## Interpreting low ligand-fraction (two distinct causes — do not conflate)

- **Method artifact / proteome contamination** — low `frac_9mer` (<0.15) AND low anchor-hit. The
  table is not a clean HLA-I immunopeptidome (co-eluted background, or a proteome DIA matrix). These
  deposits' **raw** scoring is method-confounded — **flagged**. Examples: PXD060572/060575 (the
  proteome arm of the ERAP1 paired study), PXD070471 (CaCo2/THP1 — weak).
- **Reference-coverage floor** — **high** `frac_9mer` (real immunopeptidome) but low anchor-hit
  because the deposit's alleles are rare / thinly covered in the 201-allele reference. This is an
  exact-match limitation, **not** a method artifact — the deposit is still clean ligand space.
  Examples: PXD024109 (A*29:02 birdshot-LCL), PXD070607 (MIA PaCa-2 A*24:02/B*14:02/C*08:02).
  `frac_9mer` is reported precisely so these are not mistaken for method artifacts.

## Parsers (format heterogeneity)

| Format | Deposits | Peptide col | Measure |
|---|---|---|---|
| FragPipe `combined_peptide.tsv` | PXD065279, PXD070471, PXD070607 | `Peptide Sequence` | per-sample Intensity (MaxLFQ dup skipped), else Spectral Count |
| FragPipe `psm.tsv` | PXD070941 | `Peptide` | Intensity else PSM row-count |
| Spectronaut `Peptide_List.txt` | PXD054491, PXD054494 | `PEP.StrippedSequence` | Σ `*.MS2Quantity` |
| DIA-NN `pr_matrix.tsv` | PXD060572, PXD060575 | `Stripped.Sequence` | per-run intensity (replicates pooled) |
| DIA-NN long report (streamed from `Search.zip`) | PXD056426 | `Stripped.Sequence` | `Precursor.Quantity`; condition = KO-gene folder in `File.Name` |
| PD/Percolator `PeptideGroups.txt` (quoted TSV) | PXD024109 | `Sequence` | Σ `Abundances Grouped` (else detection) |
| Multi-cell-line CSV | PXD022020 | `Unmodified Peptide Sequence` | per-cell-line column (each column = distinct genotype) |
| mzTab PSM section | PXD013064 | `sequence` | PSM row-count |
| mzIdentML (streamed `iterparse`) | PXD045265, PXD055205 | `<PeptideSequence>` via `peptide_ref` rank-1 | PSM count |

## Reproduce

```
# host: python3 + pandas; aws cli (Bash dangerouslyDisableSandbox:true)
# 1. fetch reference + build per-allele index -> ref_index.pkl (201 alleles)
# 2. download processed peptide tables to ./tables/ (see RENORMALIZED_H4_CORPUS.json deposits[].renorm_table for provenance)
python3 run_tabular.py    # tabular + streamed PXD056426 zip
python3 run_mzid.py       # mzIdentML deposits
# consolidation -> RENORMALIZED_H4_CORPUS.json ; per-deposit *_renorm_v1.tsv
```
Scripts: `renorm.py` (engine), `deposit_config.py` + `hla_genotypes.py` (config), `run_tabular.py`,
`run_mzid.py`. Disk-frugal: raw MS never downloaded; big zips streamed with `unzip -p` and deleted;
intermediates removed.

## Output schema

`RENORMALIZED_H4_CORPUS.json.deposits[ACC]`: `method`, `n_conditions`, `n_raw`, `n_ligands`,
`ligand_fraction`, `ligand_fraction_of_8to12`, `median_frac_9mer`, `alleles`, `classification`,
`renorm_table` (S3), `conditions[]` (per-condition breakdown incl. cell_line).
Per-deposit table `<ACC>_renorm_v1.tsv`: `cell_line, condition, peptide, ligand_quantile_norm,
is_genuine_hla_ligand` (ligands only; the within-deposit-normalized presentation table).

## Limitations

- Exact-match anchor = conservative lower bound (no NetMHCpan/MHCflurry on host).
- Some conditions pooled where the processed table did not separate them (PXD055205 HCT116+HT29;
  PXD024109 SILAC light+heaviest).
- Cell-line genotypes: high-confidence for most (Cellosaurus/TRON/paper-concordant); medium for
  LNCaP / MIA PaCa-2 / HeLa-A. Near-haploid HAP1 treated hemizygous.
- v1 covers the clean-tabular + mzid core (14 deposits, 100 conditions). `.msf` (Proteome
  Discoverer), large `.mzid`, and per-line genotype-pending deposits deferred to v2 —
  see `deferred_usable_deposits`.
