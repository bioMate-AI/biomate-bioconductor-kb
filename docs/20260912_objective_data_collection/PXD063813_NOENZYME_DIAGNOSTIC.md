# PXD063813 — NO-ENZYME immunopeptidome diagnostic (feasibility + recipe)

**Date:** 2026-09-14 · **training_eligible:** false · **Run attempted:** NO (blocked) · **Result faked:** NO

## Goal
Reprocess the Liepe-lab B2M-KO deposit **PXD063813** raw timsTOF DIA with a **NO-ENZYME (unspecific)** search to recover the true **HLA-I ligandome**, then test whether **B2M-KO collapses the ligandome** in the two HLA-null single-allele transfectant lines **C1R-A\*02** and **K562-A\*02**. A clean collapse would confirm the H4 presentation mechanism on defined-allele lines and **localize the earlier A375 anomaly** (A375 B2M-KO retained ~88% — inconsistent with collapse) to A375 itself rather than to A\*02 biology.

The deposit's **held** processed file (`report.pr_matrix.tsv`) is a **tryptic whole-proteome DIA-NN search** (`--cut K*,R* --missed-cleavages 1`, avg peptide length 14.3, ~7,800 proteins/run). The proteome is unchanged by B2M-KO, so the held matrix's ~0.96–0.99 KO/WT detection ratio is **not** a presentation readout. The ligandome needs a fresh no-enzyme reprocessing.

## Feasibility verdict: **NOT FEASIBLE in this environment**

| Check | Finding |
|---|---|
| **Disk free** | **5.9 GB** |
| **Raw data** | 24 `.d.zip`, **145.69 GB** total; per-file **5.06–6.60 GB** compressed (mean 6.07), each unzips to ~10–15 GB |
| **One WT/KO pair** | ~36 GB of raw alone (2× zip + 2× unzipped) — **>6× the free disk** |
| **Search engine** | DIA-NN, MSFragger/FragPipe, philosopher, Comet, MS-GF+ **all absent**. Only Java present; no Docker/Singularity. DIA-NN exists only as BioMate Galaxy tool XMLs (cloud path, not a local binary) |
| **A\*02:01 anchor** | On **S3** (`.../monoallelic_ref/combined_monoallelic_hlaI_human.tsv.gz`), not local (regenerable from OPEN MHCflurry+SysteMHC) |

A single compressed `.d.zip` (min 5.06 GB) barely fits on 5.9 GB and leaves no room to unzip, and DIA-NN searches the **uncompressed** `.d`. Downloading/searching even one pair is physically impossible here. **No result was computed; nothing was faked.**

## Reprocessing recipe (for a proper node)

- **Engine:** DIA-NN 2.0.0 (match deposit), library-free diaPASEF, direct from `.d`.
- **FASTA:** reuse the deposit's `UP000005640_9606_AddedSequence_20250302.fasta` (13.7 MB — UniProt human + B2M-HLA construct).
- **Digest:** **UNSPECIFIC** — clear `--cut` (empty), `--missed-cleavages 0`. This is the core change vs the tryptic proteome search.
- **Peptide length:** **8–12** (`--min-pep-len 8 --max-pep-len 12`); optional 8–14 sensitivity re-run.
- **Charge:** 1–4. **Mods:** fixed Carbamidomethyl(C); variable Oxidation(M) (keep var-mods minimal — unspecific libraries explode).
- **FDR:** 1% precursor q-value; report decoy-based peptide FDR too.
- **Quant/MBR:** run **WT + KO of the same line together** with `--reanalyse` (MBR) for a fair within-line comparison.

Example CLI:
```
diann --dir <folder_of_.d> --fasta UP000005640_9606_AddedSequence_20250302.fasta \
  --fasta-search --predictor --cut  --missed-cleavages 0 \
  --min-pep-len 8 --max-pep-len 12 --min-pr-charge 1 --max-pr-charge 4 \
  --unimod4 --var-mods 1 --var-mod UniMod:35,15.994915,M \
  --qvalue 0.01 --reanalyse --matrices --out report_noenzyme.tsv --threads <N>
```

### A\*02:01 anchor scoring (genuine-ligand filter)
A detected 8–12mer counts as a genuine A\*02:01 ligand if **either** it exact-matches the A\*02:01 mono-allelic reference **or** MHCflurry 2.0 / MixMHCpred (both OPEN) give **%rank ≤ 2** vs HLA-A\*02:01. Sanity motif: P2 = Leu-dominant, C-terminus = Val/Leu.

**Retention metric:** `retention = genuine A*02:01 ligands in KO / genuine A*02:01 ligands in WT` (union over replicates, 1% FDR). Also report Jaccard(KO,WT), raw 8–12mer counts, and P2/C-term motif entropy (the motif should vanish on true collapse).

**Interpretation**
- **retention ≈ 0.15–0.30 + motif lost → COLLAPSE → confirms H4** on clean single-allele lines.
- **retention ≥ ~0.5 + motif retained →** mirrors the A375 anomaly (leaky KO / B2M-independent route).
- **Payoff:** if C1R & K562 collapse cleanly but A375 held 88%, the anomaly **localizes to A375** (leaky clone / residual surface HLA / MHC1-TIP sensitivity), not to A\*02 biology or the mechanism.

## Resource estimate (proper node)
- **Storage:** provision **≥500 GB** (145.7 GB download + ~200–300 GB uncompressed `.d` + predicted library + scratch). Can cap peak by processing one cell line at a time (~150–180 GB).
- **Download:** 145.7 GB over PRIDE FTP/https/Aspera, ~1–4 h.
- **Compute:** unspecific 8–12 over the human proteome → very large predicted library. **32–64 cores, 128–256 GB RAM** recommended (RAM-heavy); GPU optional.
- **Wall time:** library build 1–3 h + ~15–45 min/run × 24 + MBR pass → **~10–24 h** end-to-end.
- **Recommended route:** BioMate DIA-NN Galaxy tool on AWS Batch (the intended cloud execution engine; tool XMLs already in the repo), overriding protease→unspecific and length→8–12 per this recipe. Keeps it on BioMate rather than a local workaround.

## Caveats
- Even if run, PXD063813 is **A\*02-only** — it adds no disjoint HLA allele and does **not** re-power the leave-HLA-out gate. Value here is purely **diagnostic** (adjudicate A375).
- The held 0.96–0.99 KO/WT numbers are **proteome**, not ligandome — must not be cited as retention.
