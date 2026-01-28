# AI Scientist Systems Survey and Biomate Publication Plan

**Date**: 2026-01-28 14:58
**Purpose**: Comprehensive survey of AI agent systems for scientific research, benchmark datasets, and publication planning for Biomate public launch.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [BioDSA Framework Analysis](#biodsa-framework-analysis)
3. [Benchmark Datasets Inventory](#benchmark-datasets-inventory)
4. [Comparative Analysis of AI Scientist Systems](#comparative-analysis-of-ai-scientist-systems)
5. [Biomate Positioning and Differentiation](#biomate-positioning-and-differentiation)
6. [Publication Plan](#publication-plan)
7. [Testharness Work Plan](#testharness-work-plan)
8. [Next Steps](#next-steps)

---

## Executive Summary

This document surveys the current landscape of AI agent systems for scientific research, with focus on:

1. **BioDSA** - A comprehensive biomedical data science agent framework from Jimeng Sun's group
2. **ACE Framework** - Agentic Context Engineering for self-improving LLMs
3. **Clawdbot** - Multi-channel messaging integration for AI agents
4. **Other AI Scientist Systems** - To be expanded with additional systems

Key findings:
- BioDSA provides **8 specialized agents** with well-defined benchmarks
- **10+ benchmark datasets** available for evaluation with 2000+ tasks total
- BioDSA published in **Nature BME, Nature Methods, Nature Communications, JAMIA**
- Biomate has unique strengths in **workflow generation** and **Galaxy integration**

---

## BioDSA Framework Analysis

### Overview

**Repository**: https://github.com/RyanWangZf/BioDSA (cloned to `reference/BioDSA/`)
**Homepage**: https://biodsa.github.io
**Platform**: https://keiji.ai
**License**: See LICENSE file

BioDSA is a modular, open-source framework for building, reproducing, and evaluating biomedical data science agents. It prioritizes clean abstractions, rapid prototyping, and systematic benchmarking.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      BioDSA Architecture                        │
├─────────────────────────────────────────────────────────────────┤
│  Base Components:                                               │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐               │
│  │ BaseAgent   │ │ CoderAgent  │ │ ReactAgent  │               │
│  │ (LLM + Exec)│ │ (Code Gen)  │ │ (ReAct)     │               │
│  └─────────────┘ └─────────────┘ └─────────────┘               │
├─────────────────────────────────────────────────────────────────┤
│  Specialized Agents:                                            │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌───────────┐ │
│  │ DSWizard    │ │DeepEvidence │ │TrialMind-SLR│ │ InformGen │ │
│  │ (Planning + │ │(Multi-agent │ │(4-stage SLR)│ │(Doc Gen)  │ │
│  │  Implement) │ │ BFS/DFS)    │ │             │ │           │ │
│  └─────────────┘ └─────────────┘ └─────────────┘ └───────────┘ │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌───────────┐ │
│  │ TrialGPT    │ │ AgentMD     │ │ GeneAgent   │ │VirtualLab │ │
│  │ (Patient    │ │(Clinical    │ │(Gene Set    │ │(Multi-    │ │
│  │  Matching)  │ │ Risk)       │ │ Analysis)   │ │ Agent)    │ │
│  └─────────────┘ └─────────────┘ └─────────────┘ └───────────┘ │
├─────────────────────────────────────────────────────────────────┤
│  Infrastructure:                                                │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐               │
│  │LangGraph    │ │Docker       │ │Memory Graph │               │
│  │Workflows    │ │Sandbox      │ │(BM25 Index) │               │
│  └─────────────┘ └─────────────┘ └─────────────┘               │
├─────────────────────────────────────────────────────────────────┤
│  Knowledge APIs (28 connectors):                                │
│  PubMed, ClinicalTrials.gov, ChEMBL, UniProt, Open Targets,    │
│  cBioPortal, KEGG, Reactome, STRING, HPO, Gene Ontology, etc.  │
└─────────────────────────────────────────────────────────────────┘
```

### Specialized Agents Details

| Agent | Description | Architecture | Performance | Publication |
|-------|-------------|--------------|-------------|-------------|
| **DSWizard** | Two-phase data science agent (planning → implementation) | StateGraph with conditional edges | 0.74 Pass@1 on BioDSBench (2× vanilla) | [Nature BME](https://www.nature.com/articles/s41551-025-01587-2) |
| **DeepEvidence** | Hierarchical multi-agent for deep research | Orchestrator + BFS/DFS subagents | 40% vs 3.3% on HLE-Medicine (10× LLM) | [arXiv:2601.11560](https://arxiv.org/abs/2601.11560) |
| **TrialMind-SLR** | Systematic literature review | 4-stage: search→screen→extract→synthesize | - | [npj Digit. Med.](https://www.nature.com/articles/s41746-025-01840-7) |
| **InformGen** | Clinical document generation | Write-review-revise workflow | - | [JAMIA](https://academic.oup.com/jamia/advance-article-abstract/doi/10.1093/jamia/ocaf174/8304363) |
| **TrialGPT** | Patient-to-trial matching | Retrieval + eligibility scoring | - | [Nature Comm.](https://www.nature.com/articles/s41467-024-53081-z) |
| **AgentMD** | Clinical risk prediction | Large-scale calculator toolkit | - | [Nature Comm.](https://www.nature.com/articles/s41467-025-64430-x) |
| **GeneAgent** | Gene set analysis | Self-verification with DB backing | - | [Nature Methods](https://www.nature.com/articles/s41592-025-02748-6) |
| **Virtual Lab** | AI-powered research discussions | Multi-agent meeting system | - | [Nature](https://www.nature.com/articles/s41586-025-09442-9) |

### Key Features

1. **Modular Base Agent**
   - Multi-provider LLM support (OpenAI, Anthropic, Azure, Google)
   - Sandboxed code execution with Docker
   - Retry logic, timeout handling, token tracking

2. **LangGraph Workflows**
   - Composable state graphs
   - Conditional edges for complex reasoning
   - Built-in checkpointing and persistence

3. **28 Knowledge API Connectors**
   - PubMed, ClinicalTrials.gov, ChEMBL, UniProt
   - Open Targets, cBioPortal, KEGG, Reactome
   - STRING, HPO, Gene Ontology, and more

4. **Docker Sandbox**
   - Python 3.12 with data science libraries
   - Resource monitoring and artifact collection
   - Secure isolated execution

### Publications

```bibtex
@article{wang2026deepevidence,
  title={DeepEvidence: Empowering Biomedical Discovery with Deep Knowledge Graph Research},
  author={Wang, Zifeng and Chen, Zheng and Yang, Ziwei and Wang, Xuan and Jin, Qiao and Peng, Yifan and Lu, Zhiyong and Sun, Jimeng},
  journal={arXiv preprint arXiv:2601.11560},
  year={2026}
}

@article{wang2026reliable,
  title={Making large language models reliable data science programming copilots for biomedical research},
  author={Wang, Zifeng and Danek, Benjamin and Yang, Ziwei and Chen, Zheng and Sun, Jimeng},
  journal={Nature Biomedical Engineering},
  year={2026},
  doi={10.1038/s41551-025-01587-2}
}

@article{wang2025biodsa1k,
  title={BioDSA-1K: Benchmarking Data Science Agents for Biomedical Research},
  author={Wang, Zifeng and Danek, Benjamin and Sun, Jimeng},
  journal={arXiv preprint arXiv:2505.16100},
  year={2025}
}
```

---

## Benchmark Datasets Inventory

### BioDSA Benchmarks (in `reference/BioDSA/benchmarks/`)

| Benchmark | Type | Tasks | Description | HuggingFace |
|-----------|------|-------|-------------|-------------|
| **BioDSA-1K** | Hypothesis Validation | 1,029 | Real biomedical hypothesis validation from published studies | [zifeng-ai/BioDSA-1K](https://huggingface.co/datasets/zifeng-ai/BioDSA-1K) |
| **BioDSBench-Python** | Code Generation | 128 | Python coding for biomedical data analysis | [zifeng-ai/BioDSBench](https://huggingface.co/datasets/zifeng-ai/BioDSBench) |
| **BioDSBench-R** | Code Generation | 165 | R coding for biomedical data analysis | [zifeng-ai/BioDSBench](https://huggingface.co/datasets/zifeng-ai/BioDSBench) |
| **DeepEvidence** | Deep Research | 7 tasks | Evidence synthesis across knowledge graphs | [zifeng-ai/DeepEvidence](https://huggingface.co/datasets/zifeng-ai/DeepEvidence) |
| **HLE-Biomedicine** | Reasoning | 40 | Hard biomedicine questions (Humanity's Last Exam) | - |
| **HLE-Medicine** | Reasoning | 30 | Hard medicine questions (Humanity's Last Exam) | - |
| **LabBench** | Literature QA | 75 | LitQA (25) + DBQA (50) | - |
| **SuperGPQA** | Expert QA | 172 | Expert-level medicine questions | - |
| **TrialPanoramaBench** | Evidence Synthesis | 50 | Clinical trial evidence synthesis | - |
| **TRQA-lit** | Literature QA | 172 | Translational research QA | - |

**Total: ~1,858 tasks across 10 benchmarks**

### DeepEvidence Task Types

| Task | Description |
|------|-------------|
| Target Identification | Identify therapeutic targets for diseases |
| MoA Pathway Reasoning | Reason about drug mechanism of action |
| In Vivo Metabolic Flux Response | Predict metabolic responses in preclinical models |
| Drug Regimen Design | Design drug dosing regimens |
| Surrogate Endpoint Discovery | Identify surrogate endpoints for trials |
| Sample Size Estimation | Estimate required sample sizes |
| Evidence Gap Discovery | Identify gaps in clinical evidence |

### External Benchmarks to Consider

| Benchmark | Source | Tasks | Relevance to Biomate |
|-----------|--------|-------|---------------------|
| **ScienceAgentBench** | CMU/Stanford | 102 | End-to-end scientific discovery |
| **MLAgentBench** | Google | 13 ML tasks | ML model development |
| **DiscoveryBench** | - | - | Multi-step data analysis |
| **BLADE** | - | - | Biomedical literature |

---

## Comparative Analysis of AI Scientist Systems

### Systems Overview

| System | Focus | Architecture | Key Strength | Limitation |
|--------|-------|--------------|--------------|------------|
| **BioDSA** | Biomedical data science | Modular agents + LangGraph | 8 specialized agents, rich benchmarks | Clinical focus, less wet-lab |
| **Biomate** | Bioinformatics workflows | Galaxy integration + Claude | 7000+ Galaxy tools, Nextflow | Newer, fewer benchmarks |
| **ACE Framework** | Context engineering | Generator-Reflector-Curator | Self-improving, 86.9% latency reduction | General purpose |
| **AI Scientist** | Full research cycle | Multi-agent | End-to-end paper writing | Limited domain coverage |
| **SciAgents** | Hypothesis generation | Graph reasoning | Novel hypothesis | No execution |

### Detailed Comparison: BioDSA vs Biomate

| Aspect | BioDSA | Biomate |
|--------|--------|---------|
| **Primary Focus** | Biomedical data analysis (clinical, genomics) | Bioinformatics workflow generation |
| **Tool Ecosystem** | 28 API connectors | 7000+ Galaxy tools + Nextflow |
| **Code Execution** | Docker sandbox | Galaxy job runner |
| **Agent Architecture** | LangGraph state machines | Claude-based single agent |
| **Multi-agent** | Yes (DeepEvidence, VirtualLab) | Planned |
| **Benchmarks** | 10 benchmarks, 1858 tasks | In development |
| **Publications** | Nature BME, Nature Methods, Nature Comm, JAMIA | Planned |
| **Knowledge Bases** | PubMed, cBioPortal, UniProt, etc. | Galaxy tool metadata |
| **Wet-lab Protocols** | Limited | Strong (OpenTrons, lab automation) |
| **Data Types** | Clinical, genomics | Multi-omics (proteomics, metabolomics, genomics) |

### Architecture Comparison

```
BioDSA Agent Flow:
┌────────┐    ┌──────────┐    ┌──────────┐    ┌────────┐
│ User   │───▶│ Planning │───▶│ Implement│───▶│ Docker │
│ Query  │    │ Phase    │    │ Phase    │    │Sandbox │
└────────┘    └──────────┘    └──────────┘    └────────┘
                   │                │
                   ▼                ▼
              [LangGraph]     [Code Gen]

Biomate Agent Flow:
┌────────┐    ┌──────────┐    ┌──────────┐    ┌────────┐
│ User   │───▶│ Workflow │───▶│ Tool     │───▶│ Galaxy │
│ Query  │    │ Planning │    │ Selection│    │ Runner │
└────────┘    └──────────┘    └──────────┘    └────────┘
                   │                │
                   ▼                ▼
              [Claude]        [Nextflow]
```

### Unique Biomate Advantages

1. **Galaxy Integration**: Access to 7000+ curated bioinformatics tools
2. **Nextflow Workflows**: Scalable, reproducible pipeline execution
3. **Multi-omics**: Proteomics, metabolomics, genomics, transcriptomics
4. **Lab Automation**: OpenTrons integration for wet-lab protocols
5. **Workflow Templates**: Pre-built workflows for common analyses

### Gaps to Address

1. **Benchmarking**: Need Biomate-specific benchmarks
2. **Multi-agent**: Implement multi-agent architecture like DeepEvidence
3. **Knowledge APIs**: Add more biomedical database connectors
4. **Self-improvement**: Implement ACE-like context engineering
5. **Publications**: Need peer-reviewed validation

---

## Biomate Positioning and Differentiation

### Value Proposition

**Biomate is the only AI scientist platform that combines:**
1. Natural language workflow generation
2. 7000+ Galaxy bioinformatics tools
3. Scalable Nextflow execution
4. Lab automation (OpenTrons) integration
5. Multi-channel access (Telegram, Slack, web)

### Target Use Cases

| Use Case | BioDSA Coverage | Biomate Advantage |
|----------|-----------------|-------------------|
| RNA-seq analysis | Partial (data analysis) | Full pipeline (QC→align→count→DE) |
| Proteomics workflow | Limited | Strong (MaxQuant, DIA-NN, etc.) |
| Variant calling | Basic | Full (BWA→GATK→annotation) |
| Clinical trials | Strong (TrialGPT, TrialMind) | Limited |
| Literature review | Strong (DeepEvidence) | Basic |
| Lab automation | None | OpenTrons integration |

### Differentiation Matrix

```
                    Tool Coverage
                    Low          High
                ┌────────────┬────────────┐
        Strong  │            │  BIOMATE   │
Knowledge       │  BioDSA    │  (target)  │
Integration     │            │            │
                ├────────────┼────────────┤
        Weak    │  Basic     │  Galaxy    │
                │  Chatbots  │  (manual)  │
                └────────────┴────────────┘
```

---

## Publication Plan

### Proposed Publications

#### Paper 1: Biomate System Paper
**Title**: "Biomate: Natural Language Bioinformatics Workflow Generation with Galaxy Tool Integration"

**Target Journal**: Nature Methods or Bioinformatics

**Key Contributions**:
1. Natural language to executable workflow translation
2. Integration with 7000+ Galaxy tools
3. Nextflow pipeline generation
4. Multi-channel access (Telegram, Slack)

**Benchmarks to Include**:
- Workflow generation accuracy on standard analyses
- Comparison with manual workflow creation time
- Tool selection accuracy

**Timeline**: Q2 2026

---

#### Paper 2: Workflow Benchmark Paper
**Title**: "BiomateWF-Bench: A Comprehensive Benchmark for AI-Driven Bioinformatics Workflow Generation"

**Target Journal**: Genome Biology or Nucleic Acids Research

**Key Contributions**:
1. New benchmark dataset for workflow generation
2. Evaluation metrics for workflow correctness
3. Comparison of different LLM approaches
4. Analysis of failure modes

**Benchmark Categories**:
- RNA-seq workflows (50 tasks)
- Variant calling workflows (50 tasks)
- Proteomics workflows (50 tasks)
- Multi-omics integration (30 tasks)
- Lab automation protocols (20 tasks)

**Timeline**: Q3 2026

---

#### Paper 3: Comparative Evaluation Paper
**Title**: "Benchmarking AI Scientist Systems for Biomedical Research: A Systematic Comparison"

**Target Journal**: Nature Communications or PLOS Computational Biology

**Key Contributions**:
1. Comprehensive comparison of AI scientist systems
2. Cross-benchmark evaluation (BioDSA-1K, BiomateWF-Bench, etc.)
3. Analysis of strengths/weaknesses
4. Recommendations for different use cases

**Systems to Compare**:
- Biomate
- BioDSA (DSWizard, DeepEvidence)
- ACE Framework
- Other AI scientist systems (to be added)

**Timeline**: Q4 2026

---

#### Paper 4: Domain-Specific Application Paper
**Title**: "AI-Driven Proteomics Workflow Optimization: From Raw Data to Biological Insights"

**Target Journal**: Journal of Proteome Research or Molecular & Cellular Proteomics

**Key Contributions**:
1. Specialized proteomics workflow generation
2. DDA vs DIA data type handling
3. Integration with MaxQuant, DIA-NN, MSFragger
4. Case studies on real datasets

**Timeline**: Q1 2027

---

### Publication Timeline

```
2026 Q1: ──────────────────────────────────────────
         │ Collect more AI systems
         │ Build testharness
         │ Create BiomateWF-Bench

2026 Q2: ──────────────────────────────────────────
         │ Submit Paper 1 (System)
         │ Run cross-system benchmarks

2026 Q3: ──────────────────────────────────────────
         │ Submit Paper 2 (Benchmark)
         │ Expand benchmark coverage

2026 Q4: ──────────────────────────────────────────
         │ Submit Paper 3 (Comparative)
         │ Public launch

2027 Q1: ──────────────────────────────────────────
         │ Submit Paper 4 (Application)
         │ Domain-specific papers
```

---

## Testharness Work Plan

### Phase 1: Infrastructure Setup (Weeks 1-2)

1. **Create testharness directory structure**:
   ```
   biomate/testharness/
   ├── benchmarks/
   │   ├── biodsa_1k/           # BioDSA-1K adapter
   │   ├── biodsbench/          # BioDSBench adapter
   │   ├── biomate_wf/          # Biomate workflow bench
   │   └── common/              # Shared utilities
   ├── agents/
   │   ├── biomate/             # Biomate agent wrapper
   │   ├── biodsa/              # BioDSA agent wrapper
   │   └── baselines/           # Baseline models
   ├── evaluation/
   │   ├── metrics.py           # Evaluation metrics
   │   ├── runners.py           # Benchmark runners
   │   └── visualization.py     # Result visualization
   ├── results/
   │   └── ...                  # Benchmark results
   └── config/
       └── ...                  # Configuration files
   ```

2. **Setup evaluation metrics**:
   - Pass@1, Pass@5, Pass@10
   - Exact match, partial match
   - Tool selection accuracy
   - Parameter correctness
   - Workflow executability

### Phase 2: Benchmark Adaptation (Weeks 3-4)

1. **Adapt BioDSA-1K for Biomate**:
   - Convert hypothesis validation tasks to workflow tasks
   - Map to Galaxy tools where applicable

2. **Adapt BioDSBench**:
   - Convert Python/R tasks to Biomate format
   - Create execution environment

3. **Create BiomateWF-Bench**:
   - Collect real-world workflow examples
   - Annotate with ground truth
   - Create test datasets

### Phase 3: Agent Wrappers (Weeks 5-6)

1. **Biomate agent wrapper**:
   ```python
   class BiomateAgent:
       def __init__(self, config):
           self.config = config

       def run(self, query: str) -> WorkflowResult:
           # Call Biomate API
           # Return structured result
           pass
   ```

2. **BioDSA agent wrapper**:
   ```python
   class BioDSAAgent:
       def __init__(self, agent_type: str, config):
           self.agent = self._load_agent(agent_type)

       def run(self, query: str) -> Result:
           return self.agent.go(query)
   ```

### Phase 4: Evaluation Runs (Weeks 7-8)

1. **Run benchmarks**:
   - Biomate on BioDSA-1K (adapted)
   - Biomate on BioDSBench (adapted)
   - Biomate on BiomateWF-Bench
   - BioDSA on BiomateWF-Bench (if applicable)

2. **Analyze results**:
   - Generate comparison tables
   - Identify strengths/weaknesses
   - Document failure modes

### Phase 5: Continuous Integration (Ongoing)

1. **Automated benchmark runs**:
   - Daily/weekly benchmark execution
   - Result tracking over time

2. **Regression testing**:
   - Ensure improvements don't degrade other areas

---

## Next Steps

### Immediate Actions (This Week)

1. [ ] Add BioDSA to .gitignore (large repo)
2. [ ] Create testharness directory structure
3. [ ] Document additional AI scientist systems as provided
4. [ ] Start BiomateWF-Bench task collection

### Short-term (Next 2 Weeks)

1. [ ] Implement benchmark adapters
2. [ ] Create Biomate agent wrapper
3. [ ] Run initial benchmark evaluation
4. [ ] Draft Paper 1 outline

### Medium-term (Next Month)

1. [ ] Complete BiomateWF-Bench (200 tasks)
2. [ ] Run comprehensive evaluations
3. [ ] Start Paper 1 writing
4. [ ] Collect more AI scientist systems for comparison

---

## Appendix A: BioDSA Tool Connectors

Full list of 28 knowledge API connectors in BioDSA:

1. biothings
2. chembl
3. clinical_trials
4. compound
5. diseases
6. drugs
7. ensembl
8. gene_ontology
9. genes
10. gene_set
11. hpo
12. kegg
13. ncbi
14. openfda
15. opengenes
16. opentargets
17. pathway
18. protein
19. proteinatlas
20. pubchem
21. pubmed
22. reactome
23. risk_calculators
24. stringdb
25. targets
26. umls
27. uniprot
28. (README.md)

---

## Appendix B: Previously Analyzed Systems

### ACE Framework (Agentic Context Engineering)
- **Paper**: arXiv:2510.04618
- **Key Innovation**: Generator-Reflector-Curator architecture
- **Performance**: +10.6% on agent tasks, 86.9% latency reduction
- **Full Analysis**: `reference/ACE_FRAMEWORK_ANALYSIS_20251030.md`

### Clawdbot
- **Purpose**: Multi-channel AI assistant
- **Integration**: Telegram, Slack, Discord, WhatsApp
- **Full Analysis**: `reference/CLAWDBOT_SURVEY_AND_INTEGRATION_PLAN_20260127.md`

---

## Appendix C: Benchmark Data Locations

```
reference/BioDSA/benchmarks/
├── BioDSA-1K/
│   └── dataset/biodsa_1k_hypothesis.parquet
├── BioDSBench-Python/
│   └── dataset/python_tasks_with_class.jsonl
├── BioDSBench-R/
│   └── dataset/R_tasks_with_class.jsonl
├── HLE-biomedicine/
│   └── hle_biomedicine_40.csv
├── HLE-medicine/
│   └── hle_medicine_30.csv
├── LabBench/
│   ├── LitQA2_25.csv
│   └── DBQA_50.csv
├── SuperGPQA/
│   └── SuperGPQA-hard-medicine-172.csv
├── TrialPanoramaBench/
│   └── evidence_synthesis_50.csv
└── TRQA-lit/
    ├── TRQA-lit-choice-172.csv
    └── TRQA-lit-choice-coreset.csv
```

---

*Document created: 2026-01-28 14:58*
*To be updated as more AI scientist systems are provided*
