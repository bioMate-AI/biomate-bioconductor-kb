# Blog Notes: Hard Target Drug Discovery — GNN + Chemical Language Models

Source: `hard_target_research.jpg`

## Core Insight

Undruggable / hard targets (membrane proteins, transcription factors, intrinsically disordered proteins) are a major frontier. GNN + Chemical Language Model (CLM) hybrid architectures show promise for predicting binding affinity, but generalization outside kinase-like pockets is still weak.

## Key Methods

- **GNN** encodes molecular graph topology; learns atom-level interaction features
- **CLM** (e.g., ChemBERTa, MolBERT) encodes SMILES/SELFIES; transfers chemical knowledge from large pretraining corpora
- Hybrid: GNN for local binding-site geometry + CLM for global drug-likeness → better than either alone
- Validated on kinase panels; benchmark accuracy ≥85% on known kinases

## Limitations

- Membrane protein targets: sparse training data, no reliable docking poses → model generalizes poorly
- Transcription factors: flat, hydrophobic PPI surfaces → conventional binding-affinity metrics mislead
- Covalent binders: require different scoring functions; most models assume non-covalent

## Implications

Hard targets require a different workflow: homology-based pose generation → uncertainty-quantified affinity prediction → experimental confirmation loop. Current BioMate docking workflows are kinase-centric.
