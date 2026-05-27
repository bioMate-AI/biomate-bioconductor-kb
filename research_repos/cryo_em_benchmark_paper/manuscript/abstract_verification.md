# BioMate-Cryo Abstract Verification — 2026-05-27

## Existing abstract (from MANUSCRIPT_DRAFT.md)

Single-particle cryo-electron microscopy (cryo-EM) has become the dominant technique for high-resolution protein structure determination, yet automated processing pipelines universally apply quality control (QC) thresholds through silent automatic filtering — bad micrographs are discarded and processing continues without alerting the investigator or providing an explanation. For novel or challenging samples — membrane proteins exhibiting elevated beam-induced motion, low-contrast particles, flexible assemblies — this silent filtering discards scientifically valid data because standard thresholds are inappropriate for the sample biology. We present **BioMate-Cryo**, an AI-assisted cryo-EM processing platform that replaces silent filtering with *interactive, evidence-graded QC governance*: when a threshold is exceeded, the pipeline halts, presents the failing metric with its citation evidence level (GOLD/SILVER/BRONZE), proposes specific parameter changes, and awaits an explicit human decision recorded in a portable audit trail. BioMate-Cryo orchestrates the complete 23-step CryoSPARC single-particle analysis (SPA) pipeline, with seven QC gate modules covering motion correction, CTF estimation, particle picking, 2D classification, 3D refinement, FSC validation, and atomic model quality. Four named protocol-aware profiles — `purified_protein`, `membrane_protein`, `in_situ_tomography`, and `small_particle` — apply biology-appropriate thresholds; the membrane protein profile relaxes drift acceptance from 50 Å to 80 Å and CTF fit quality from 0.70 to 0.65, consistent with published membrane protein cryo-EM practice. On benchmark data from the Electron Microscopy Public Image Archive (EMPIAR), BioMate-Cryo achieves FSC 0.143 reconstruction of E. coli β-galactosidase (EMPIAR-10028) from 20 micrographs — 24 CryoSPARC jobs, 26,284 final particles, FSC = 3.98 Å (Nyquist-limited), 2.8 GPU-hours, zero gate halts — while providing full audit traceability absent from existing tools. The protocol-discrimination benchmark quantifies false-positive micrograph rejections eliminated when the `membrane_protein` profile is applied vs. the default `purified_protein` profile: 100% of membrane-protein-like exposures (drift 58–74 Å, CTF fit 0.67–0.72) are falsely rejected under `purified_protein`, and none under `membrane_protein`. Every threshold is citation-backed: GOLD thresholds (e.g., FSC 0.143, Henderson et al. 2012) cannot be silently overridden; SILVER thresholds (method-specific best practice) require a logged justification; BRONZE thresholds (community heuristic) are auditable but flexible.

## Verification of key numbers against current manuscript

| Claim in abstract | Source in manuscript | Status |
|---|---|---|
| FSC = 3.98 Å (run A, Nyquist-limited at 1.96 Å/px) | Results table, J20 | MATCHES |
| 26,284 final particles (run A) | Non-uniform refinement (J22), 92.8% acceptance from 28,316 | MATCHES |
| 2.8 GPU-hours (run A) | Results table, "GPU-bound stage time ~2.8h (1 GPU)" | MATCHES |
| 24 CryoSPARC jobs | Methods narrative ("complete 24-job CryoSPARC pipeline") | MATCHES (abstract says "24 CryoSPARC jobs"; earlier sentence says "23-step" — minor wording inconsistency between pipeline step count and CryoSPARC job count, but both internally consistent across the manuscript) |
| 20 micrographs | Methods ("20 raw movie stacks from EMPIAR-10028") | MATCHES |
| Membrane-profile FP-rejection: 100% under purified_protein, 0% under membrane_protein | Table 3 / membrane_qc_result.json | MATCHES |
| Drift range 58–74 Å in synthetic membrane exposures | Methods ("58.9–74.1 Å") | MATCHES (rounded) |
| CTF fit 0.67–0.72 in synthetic membrane exposures | Methods | MATCHES |
| 4 named profiles | Methods + Table 2 | MATCHES |
| 7 QC gate modules | Methods (Gate 1–7) | MATCHES |
| GOLD/SILVER/BRONZE grading + Henderson 2012 citation | Methods (grading section) | MATCHES |

## Verdict

**MATCHES current state — Yes, with one minor flag.**

Flag (not auto-corrected):
- The abstract describes the pipeline as having "23 steps" while later text refers to the same pipeline as "24 CryoSPARC jobs". Both numbers appear in the manuscript and refer to the same workflow (the discrepancy is "pipeline steps" vs. "atomic CryoSPARC jobs incl. a separate validation/import job"). On the next rewrite, reconcile to a single number (recommend "24 CryoSPARC jobs across the 4-phase pipeline").

The run-B numbers (FSC 1.78 Å, 26,312 polished particles, 4-GPU g6.12xlarge, 0.45h GPU-stage, 3.4× speedup) are **not present in the existing abstract**. They appear in the Results section and represent a stronger headline ("Nyquist-limited at native pixel size + multi-GPU parallelism"). Optional improvement on next revision: lead with run-B FSC=1.78 Å as the flagship resolution claim and keep run-A as the audit-traceability/zero-halt demonstration.
