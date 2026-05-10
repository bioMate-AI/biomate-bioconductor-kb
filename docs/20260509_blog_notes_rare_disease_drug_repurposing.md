# Blog Notes: Rare Disease + Drug Repurposing — TxGNN and Therapeutic Data Commons

Source: `rare_disease_resource.jpg`

## Core Insight

~7,000 rare diseases exist globally. Only 5% have FDA-approved treatments. The remaining 95% are untreated not because science is insufficient but because the economics are broken: small patient populations → low commercial return → no investment.

## Harvard Approach: TxGNN (Marinka Zitnik Lab)

- **TxGNN**: GNN covering 17,000 disease phenotypes; predicts which existing approved drugs may be effective for rare diseases
- Approach: **drug repurposing** — find new indications for already-approved compounds, avoiding full development cost
- Graph structure: drug → mechanism → pathway → disease phenotype; GNN learns multi-hop associations

## Therapeutic Data Commons (TDC)

- Open-source benchmark platform built by Zitnik lab
- Establishes common tasks + leaderboards so ML community and drug development community can share a language
- Problem it solves: ML researchers optimize for benchmark scores; pharma researchers optimize for clinical outcomes — no common ground

## Frontier Direction

TxGNN is evolving toward **agentic AI**: model can actively query FDA databases, pull real-time literature, and reason over multi-step inference chains. Shift from static prediction → dynamic action.

## Implications for BioMate

- BioMate's rare disease workflow (`raredisease` nf-core pipeline) handles sequencing/variant calling but not therapeutic recommendation
- A drug repurposing module (TxGNN-style) would directly address the "what can we do for this patient" question
- Connecting variant → pathway → druggable target → approved drug is the full rare disease loop BioMate should close
