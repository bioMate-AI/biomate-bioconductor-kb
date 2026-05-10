# Blog Notes: ROCKET Framework — Google DeepMind Cryo-EM + Crystallography Fusion

Source: `google_cryo_roket.jpg`

## Core Insight

ROCKET upgrades AlphaFold by fusing **MSA co-evolutionary embeddings** with **experimental electron density maps** (crystallography or cryo-EM). No retraining needed — ROCKET uses the existing AF2/AF3 trunk with experimental data injected as priors during inference.

## Key Capabilities

- Works on low-resolution cryo-EM data (6–10 Å), not just near-atomic
- Fuses crystallographic structure factors + cryo-EM density maps as hard constraints
- Co-evolutionary MSA embedding provides structural context; density maps provide experimental grounding
- Result: models that honor experimental data rather than ignoring it (pure AF3 can hallucinate loops)

## Technical Significance

Traditional model building pipelines (Phenix, REFMAC, COOT) require manual intervention and expert crystallographers. ROCKET automates the "fitting to density" step that has been the bottleneck for non-atomic resolution structures.

## Implications for Cryo-EM Workflows

- BioMate currently routes cryo-EM to CryoSPARC SPA — this is reconstruction, not model building
- ROCKET fills the gap **after** reconstruction: map → fitted model → refined structure
- Low-res cryo-EM of membrane proteins / large complexes (where ROCKET shines most) is currently not served by BioMate
