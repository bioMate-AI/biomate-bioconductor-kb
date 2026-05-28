# ANDV campaign — bioRxiv submission package (v1 draft)

**Branch:** `integration/next-phase`  
**Assembled:** 2026-05-27  
**Status:** Draft — GROMACS MD in progress; NetMHCpan pending licensed tarball upload

---

## Manuscripts

| Track | File | Sprint data integrated |
|-------|------|------------------------|
| Plan A vaccine | [`../MANUSCRIPT_PLAN_A_VACCINE_v1_0.md`](../MANUSCRIPT_PLAN_A_VACCINE_v1_0.md) | Structural epitopes, cross-species, MHCnuggets; NetMHCpan noted as failed/missing |
| Inhibitor | [`../MANUSCRIPT_ANDV_INHIBITOR_v1_0.md`](../MANUSCRIPT_ANDV_INHIBITOR_v1_0.md) | Ensemble docking 3/3 improved; MD in progress |
| Plan B codon | [`../MANUSCRIPT_PLAN_B_CODON_v1_0.md`](../MANUSCRIPT_PLAN_B_CODON_v1_0.md) | Codon 25/57 replaced (43.86%); RNA2D + LNP succeeded |

---

## Figures (regenerate)

```bash
cd /home/yzhang/biomate
python3 research/anti-virus/scripts/generate_manuscript_plan_a_figures.py
python3 research/anti-virus/scripts/generate_manuscript_inhibitor_figures.py
python3 research/anti-virus/scripts/generate_manuscript_tables.py
```

| Bundle | Path |
|--------|------|
| Plan A | `research/anti-virus/runs/manuscript_figures_v1/plan_a/` |
| Inhibitor | `research/anti-virus/runs/manuscript_figures_v1/inhibitor/` |
| Tables | `research/anti-virus/runs/manuscript_figures_v1/tables/` |

---

## Primary data artifacts

| Artifact | Location |
|----------|----------|
| Chained inhibitor run | `research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/` |
| Ensemble sprint | `research/anti-virus/science_sprint/runs/20260527T195530Z/track_inh_ensemble/` |
| MD sprint metadata | `research/anti-virus/science_sprint/runs/20260527T195747Z/track_inh_md/` |
| Plan A structural | `research/anti-virus/science_sprint/runs/20260527T180210Z/track_plan_a_structural_epitopes/` |
| Plan A cross-species | `research/anti-virus/science_sprint/runs/20260527T180210Z/track_plan_a_cross_species/` |
| Plan A multitool | `research/anti-virus/science_sprint/runs/20260527T193013Z/track_plan_a_multitool/` |
| Campaign audit | `research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/AUDIT.md` |

---

## Pre-submission checklist

- [ ] GROMACS MD terminal status + MM–GBSA numbers in inhibitor manuscript
- [ ] NetMHCpan rerun after `netMHCpan-4.1b.Linux.tar.gz` on S3
- [ ] All figure PNG/PDF committed or archived with SHA256 manifest
- [ ] Remove internal paths / API keys from supplement
- [ ] Author list and correspondence filled in
- [ ] References completed (PDB primary citation, ADMET tools, generative module)
