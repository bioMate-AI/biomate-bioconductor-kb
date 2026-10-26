# A deployable peptide *availability* predictor (Landry-grounded) — useful model for the community + BioMate

**2026-10-25.** A real, honest, useful model — not a SOTA chase. Module: `research/guangzhou_all_atom/cyclic_llm/peptide_availability.py`.

## Why this, and why it's the *right* thing to build
Across this program every attempt to predict *binding/affinity* **across contexts** collapsed under proper
held-out testing (cyclic cross-target, renal cross-target, SH3 cross-domain). The honest lesson: binding
doesn't transfer. **But peptide *availability* — how much of the peptide is actually free to act in the
cell — is a peptide-*intrinsic* property, so it transfers where binding does not.** Lemieux … Landry
(bioRxiv 2026, doi:10.64898/2026.09.21.752983; 6,500+ in-cell DHFR-PCA variants) showed availability is
largely set by hydrophobicity/charge and **limits functional binding independently of affinity** — a factor
standard design pipelines ignore; we found no deployable Landry-calibrated predictor **[UNVERIFIED — no systematic prior-art search; simple hydrophobicity/charge filters are old]**. This is a modest, honestly-scoped contribution.

## The model
`availability_score = 0.3318 − 0.2541·meanKD_hydrophobicity − 0.1479·net_charge − 0.4793·frac_charged`
(OLS on Landry PCA1 measured availability, 7 domains (4 SH3: SHO1, ARHGAP26, EPS8L1, SNX9; 3 PDZ: TJP1-PDZ3, TIAM1-PDZ1, PDLIM4-PDZ1), ~3,000 variants; domain identities per the PCA2 analysis, `multitarget/pca2_cross_domain/README.md`). **Direction (corrected 2026-10-25):** more hydrophobic → lower; higher
fraction of charged residues → lower; **net charge enters with a negative coefficient, so net-POSITIVE peptides score lower and net-NEGATIVE (anionic)
peptides score HIGHER** — the earlier phrase "more charged → less available" was wrong for anions.

| metric | value |
|---|---|
| in-sample Spearman (pred vs measured availability) | 0.72 |
| **leave-one-DOMAIN-out Spearman (cross-domain, honest)** | **0.40** (per-domain 0.23–0.49, robust) |
| low-availability flag | measured 25th-pct threshold (−0.142) |

Contrast with binding: the *binding* model's cross-domain Spearman was ~0.27 and **got worse** when
availability was added as a correction — because binding is domain-specific. Availability at a *robust* 0.40
across held-out domains is the usable, transferable signal. Honest scope: it is a **ranking / liability
flag**, not a precise oracle.

## Usefulness (community + platform + project)
- **Community (primary):** an open, first-of-its-kind deployable **availability-risk flag** for peptide
  designers — most directly functional for **intracellular** targets (SH3/PDZ/short-linear-motif and
  cell-penetrating peptides), where availability literally gates function. `predict_availability(seq)`.
- **Platform (BioMate):** an informational **availability/developability score** for the peptide gate chain,
  upgrading the ad-hoc "greasy" hydrophobicity flag with a calibrated, data-grounded model.
- **Project (αvβ6 / PD-L1):** screened our v2 CRO panel — **all 12 pass** the availability flag; the model
  correctly ranks the greasiest candidates (AVB6-V2-06, PDL1-V2-02) as relatively higher risk.

## Honest caveats (stated plainly)
1. **Moderate accuracy** (cross-domain ρ ≈ 0.40): a *ranking/triage* tool, not a quantitative oracle.
2. **Trained on canonical linear SH3/PDZ-binding peptides (4 SH3 + 3 PDZ domains).** For cyclic/ncAA macrocycles (our αvβ6 RGD cyclics,
   PD-L1 bicyclics) it is an **approximation** over the canonical residues; the module flags ncAA fraction.
3. **"Availability" here is *intracellular*.** It is directly functional for intracellular targets. **Our
   αvβ6/PD-L1 targets are cell-surface / extracellular**, so for *them* this score is a **developability /
   solubility-aggregation proxy** (hydrophobicity/charge-driven), not a functional-availability predictor —
   do not over-read the "pass" as functional validation for surface targets.

## Defects and warnings added after the 2026-10-25 committee review (verified in code; fixed unless noted)
- **Parser fixes:** `2Nal`-type ncAAs were silently dropped from the hydrophobicity mean; a bracketed `[Met]` would have parsed as `Me`+`t` (Thr);
  N-methylation was erased; an unparsable peptide returned `low_availability=False` with a NaN score (read as "ok"). Now: conservative surrogate map,
  N-methylation counted, unmapped residues counted, **abstain** (`low_availability=None`) above 25 % unmapped. Tests: `test_peptide_availability.py`.
  The v2-panel screen quoted above is unchanged (no 2Nal in those peptides).
- **It points the wrong way on the one tight SAR we own.** On the Quigley A1 grid the availability score is FF +0.100, YY +0.332, FY = YF +0.216 against
  potency FF > YY > FY > YF: Spearman(potency, availability) = −0.40 (n = 4 — a warning, not a statistic). YY→FF lowers the score by 0.231 while binding
  5× tighter. **Do not use availability as a design objective for αvβ6 radioligands**; it is a liability screen at most.
- **Open, not fixed:** (i) no external validation on cyclic/ncAA data; (ii) "no deployable availability predictor existed" is **[UNVERIFIED]** — charge/grease
  filters are old; the contribution is the Landry-calibrated cross-domain estimate; (iii) the Landry data are CC BY-NC-ND — whether four fitted coefficients
  are a derivative work is **[UNVERIFIED]**; get a licence review before redistributing or commercialising; (iv) the 25th-percentile threshold is a
  measured-label quantile applied to predictions, not a calibrated decision threshold.

## Provenance / open
Data: `github.com/Landrylab/Lemieux_et_al2026` (CC BY-NC-ND; `data/PCA1/med_avail_score.csv`). Our model
coefficients + module are open and reproducible from that data. Next (optional) upgrades: richer features /
nonlinear model (honest ceiling ~0.40 cross-domain), and position-aware availability; integrate as an
informational score (not a hard gate) in `score.py` / `knowledge_liability_flags.py`.
