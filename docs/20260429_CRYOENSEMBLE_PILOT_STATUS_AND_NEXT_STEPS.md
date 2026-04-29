# CryoEnsemble Pilot Status & Next Steps — 2026-04-29

## Current State (as of ~12:00 UTC)

### Pilots running on AWS Batch

| Pilot | Job | Queue | Started | Est. finish |
|-------|-----|-------|---------|-------------|
| Pilot 0a | BIOEMU_SAMPLE (β₂AR) | biomate-nextflow-queue | 11:49 | ~13:00–13:30 |
| Pilot 0b | BIOEMU_SAMPLE (TRPV1) | biomate-nextflow-queue | 11:52 | ~13:00–13:30 |
| Pilot 2 | CRYODRGN_TRAIN (TRPV1 EMPIAR-10059) | biomate-nextflow-queue | 11:49 | ~13:30–14:30 |

**Container**: `biomate/protein-dynamics-nf:v1.0.5` (BioEmu 1.3.1 from PyPI, confirmed installed).  
**cryoDRGN container**: `biomate/cryo-heterogeneity-nf:latest`.

### Output paths to watch
```
s3://biomate-nextflow-work/pilot/results/beta2ar-bioemu-v3/summary/summary_report.json
s3://biomate-nextflow-work/pilot/results/trpv1-bioemu-v3/summary/summary_report.json
s3://biomate-nextflow-work/pilot/results/trpv1-cryodrgn-r6/   (after all 4 steps)
```

---

## Fixes applied this session (6 bugs resolved)

All bugs were in the Nextflow modules and Docker container; no manuscript changes required.

| # | File | Problem | Fix |
|---|------|---------|-----|
| 1 | `cryo_heterogeneity/main.nf` | `cryodrgn abinit_het` renamed in cryoDRGN ≥4.0 | Changed to `cryodrgn abinit` |
| 2 | `cryo_heterogeneity/main.nf` | Star file `_rlnImageName` had `s3://...mrcs` URIs; cryodrgn can't read S3 | Added Python block to download all mrcs locally, write `particles_local.star` |
| 3 | `cryo_heterogeneity/main.nf` | Groovy GString mangled Python heredoc: `${particles_mrcs}` caused adjacent lines to merge | Moved all NF vars to bash `NXF_*` env vars before the heredoc; Python reads via `os.environ` |
| 4 | `cryo_heterogeneity/main.nf` | `re.compile(r'\S+?')` — Groovy lexer rejected `\S` inside script block | Changed to `re.compile('s3://[^ \\t\\n]+[.]mrcs')` (no backslash metacharacters) |
| 5 | `protein_dynamics/main.nf` | Wrong BioEmu API: `from bioemu.sample import sample_conformations` (doesn't exist) | Correct API is `from bioemu.sample import main as bioemu_main`; takes FASTA not PDB |
| 6 | `protein-dynamics-nf/Dockerfile` | GitHub source install of BioEmu silently failed → MDAnalysis fallback always triggered | Changed to `pip install bioemu==1.3.1` from PyPI; v1.0.5 image (15.9 GB) pushed to ECR |

---

## What each pilot contributes

### Pilot 0 (β₂AR + TRPV1, real BioEmu)
- **If BioEmu model download succeeds** (requires HuggingFace + ColabFold MSA server access from the Batch network): generates 500 real conformers per protein with expected RMSD 5–10 Å — qualitatively different from the Gaussian surrogate (max 1.27 Å)
- **If BioEmu falls back** (HuggingFace timeout or MSA failure): generates 500 MDAnalysis Gaussian conformers again — positive control only
- **Status indicator**: check `summary_report.json` field `rmsd.max_angstrom` — surrogate ≈1.3 Å, real BioEmu ≥3 Å

### Pilot 2 (cryoDRGN, TRPV1 EMPIAR-10059)
- 27,983 real cryo-EM particles from EMPIAR-10059 (TRPV1 apo state)
- 20 epochs of `cryodrgn abinit` (heterogeneous ab initio, no prior poses)
- Outputs: latent space model + k-means cluster centroids (k=10)
- **First real conformational completeness gap measurement**: subtract Pilot 0b BioEmu ensemble coverage from the cryoDRGN cluster coverage

---

## Planned analysis once jobs complete

### 1. Run gap_analysis.py on real data (1–2 hours)
```bash
python scripts/cryo_pilot/gap_analysis.py \
  --cryodrgn_dir s3://biomate-nextflow-work/pilot/results/trpv1-cryodrgn-r6/ \
  --bioemu_dir   s3://biomate-nextflow-work/pilot/results/trpv1-bioemu-v3/ \
  --protein trpv1 \
  --output scripts/cryo_pilot/real_gap_results.json
```
Expected output: gap fraction (% BioEmu conformers not covered by any cryoDRGN cluster within 2.0 Å RMSD).

If real BioEmu conformers have 5–10 Å RMSD and cryoDRGN clusters have 1–3 Å coverage radius → gap fraction expected 20–50% (vs 0% for Gaussian surrogate).

### 2. Update manuscript with real gap fraction (30 min)
- Replace Table 2 Gaussian surrogate numbers with real data for TRPV1
- Update §4.2 "Why 10% is a lower bound" with the measured real gap
- Update abstract to cite real gap fraction alongside ADK PoC numbers

### 3. Update proposal quantitative objectives table (15 min)
- §3.4 currently cites 10% surrogate as baseline; update with real TRPV1 gap fraction
- This is a stronger motivator: "we measured X% gap on real cryo-EM data, CryoEnsemble targets ≤5%"

---

## What is NOT further pilot work (future research milestones)

| Item | Why not pilot | Timeline |
|------|--------------|----------|
| smFRET validation (R² ≥0.70) | Requires posterior inference, not just prior ensemble | Year 1 of funded project |
| CryoBench rare-state recall (≥50%) | Requires full CryoEnsemble posterior implementation | Year 1-2 |
| Per-particle image likelihood on real 2D projections | ADK PoC used coordinate-space particles | Year 1 |
| Full BioEmu-1 integration with pose disentanglement | Adopting cryoDRGN-AI 2025 as foundation | Year 1 |

---

## Open gap before May 1 proposal submission

The proposal V2 (`docs/20260429_GOOGLE_AI4SCIENCE_PROPOSAL_V2.md`) is **scientifically complete**. One item blocks submission:

### Sister's affiliation — fields to fill

```markdown
## Authors / PI

**PI:** [Sister's Full Name], PhD
**Institution:** [University Name]
**Department:** [Department of Structural Biology / Biophysics / etc.]
**Address:** [University Address]
**Email:** [institutional email]

**Co-PI:** Yaoyun Zhang
**Organization:** BioMate AI
**Email:** xiaoni5122@gmail.com
```

These appear in:
- Proposal cover page (§1 Project Leadership)
- Budget justification (PI salary line)
- Author list on manuscript draft

**Action:** User to provide these 4 fields from sister's CV. Once filled in, proposal is ready for submission to Google.org AI4Science (deadline: 2026-05-01).

---

## Session commits (this session)

```
241ebb68e  fix(cryodrgn): escape regex backslashes for Groovy GString compatibility
8c0cce50e  fix(cryodrgn): move Nextflow vars to bash before Python heredoc
ab0cc6d80  fix(bioemu): correct API for BioEmu 1.3.1
6c967fa44  fix(cryo-pilot): cryodrgn abinit + S3 mrcs download + BioEmu v1.0.5
8e98f4530  feat(manuscript): incorporate ADK PoC results and refine innovation framing
```

---

## Known risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| BioEmu model download fails (HuggingFace blocked from Batch) | Medium | MDAnalysis surrogate is the fallback; manuscript already honest about this |
| cryoDRGN abinit takes >3h or fails on 27K particles | Low | 20 epochs is conservative; can reduce to 10 if needed |
| Batch spot preemption | Low | Queue uses on-demand (`biomate-nextflow-queue`) |
| gap_analysis.py not yet adapted for real cryoDRGN output format | Medium | Script needs to parse actual cryoDRGN latent space output, not simulated |
