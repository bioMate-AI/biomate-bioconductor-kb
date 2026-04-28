# Reference: The AI Scientist — Nature 2026

## Citation

**Title**: The AI Scientist: Towards Fully Automated Open-Ended Scientific Discovery  
**Authors**: Lu et al. (Sakana AI, UBC, Vector Institute, University of Oxford; incl. Jeff Clune, Jakob Foerster)  
**Journal**: *Nature*  
**DOI**: https://doi.org/10.1038/s41586-026-10265-5  
**Published**: 2026-03-26  

## Code Repositories

- **v1** (original): https://github.com/SakanaAI/AI-Scientist  
- **v2** (agentic tree search): https://github.com/SakanaAI/AI-Scientist-v2  
- **v2 paper (PDF)**: https://arxiv.org/pdf/2504.08066

## Key Milestone

An AI-generated manuscript passed peer review at the ICLR 2025 ICBINB workshop — the first fully AI-generated paper accepted through formal peer review (average reviewer score 6.33, top ~45% of submissions).

## Core Autonomous Loop Design

The system implements a four-stage iterative cycle:

```
1. Hypothesis Generation
   └── LLM generates novel research ideas from a broad direction
   └── Retrieves and reads relevant literature

2. Experimental Design & Execution
   └── Programs and runs experiments via parallelized agentic tree search
   └── v2 uses an Experiment Manager agent to coordinate sub-agents

3. Analysis & Write-up
   └── Produces complete LaTeX paper with figure feedback from vision model
   └── Self-critiques and iterates on the write-up

4. Automated Review & Refinement
   └── Automated Reviewer scores the manuscript
   └── Feedback triggers another iteration of steps 1–3
```

## Relevance to BioMate Auto-Loop

The AI Scientist's core insight: **science is a closed feedback loop** — run an experiment, evaluate the result against a quality criterion, adjust the hypothesis/parameters, repeat.

BioMate's cryo-EM auto-loop (`backend/experiments/cryo_em_autoloop/`) applies this same principle at the **workflow phase level**:

| AI Scientist concept | BioMate cryo-EM equivalent |
|---------------------|---------------------------|
| Hypothesis | Initial processing parameters (pixel_size, CTF range, etc.) |
| Experiment | One phase of the CryoSPARC pipeline (motion correction, 2D classification, etc.) |
| Quality criterion | QC gates in `cryosparc_qc_gates.py` (FSC, drift, junk fraction, etc.) |
| Automated Reviewer | `CryoEMQCEvaluator` — runs gate suite, returns GOLD/SILVER/BRONZE/HALT |
| Iteration | `ParamTuner.remediate()` adjusts parameters, phase reruns |
| Write-up | `AuditLogger` → structured JSONL + HTML summary report |

## Key Differences from AI Scientist

- AI Scientist targets open-ended ML research (broad, hypothesis-driven)
- BioMate targets deterministic bioinformatics workflows (narrow, metric-driven)
- BioMate has fixed QC thresholds from domain literature (not LLM-scored)
- BioMate's loop is per-phase, not per-paper; terminates in minutes, not days
