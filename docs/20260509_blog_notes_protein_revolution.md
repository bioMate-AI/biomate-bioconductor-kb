# Blog Notes: AI Protein Design Revolution 2026

Source: `protein_revolution1.jpg` through `protein_revolution6.jpg`

## Timeline of Key Models

| Year | Model | Capability |
|------|-------|-----------|
| 2021 | AlphaFold2 | Structure prediction from sequence; CASP14 breakthrough |
| 2022 | ESMFold | 650M parameter pLM; 60× faster than AF2 |
| 2022 | RFdiffusion | Diffusion-based de novo scaffold generation |
| 2022 | ProteinMPNN | Inverse folding; designs sequences for target backbones |
| 2023 | LigandMPNN | ProteinMPNN + small-molecule pocket conditioning |
| 2023 | ESM3 | Multimodal (sequence + structure + function); 98B parameters |
| 2024 | AlphaFold3 | Extends to nucleic acids, small molecules, PTMs |
| 2024 | DiffSBDD | Structure-based drug design via diffusion |

## Pipeline: Lab to Clinic

Design → Computational screening → Wet lab validation → Preclinical → Clinical

- 165+ AI-designed antibody drugs in clinical development (2024)
- Structure-driven vaccine design: RSV prefusion F protein; HIV bnAb epitope scaffolds
- CAR-T: AI-designed antigen-binding domains showing improved tumor specificity

## Open Challenges

- **Data bias**: PDB is enriched for soluble, globular, eukaryotic proteins; membrane proteins / disordered regions underrepresented
- **Interpretability**: AF3 attention maps ≠ mechanistic understanding; engineers can't debug failure modes
- **Biosafety**: de novo protein design could generate novel pathogens; no regulatory framework yet
- **Fitness landscape accuracy**: structure ≠ function; catalytic efficiency, stability in physiological conditions still hard to predict

## The Design-Build-Test-Learn Loop

Efficient DBTL cycles require:
1. Fast in-silico generation (AF3/RFdiffusion)
2. High-throughput expression screening (cell-free systems, yeast display)
3. Functional assay with quantitative readout
4. ML feedback to update generative model priors

BioMate currently handles step 1 (structure prediction via ESMFold) and parts of step 3 (ADMET). Steps 2 and 4 are gaps.
