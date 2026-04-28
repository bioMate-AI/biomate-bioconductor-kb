# bioRxiv Submission Package — BioMate-Cryo

## Submission checklist

- [x] Manuscript draft: `manuscript/MANUSCRIPT_DRAFT.md`
- [x] Table 1 filled with real computed numbers (EMPIAR-10028, 20-movie P36 run)
- [x] Per-job timing table with real CryoSPARC timestamps
- [x] DOCX ready: `manuscript/BioMate_Cryo_preprint.docx`
- [ ] Register Zenodo DOI for benchmark run data + code
- [ ] Fill author affiliations (Sister's institution, collaborators)
- [ ] Add GitHub repository URL
- [ ] Upload to bioRxiv.org
- [ ] TRPV1 benchmark run (EMPIAR-10005) — in preparation
- [ ] Full-dataset run (1,081 particle stacks) — in progress

---

## bioRxiv submission fields

**Title:**
BioMate-Cryo: Evidence-Graded Interactive QC Governance for Automated Single-Particle Cryo-EM

**Category:** Structural Biology · Methods and Resources

**Authors:**
Yaoyun Zhang¹*, [Sister's Name]²*, [Structural Biology Co-author]³  
¹ BioMate AI Platform  
² Department of [Structural Biology], [Institution]  
³ [Cryo-EM Core Facility], [Institution]  
*Equal contribution

**Abstract (from manuscript):**
[Copy from manuscript § Abstract — ~280 words]

**Keywords:**
cryo-EM, single-particle analysis, quality control, Nextflow, CryoSPARC, reproducibility, audit trail, membrane proteins, automated processing, protocol-aware profiles

**License:** CC BY 4.0

---

## Convert to PDF (if needed)

```bash
cd research_repos/cryo_em_benchmark_paper
pandoc manuscript/MANUSCRIPT_DRAFT.md \
  -o manuscript/BioMate_Cryo_preprint.pdf \
  --pdf-engine=xelatex \
  -V geometry:margin=1in \
  -V fontsize=11pt
```

---

## Key verified numbers for preprint

All from EMPIAR-10028 P36 benchmark run (CryoSPARC project CS-biomate-20260427-071705):

- **24 jobs** (J1–J24, all completed: import → local resolution)
- **FSC 0.143 = 3.98 Å** (gold-standard, J20 validation job, independent half-maps)
- **26,284 final particles** (J22 NU-refine, 92.8% acceptance)
- **2.8 GPU-hours** (active compute), **7.4h wall time** (g6.2xlarge, 1× NVIDIA L4)
- **$6.29 estimated AWS cost**
- **0 QC gate halts** (purified_protein profile, clean EMPIAR-10028 data)
- FSC Nyquist-limited at 1.96 Å/px; full-resolution run in progress at 0.885 Å/px

---

## After bioRxiv posting

1. Add bioRxiv DOI to companion paper (CryoEnsemble preprint — see `../cryoensemble_paper/`)
2. Add bioRxiv DOI to Google.org AI4Science proposal (deadline 2026-05-01)
