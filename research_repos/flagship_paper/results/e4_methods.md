# Experiment E4 — Regulatory Audit Completeness of Run Logs

## Claim
A regulatory reviewer can reconstruct every threshold decision from a BioMate run log because each gate carries `paper_ref + paper_doi + provenance grade + rule_text`. Standard cryo-EM/ADMET/HTS/PBPK/clinical tools log only metric values and at most a numeric threshold, so a reviewer cannot tell whether a threshold reflects regulatory consensus, community heuristic, or arbitrary developer choice.

## Operational definition
For each *threshold decision* (a gate firing in a run), assign a per-decision score:

| present fields                | score |
| ----------------------------- | ----- |
| none of {paper_ref, DOI, provenance grade} | 0     |
| exactly one                   | 0.33  |
| exactly two                   | 0.67  |
| all three                     | 1.00  |

The per-run audit completeness is the arithmetic mean across that run's decisions. The per-tool group statistic is the mean across runs.

## Auditor algorithm
Implementation: `scripts/e4_audit_completeness.py`.

```
for each log file:
    decisions = log["gates"]            # BioMate
              | log["decisions"]        # baselines
    per-decision score = (# of paper_ref/paper_doi/provenance fields present) / 3
    per-run score = mean(per-decision scores)
mann-whitney U two-sided between BioMate vs baseline pool.
```

For BioMate logs the auditor looks inside each gate's `evidence` list (the shape emitted by `backend/lib/galaxy/ai/retrievers/qc_gate_reader.py::build_gate_event`, populated from `backend/config/qc_evidence.yaml`); the highest-scoring evidence entry wins. For baselines, the same three fields are looked up at the top level of each decision row, which is where they would have to appear in a downstream audit dossier. Vendor documentation URLs (e.g. a Spotfire user guide) are recorded for transparency but are **not** counted as `paper_ref` or `paper_doi`, since they are product documentation rather than scientific provenance.

## Run sample (n=10 each)
The experiment is a logging audit, not an execution audit, so runs are constructed synthetically but with gate event shapes copied verbatim from BioMate production code. Domains were chosen to span the five workflow families most cited in the publication plan:

| domain        | runs | scenario                                       |
| ------------- | ---- | ---------------------------------------------- |
| cryo-EM       | 2    | passing SPA + failing motion/particles run     |
| ADMET         | 2    | hERG+DILI fail + clean compound                |
| HTS plate QC  | 2    | passing + failing Z'/SW                        |
| PBPK          | 2    | passing + mass-balance & Tmax failure          |
| BOIN clinical | 2    | escalation + de-escalation decision            |

For each BioMate run a parallel baseline log was constructed representing what the equivalent standard tool would emit:

- **CryoSPARC Live** dashboard JSON — metric + pass/fail flag only (https://guide.cryosparc.com/live).
- **RELION 4 schemes** — thresholds embedded in scheme `.star` job parameters but no citations (Kimanius et al., *IUCrJ* 2021;8:801-813, doi 10.1107/S2052252521008538).
- **DataWarrior** / manual ADMET CSV — rule flags from built-in model, no published cutoff in output.
- **TIBCO Spotfire** plate report — threshold lines visible, no DOI.
- **PK-Sim / GastroPlus** simulation reports — metric+flag from GUI; design references in the manual, not in per-run output (Simulations Plus and Bayer documentation).
- **SAS BOIN macro** (`%BOIN`, Yuan et al. 2016 doi 10.1158/1078-0432.CCR-16-0592) — per-decision log row contains threshold but no citation; the methodology citation sits in the macro header, not the trial dossier.

This honestly reflects how those tools structure their outputs today; none of them emit `paper_ref / DOI / provenance` per-decision in the run log. Where a tool *does* embed a threshold value (RELION schemes, Spotfire, SAS BOIN, PK-Sim AUC fold), the auditor scores no points because the operational definition requires a scientific anchor, not just a number.

## Statistical test
Mann-Whitney U two-sided, n1 = n2 = 10. Implemented with the standard-normal approximation inside `e4_audit_completeness.py` (no SciPy dependency).

## Outputs
- `results/e4_audit_completeness_per_run.csv` — one row per (tool, run_id).
- `results/e4_completeness_summary.csv` — group-level min/Q1/median/Q3/max/mean plus the Mann-Whitney line.
- `figures/e4_audit_completeness.png` — box+strip plot, two columns (BioMate vs baseline pool), with significance annotation.

## Reproduction
```
python scripts/e4_generate_logs.py
python scripts/e4_audit_completeness.py
python figures/e4_audit_completeness.py
```
