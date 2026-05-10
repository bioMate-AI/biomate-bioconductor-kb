# Blog Notes: Single-Cell Research and Virtual Cell Models

Source: `singlecell_research_workflow.jpg`

## Core Insight

The frontier of single-cell AI is not just analysis — it is building a **Virtual Cell (虚拟细胞)**: a large model that can predict cell state changes, simulate perturbation responses (drug / gene / mRNA), and decode disease mechanisms, then guide drug design.

## Virtual Cell Model Requirements

The ideal sc-LLM (single-cell Large Language Model) should:
- Predict **cell state changes** over time / conditions
- Simulate **perturbation responses** (CRISPR KO, drug treatment, mRNA delivery)
- Perform **mechanism inference** — why does a perturbation cause a particular state change?
- Close the loop: `data → model → biology → insight`
- Operate in tight collaboration with wet lab for experimental validation

## Technical Stack

- Foundation model pretrained on scRNA-seq corpora (scGPT, Geneformer, scFoundation)
- Fine-tuning on perturbation datasets (Perturb-seq, CROP-seq)
- Multi-omics extension: scATAC-seq, spatial transcriptomics, proteomics
- Output: cell state embeddings + perturbation effect predictions

## Current Limitations

- Perturbation generalization: models trained on one cell type fail on others
- No single model yet achieves the full data→model→biology→insight loop
- Wet lab integration (closing the DBTL loop) is the hardest operational challenge

## Implications for BioMate

BioMate has scRNA-seq workflows (Seurat, scdownstream) for analysis. The gap is the **modeling layer**: connecting single-cell data to perturbation prediction and mechanism reasoning — the "what does this drug do at cellular resolution" question.
