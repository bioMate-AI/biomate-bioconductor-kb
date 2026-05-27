# Experiment E1 — Methods

## Claim

A workflow with fixed (default-profile) QC thresholds will falsely reject
valid data when sample biology deviates from default assumptions. A
profile-aware system that lets users select sample-appropriate thresholds
recovers that data without compromising rejection of truly-failed samples.

## Domains and profiles

### HTS — plate quality and hit calling

Reference workflow:
`backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/hts_plate_qc_hit_calling/main.nf`

| Profile | Z'-factor min | Signal window min | Rationale |
|---|---|---|---|
| `default` | 0.50 | 2.0 | Zhang JH 1999 "excellent" + Iversen PW 2006 SW>=2 |
| `screening_grade` | 0.40 | 1.5 | Zhang 1999 "doable" band — primary screens with live-cell or low-signal targets |
| `confirmatory_grade` | 0.70 | 2.5 | Stricter than default — dose-response confirmation |

### LNP — formulation optimization

Reference workflow:
`backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/lnp_formulation_optimization/main.nf`

| Profile | Z-avg (nm) | PDI max | EE min (%) | Rationale |
|---|---|---|---|---|
| `clinical` | 60-120 | 0.20 | 85 | Yamamoto 2019 + Onpattro CMC + FDA Liposome 2018 |
| `research_grade` | 40-150 | 0.30 | 70 | Early formulation development — in vitro mechanism studies |
| `mrna_specialized` | 80-110 | 0.15 | 90 | Tighter than clinical — mRNA-LNP clinical-grade specification |

All thresholds are anchored to entries in `backend/config/qc_evidence.yaml`
(`hts.hts_z_prime`, `hts.hts_signal_window`,
`lnp_formulation.lnp_z_avg_particle_size`, `lnp_formulation.lnp_pdi`,
`lnp_formulation.lnp_encapsulation_efficiency`).

## Scenario generation

For each domain we generate 50 synthetic scenarios with stratified
ground-truth labels:

- **20 `default_grade`** — comfortably above default-profile cutoffs.
  - HTS: Z' ~ U(0.55, 0.85), SW ~ U(2.2, 5.0)
  - LNP: Z-avg ~ U(70, 115) nm, PDI ~ U(0.05, 0.18), EE ~ U(86, 95)%
- **20 `marginal`** — valid sample biology but below default cutoffs;
  pass the relaxed profile.
  - HTS (live-cell / low-signal target assays): Z' ~ U(0.40, 0.49),
    SW ~ U(1.50, 1.99) — Zhang 1999 "doable" band.
  - LNP rotated across 3 biology-driven modes:
    - large-particle research batch (Z-avg 120-150 nm)
    - small-particle research batch (Z-avg 40-59 nm)
    - in-vitro mechanism batch (clinical Z-avg, elevated PDI + lower EE)
    PDI ~ U(0.20, 0.29), EE ~ U(70, 84)%.
- **10 `truly_bad`** — fail any profile.
  - HTS: Z' ~ U(-0.10, 0.35), SW ~ U(0.60, 1.40) — Zhang "screen will
    not work" band.
  - LNP: Z-avg <40 or >150 nm (aggregation), PDI ~ U(0.30, 0.45),
    EE ~ U(40, 65)%.

Scenarios are synthetic but constrained to literature-anchored parameter
bands (see citations in `qc_evidence.yaml`). No fabricated experimental
identities, instrument readings, or compound IDs are used; only metric
values within the published ranges.

Random seed: `20260527`. Generator: `research_repos/flagship_paper/run_e1.py`.

## Evaluation

Each of the 100 scenarios (50 HTS + 50 LNP) is evaluated against each of
the 3 profiles in its domain (300 (scenario, profile) decisions). For
each (profile, ground-truth-class) cell we compute:

```
rejection_rate = n_failed / n_total
```

The headline claim is supported when:

1. `default`-profile rejection rate on `marginal` scenarios is high
   (false rejection of valid data).
2. The relaxed `screening_grade` / `research_grade` profile reduces
   `marginal` rejection rate dramatically while preserving 100%
   rejection of `truly_bad`.
3. The stricter `confirmatory_grade` / `mrna_specialized` profile
   correctly rejects more `default_grade` data (i.e. stricter QC is
   *also* a profile-aware decision, not a universal upgrade).

## Outputs

| File | Contents |
|---|---|
| `e1_hts_scenarios.csv` | 50 HTS scenarios (Z', SW) |
| `e1_lnp_scenarios.csv` | 50 LNP scenarios (Z-avg, PDI, EE) |
| `e1_per_scenario_profile.csv` | 300 (scenario, profile) pass/fail decisions |
| `e1_false_rejection_per_profile.csv` | Figure 1 source (18 rows: 2 domains × 3 profiles × 3 gt-classes) |
| `../figures/e1_false_rejection.png` / `.pdf` | Figure 1 |

## Reproducibility

```
cd research_repos/flagship_paper
python3 run_e1.py
python3 figures/e1_false_rejection.py
```

The script does **not** import or modify
`backend/lib/galaxy/ai/retrievers/qc_gate_reader.py` (subject to
parallel-session reverts); it reimplements identical threshold logic
locally with anchors documented above. The cryo-EM analogue of this
experiment lives in `research_repos/cryo_em_benchmark_paper/` and uses
the same false-rejection structure.
