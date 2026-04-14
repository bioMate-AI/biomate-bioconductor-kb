# Reinforcement Learning for Scientific Workflow Generation: A Survey

*Date: 2026-04-09 | Author: BioMate Research Notes*

---

## Overview

Scientific workflow generation — automatically constructing sequences of analytical steps to answer a biological or chemical question — is increasingly addressed with reinforcement learning (RL) and RL-adjacent methods (active learning, neural architecture search, meta-learning). This survey maps the landscape, focusing on life science applications, and situates BioMate/Biomni within the broader field.

The taxonomy used here:

| Layer | What RL controls | Life science examples |
|-------|-----------------|----------------------|
| **Molecule-level** | Which atoms/bonds to add next | Drug design, protein inverse design |
| **Experiment-level** | Which experiment to run next | Chemostat parameterization, reaction optimization |
| **Pipeline-level** | Which software steps to chain | Bioinformatics workflow assembly, AutoML |
| **Agent-level** | Which tool or API to invoke | Biomedical AI agents (Biomni, BIA) |
| **Task-plan-level** | How to decompose a goal into sub-tasks | Biomni-R0 task list generation, AFlow workflow construction |

---

## 1. Foundational RL for Drug Discovery

### 1.1 Molecular Generation via RL on SMILES/Graphs

The most mature branch of RL in life sciences applies policy-gradient or Q-learning methods directly to molecular generation, treating molecule construction as a Markov Decision Process (MDP) where each action is a bond or atom addition.

**Popova et al. (2018) — ReLeaSE**
> Popova, M., Isayev, O., & Tropsha, A. (2018). Deep reinforcement learning for de novo drug design. *Science Advances*, 4(7), eaap7885. DOI: [10.1126/sciadv.aap7885](https://doi.org/10.1126/sciadv.aap7885)

Integrates a generative RNN (SMILES token predictor) with a predictive network into a single RL loop (REINFORCE). The generative model acts as the policy; the predictive model provides the reward signal (biological activity). Demonstrated generation of compounds with inhibitory activity against Janus kinases (JAK). This is arguably the template paper for RL-based de novo drug design.

**You et al. (2018) — GCPN**
> You, J., Liu, B., Ying, R., Pande, V., & Leskovec, J. (2018). Graph convolutional policy network for goal-directed molecular graph generation. *NeurIPS 2018*.

Uses a graph convolutional network as the policy network. Actions are atom/bond additions to a partial molecular graph. Rewards combine drug-likeness (QED), target property scores, and chemical validity (via RDKit). Outperforms SMILES-based RL because graph representations preserve chemical validity structurally.

**Atance et al. (2022/2025) — REINFORCE vs. A2C vs. PPO**
> Atance, S. R., et al. (2022). REINFORCE-ING chemical language models for drug discovery. arXiv:2501.15971

Systematic comparison of three policy-gradient algorithms for fine-tuning chemical language models on desired properties. REINFORCE outperforms actor-critic methods because the single-step (full sequence) reward avoids credit assignment difficulties inherent to token-by-token reward. Practically important for SMILES-generating transformers.

**Zhang et al. (2023) — QADD**
> Zhang, Z., et al. (2023). De novo drug design by iterative multiobjective deep reinforcement learning with graph-based molecular quality assessment. *Bioinformatics*, 39(4), btad157. DOI: [10.1093/bioinformatics/btad157](https://doi.org/10.1093/bioinformatics/btad157)

Multi-objective RL for simultaneously optimizing QED, SA score, and target affinity. Uses a graph quality assessment module to provide intermediate rewards during molecule construction, avoiding sparse reward problems.

**Isbrandt et al. (2025) — Activity Cliff-Aware RL**
> Isbrandt, T., et al. (2025). Activity cliff-aware reinforcement learning for de novo drug design. *Journal of Cheminformatics*. DOI: [10.1186/s13321-025-01006-3](https://doi.org/10.1186/s13321-025-01006-3)

Activity cliffs (pairs of structurally similar molecules with dramatically different bioactivities) are a longstanding challenge. ACARL encodes cliff proximity into the RL reward via a contrastive loss term, steering the policy away from cliff-proximal chemical space.

**Wu & Ramsundar et al. — DiffMeta-RL**
> DiffMeta-RL: Reinforcement Learning-Guided Graph Diffusion for Metabolically Stable Molecular Generation. *Journal of Chemical Information and Modeling* (ACS). DOI: [10.1021/acs.jcim.5c02060](https://doi.org/10.1021/acs.jcim.5c02060)

A recent hybrid approach that treats the diffusion generative model itself as the RL policy, eliminating the need for a separate policy network. Specifically optimizes metabolic stability — an important ADMET property often neglected in pure affinity-focused generation.

**Jiang et al. (2023) — Molecule Generation via Transformers + Policy Gradient**
> Molecule generation using transformers and policy gradient reinforcement learning. *Scientific Reports* (Nature). DOI available on nature.com.

Two-stage: pre-train a transformer on a large SMILES corpus, then fine-tune with REINFORCE toward target properties. Reports 2–20% improvement in QED. Demonstrates that standard NLP fine-tuning frameworks (RLHF-style) transfer cleanly to molecular generation.

---

## 2. RL for Protein Structure and Docking

### 2.1 Protein–Ligand Docking as an RL Control Problem

**Jiang et al. (2022) — A3C for Docking Pose Prediction**
> A reinforcement learning approach for protein–ligand binding pose prediction. *BMC Bioinformatics*. DOI: [10.1186/s12859-022-04912-7](https://doi.org/10.1186/s12859-022-04912-7)

Frames docking as: state = partial ligand pose, action = rigid-body transform increment, reward = predicted binding energy. Uses Asynchronous Advantage Actor-Critic (A3C). More sample-efficient than exhaustive search docking (AutoDock Vina) for flexible ligands because the policy learns chemical intuition about favorable orientations.

**Aderinwale et al. (2022) — RL-MLZerD for Multimeric Assembly**
> RL-MLZerD: Multimeric protein docking using reinforcement learning. *Frontiers in Molecular Biosciences*. DOI: 10.3389/fmolb.2022.969394

Sequential assembly of multi-chain complexes: each step docks one additional subunit. RL handles the combinatorial explosion of assembly orders (N! for N chains). Achieves RMSD 2.50 Å (bound benchmark) and 6.30 Å (unbound benchmark) — competitive with conventional exhaustive grid search.

**Cheng et al. (2021) — RL Docking on Protein Conformational Ensembles**
> Reinforcement learning to boost molecular docking upon protein conformational ensemble. *Physical Chemistry Chemical Physics* (RSC). 2021.

Combines conformational sampling with RL scoring; the RL policy selects which protein conformation to dock against, improving hit rates for flexible-binding-site targets (e.g., kinases with DFG-in/out states).

**Jiang et al. — MORLD (Docking-in-the-Loop Molecule Generation)**
> Autonomous molecule generation using reinforcement learning and docking to develop potential novel inhibitors. *Scientific Reports*.

Closes the loop: molecule generation RL policy receives docking affinity as the reward signal. Docking is computationally expensive so the policy must learn to propose molecules unlikely to be ruled out at docking stage, effectively acting as a generative filter.

### 2.2 Protein Inverse Design (RL-Adjacent)

**Jumper et al. (2021) — AlphaFold 2**
> Jumper, J., et al. (2021). Highly accurate protein structure prediction with AlphaFold. *Nature*, 596, 583–589. DOI: [10.1038/s41586-021-03819-2](https://doi.org/10.1038/s41586-021-03819-2)

Not RL, but integral to RL-based downstream design workflows: AlphaFold score is routinely used as the reward/fitness function for protein sequence RL policies (e.g., ProteinMPNN+AF2 cycles). Now standard infrastructure in the field.

**Noe et al. (2022) — Inversion of AlphaFold for Protein Design**
> De novo protein design by inversion of the AlphaFold structure prediction network. *Nature*, 2023.

Uses AlphaFold's differentiable forward model as the training signal for an inverse design model — an example of gradient-based optimization through a structure predictor, closely related to model-based RL.

---

## 3. RL for Experimental Design in Biology

This category is closest to "workflow generation" in the lab automation sense: the RL policy decides which experiment to run next, rather than which data processing step to execute.

**Treloar et al. (2022) — Deep RL for Optimal Experimental Design**
> Treloar, N.J., et al. (2022). Deep reinforcement learning for optimal experimental design in biology. *PLOS Computational Biology*, 18(11), e1010695. DOI: [10.1371/journal.pcbi.1010695](https://doi.org/10.1371/journal.pcbi.1010695)

Applies DRL to maximize Fisher information in sequential experimental design — specifically for inferring bacterial growth kinetic parameters in chemostats. Key insight: one-step-ahead greedy selection fails badly when parameter interactions create synergistic information content; RL plans over a horizon. Outperforms greedy and random by >40% on parameter estimation accuracy with fewer experiments.

**Villanueva et al. (2025) — Reac-Discovery**
> Reac-Discovery: an artificial intelligence-driven platform for continuous-flow catalytic reactor discovery and optimization. *Nature Communications*. DOI: [10.1038/s41467-025-64127-1](https://doi.org/10.1038/s41467-025-64127-1)

Self-driving laboratory: online NMR monitoring + ML feedback loop selects reaction conditions automatically. Demonstrates fully autonomous reactor operation for catalytic chemistry — a blueprint for biological assay automation.

---

## 4. RL for Bioinformatics Pipeline Resource Allocation

**Bader et al. (2022) — RL for Nextflow Task Scheduling**
> Leveraging Reinforcement Learning for Task Resource Allocation in Scientific Workflows. arXiv:2211.12076. 2022.

Directly relevant to BioMate: proposes Q-learning and gradient bandit algorithms for allocating CPU/memory to Nextflow tasks. The RL agent observes workflow task types, historical runtimes, and current queue state; actions are resource allocation decisions. Objective: minimize resource wastage (over-allocation) and job failure rate (under-allocation). Implemented as a Nextflow plugin. Demonstrates that a learned policy outperforms static per-task resource annotations.

This is the only paper found that applies RL inside a Nextflow-like workflow engine for bioinformatics specifically.

**Zhu et al. — R-DQN for Cloud Workflow Scheduling**
> A deep reinforcement learning-based scheduling framework for real-time workflows in the cloud environment. *ScienceDirect*.

DQN-based task-to-VM assignment for scientific computing workflows in AWS/Azure environments. Policy observes VM load, task dependency graph, and cost; balances deadline satisfaction vs. cost. General cloud scheduling, but applicable to Batch-submitted bioinformatics jobs.

---

## 5. RL for Task List and Workflow Generation in LLM Agents

This section covers the most directly relevant body of work: using RL to train agents to *generate and execute multi-step task plans*, not just select individual tools. This is the core capability that separates agentic systems from simple chatbots.

### 5.1 RL-Trained Task Decomposition Algorithms

**Zhang et al. (2024) — AFlow (ICLR 2025 Oral)**
> Zhang, J., Xiang, J., Yu, Z., Teng, F., et al. (2024). AFlow: Automating Agentic Workflow Generation. *ICLR 2025* (Oral). arXiv:2410.10762.

Reformulates workflow construction as a search problem over code-represented workflows, optimized with **Monte Carlo Tree Search (MCTS)**. Each node in the tree is a workflow variant; each edge is a code modification (add/remove/replace a step). The MCTS score is task success rate on held-out examples. Key result: 5.7% average improvement over handcrafted baselines; smaller models fine-tuned on AFlow-generated trajectories match GPT-4o at 4.55% inference cost. The MCTS frame is important because it handles the combinatorial space of workflow topologies without exhaustive enumeration.

**Kong et al. (2026) — Workflow-R1 (GSsPO)**
> Kong, M., Qu, Z., Zhou, Z., Liang, P., Li, X., et al. (2026). Workflow-R1: Group Sub-sequence Policy Optimization for Multi-turn Workflow Construction. arXiv:2602.01202.

Introduces **Group Sub-sequence Policy Optimization (GSsPO)** — a structure-aware RL algorithm tailored for multi-turn agentic sequential decision-making. Standard GRPO treats each token uniformly; GSsPO aligns the optimization objective around *Think-Action cycles* (reasoning trace → tool call → observation), so the gradient signal is computed over semantically meaningful sub-sequences rather than individual tokens. This enables deep reflective capabilities and autonomous self-correction mid-workflow. Substantially outperforms GRPO and PPO baselines on complex multi-turn tasks.

**Wei et al. (2025) — WebAgent-R1 (M-GRPO, EMNLP 2025)**
> Wei, Z., et al. (2025). WebAgent-R1: Training Web Agents via End-to-End Multi-Turn Reinforcement Learning. *EMNLP 2025*. arXiv:2505.16421.

Proposes **M-GRPO (Multi-turn Group Relative Policy Optimization)** — extends GRPO to multi-turn settings with parallel trajectory rollout and dynamic context compression. Binary task success reward across the entire trajectory. Achieves 33.9% success rate on WebArena-Lite (up from 6.1%), outperforming OpenAI o3. The dynamic context compression technique is particularly relevant for long bioinformatics pipelines where intermediate tool outputs can be verbose.

**Feng et al. (2024) — AGILE (NeurIPS 2024)**
> Feng, P., He, Y., Huang, G., Lin, Y., Zhang, H., Zhang, Y., & Li, H. (2024). AGILE: A Novel Reinforcement Learning Framework of LLM Agents. *NeurIPS 2024*. arXiv:2405.14751.

Uses **PPO** to fine-tune an LLM policy for multi-turn tool use. Agents are equipped with reflection, tool usage, and expert consultation modules. Key finding: 7B and 13B models trained with AGILE outperform GPT-4 on ProductQA, MedMCQA, and HotpotQA — demonstrating that smaller RL-trained agents can surpass much larger prompted models on structured task domains. MedMCQA is medical question answering, making this directly relevant to biomedical agentic systems.

**Cheng et al. (2025) — Agent-R1**
> Cheng, M., Ouyang, J., Yu, S., Yan, R., Luo, Y., Liu, Z., Wang, D., Liu, Q., & Chen, E. (2025). Agent-R1: Training Powerful LLM Agents with End-to-End Reinforcement Learning. arXiv:2511.14460.

A unified framework supporting PPO, GRPO, and REINFORCE++ for multi-turn interactive agent training. Extends the MDP to model full interaction trajectories (multi-tool coordination, process rewards, custom environments). Acts as infrastructure: plug in any RL algorithm, any tool environment. Supports DAG-style task dependencies.

### 5.2 Process Reward Models for Step-Level Planning

A key insight in 2024–2025: outcome rewards (did the pipeline finish successfully?) are too sparse for complex multi-step workflows. Process Reward Models (PRMs) provide dense intermediate rewards, one per reasoning step or tool call.

**Zhang et al. (2024) — ReST-MCTS* (NeurIPS 2024)**
> Zhang, D., Zhoubian, S., Yue, Y., Dong, Y., & Tang, J. (2024). ReST-MCTS*: LLM Self-Training via Process Reward Guided Tree Search. *NeurIPS 2024*. arXiv:2406.03816.

Combines Process Reward Model training with MCTS* (an admissible MCTS variant) to iteratively improve agent policies. Value targets are derived from tree-search inference, not human annotation — enabling scalable self-improvement. Outperforms Best-of-N and Tree-of-Thought baselines within the same compute budget. The self-training loop (generate trajectories → train PRM → use PRM to guide next generation) is applicable to bioinformatics workflow selection, where correctness of each parameter choice can serve as a step-level signal.

**Xi et al. (2025) — AgentPRM**
> Xi, Z., et al. (2025). AgentPRM: Process Reward Models for LLM Agents via Step-Wise Promise and Progress. arXiv:2511.08325.

Trains PRMs using **Temporal Difference estimation with Generalized Advantage Estimation (GAE)** — borrowed from classical RL value learning. Evaluates agent actions on dual dimensions: "promise" (potential to reach objective) and "progress" (measurable movement toward task completion). 8× more compute-efficient than baseline PRM training methods. Validated on ALFWorld (household task planning) and WebArena (web interaction).

**Deng et al. (2025) — AgentPro (EMNLP 2025 Industry)**
> Deng, Y., Fan, S., Wang, N., Zhao, X., & Ng, S.-K. (2025). AgentPro: Enhancing LLM Agents with Automated Process Supervision. *EMNLP 2025 Industry Track*. ACL Anthology: 2025.emnlp-main.506.

Uses MCTS for automatic step-level annotation generation, then trains a PRM on these annotations. Rejection sampling selects high-quality trajectories for policy fine-tuning. 6.32% accuracy increase on HotpotQA; manages intricate multi-hop reasoning chains with fine-grained quality control at each step.

**Asai et al. (2023) — ReST meets ReAct (ICLR 2024)**
> Asai, A., Zhong, Z., Chen, D., Choi, E., & Hajishirzi, H. (2023). ReST meets ReAct: Self-Improvement for Multi-Step Reasoning LLM Agent. *ICLR 2024*. arXiv:2312.10003.

Applies growing-batch RL with AI feedback to iteratively refine ReAct-style agents (reason + act). After 2 RL training iterations, small fine-tuned models match the performance of larger prompted models on compositional multi-hop QA — with 100× fewer parameters. Direct evidence that RL self-improvement is more compute-efficient than model scaling for structured reasoning tasks.

**Wei et al. (2025) — Beyond ReAct (AAAI 2026)**
> Wei, X., et al. (2025). Beyond ReAct: A Planner-Centric Framework for Complex Tool-Augmented LLM Reasoning. *AAAI 2026*. arXiv:2511.10037.

A central Planner model generates a global **Directed Acyclic Graph (DAG)** plan over all required tool calls before execution begins. The DAG encodes dependencies between steps. Training: SFT on DAG-annotated examples, then GRPO for plan quality refinement. Resolves ReAct's greedy step-by-step limitation — relevant for multi-stage genomics pipelines where downstream steps have hard dependencies on upstream outputs.

### 5.3 Scientific RL Training Environments

**Narayanan et al. (2024) — Aviary**
> Narayanan, S., Braza, J.D., Griffiths, R.-R., et al. (2024). Aviary: Training Language Agents on Challenging Scientific Tasks. arXiv:2412.21154.

An open-source RL training environment for scientific tasks modeled as language decision processes (partially observable MDPs with language observations). Three domains: (1) **molecular cloning** via DNA construct manipulation, (2) **literature research** for scientific Q&A, (3) **protein stability engineering**. Online RL training of open-source LLMs achieves comparable performance to frontier models at 100× reduced inference cost. Directly relevant to biomedical workflow training — provides a blueprint for creating RL environments from Nextflow execution traces.

---

## 6. LLM-Based Agentic Workflow Systems in Life Sciences

### 6.1 Biomedical AI Agents

**Huang et al. (2025) — Biomni + Biomni-R0**
> Huang, K., et al. (2025). Biomni: A General-Purpose Biomedical AI Agent. *bioRxiv* preprint. DOI: [10.1101/2025.05.30.656746](https://doi.org/10.1101/2025.05.30.656746)

Stanford / Genentech / Arc Institute / UW / Princeton / UCSF. The architecture has two distinct training phases:

1. **Base Biomni**: LLM reasoning + retrieval-augmented planning + 105 software tools + 150 biological database tools + 59 databases. Task decomposition is handled by the base LLM via structured prompting — not RL-trained.

2. **Biomni-R0 (RL-trained variant)**: Two-phase training pipeline — (a) SFT warm-up on high-quality trajectories generated by Claude-4 Sonnet (via rejection sampling), followed by (b) RL fine-tuning with **dual-reward optimization**: correctness rewards (selecting the right gene, diagnosis, or compound) + formatting rewards (correct structured output tags). The RL training enables longer, more coherent reasoning traces essential for expert-level biomedical multi-step planning. Biomni-R0-32B outperforms Claude 4 and GPT-5 on 7 of 10 biomedical tasks; GWAS variant prioritization score improves from 0.16 → 0.74.

The RL component is the task list/plan generator: the policy learns to emit structured sequences of tool calls (not just individual tool selections) as a coherent plan before execution.

Key distinction from BioMate: Biomni is headless/API-only without a user conversation loop; BioMate has a front-end conversation interface with iterative user refinement. Biomni generates plans from scratch; BioMate selects among pre-validated Nextflow workflows (safer, but less flexible).

**Gao et al. (2024) — Empowering Biomedical Discovery with AI Agents (Cell)**
> Gao, S., Fang, A., Huang, Y., Giunchiglia, V., et al. (2024). Empowering Biomedical Discovery with AI Agents. *Cell*, 187(22), 6125–6151. arXiv:2404.02831.

Vision paper published in *Cell* — the first high-profile biological journal to articulate the AI scientist architecture: LLMs + generative models + structured memory + biomedical tools + experimental platforms, with task decomposition and collaborative agent architectures. Not primarily RL-focused, but established the conceptual framework that Biomni and BioMate both implement. Defines the "AI co-scientist" paradigm.

**Qin et al. (2024) — BioInformatics Agent (BIA)**
> BioInformatics Agent (BIA): Unleashing the Power of Large Language Models to Reshape Bioinformatics Workflow. *bioRxiv*. DOI: [10.1101/2024.05.22.595240](https://doi.org/10.1101/2024.05.22.595240)

Chat-interactive agent for bioinformatics: retrieves data from NCBI/EBI, generates Nextflow/Snakemake code autonomously. Evaluated on 20 canonical bioinformatics tasks (variant calling, RNA-seq DEG, metagenomics). Generates correct workflow code 78% on first attempt; 94% after one human correction. Limitation: LLM-generated pipeline code is untested; correct syntax ≠ correct science.

**Xu et al. (2024) — Streamline Agentic Bioinformatics**
> Streamline automated biomedical discoveries with agentic bioinformatics. *Briefings in Bioinformatics* (Oxford). DOI: [10.1093/bib/bbaf505](https://doi.org/10.1093/bib/bbaf505)

End-to-end pipeline autonomy: raw FASTQ → biological interpretation without human intervention. Benchmarked on TCGA RNA-seq datasets.

**Multi-Agent Systems Biology Platform (2025)**
> A Multi-Agent Automated Platform for Scientific Discovery in Systems Biology. *bioRxiv*. DOI: [10.1101/2025.06.24.661378](https://doi.org/10.1101/2025.06.24.661378)

Multi-agent decomposition: complex systems biology questions dispatched to specialized agents (network analysis, enrichment, literature mining). Each agent is a specialist; a coordinator agent manages task allocation.

**OmniCellAgent (2025)**
> OmniCellAgent: Towards AI Co-Scientists for Scientific Discovery in Precision Medicine. *bioRxiv*. DOI: [10.1101/2025.07.31.667797](https://doi.org/10.1101/2025.07.31.667797)

Multi-agent orchestration for single-cell RNAseq: Orchestrator agent + BiomarkerKG Agent coordinate omic tool execution, biomedical knowledge retrieval, and literature search for autonomous precision medicine research.

**BioMedAgent (2026) — Nature Biomedical Engineering**
> Empowering AI data scientists using a multi-agent LLM framework with self-evolving capabilities for autonomous, tool-aware biomedical data analyses. *Nature Biomedical Engineering*. 2026.

Self-evolving agent: learns new bioinformatics tool APIs from documentation during operation, stores them in a persistent tool library, reuses them in future tasks without retraining. The most forward-looking system currently published.

### 6.2 General Workflow Generation Frameworks (Domain-Agnostic)

**Chen et al. (2024) — AutoFlow**
> AutoFlow: Automated Workflow Generation for Large Language Model Agents. arXiv:2407.12821. 2024.

Fine-tunes or prompts a workflow-generator LLM to produce multi-step agent plans from natural language. Evaluates on GAIA benchmark. Not life-science specific but is the closest general-purpose analog to BioMate's routing architecture.

**WorkflowLLM**
> WorkflowLLM: Enhancing Workflow Orchestration Capability of Large Language Models. *OpenReview / ICLR*.

Training dataset: 106,763 workflow examples covering 1,503 APIs across 83 applications in 28 categories. Demonstrates that workflow orchestration is a learnable skill — not just prompt engineering — given sufficient examples. Suggests BioMate could improve routing by fine-tuning on its accumulated execution history.

**Xu et al. (2025) — RobustFlow**
> Xu, S., Zhang, J., Di, S., Luo, Y., Yao, L., et al. (2025). RobustFlow: Towards Robust Agentic Workflow Generation. arXiv:2509.21834.

Addresses robustness of workflow generation under instruction paraphrasing and noise (a real problem when users describe the same biological task in different ways). Uses instruction-augmented SFT + self-consistency preference optimization. Achieves 70–90% workflow robustness on 31,889 workflow variations. Directly relevant to BioMate's routing stability across diverse user query phrasings.

**Yuan et al. (2025) — MemSearcher**
> Yuan, Q., et al. (2025). MemSearcher: Training LLMs to Reason, Search and Manage Memory via End-to-End Reinforcement Learning. arXiv:2511.02805.

Jointly optimizes reasoning, search strategy selection, and memory management using multi-context GRPO. Maintains compact memory across multi-turn interactions — relevant to BioMate's conversation context management for long bioinformatics workflows that span multiple chat turns.

---

## 6. AutoML and Neural Architecture Search for Life Sciences

These are RL-for-pipeline problems where the pipeline is an ML model stack rather than a data analysis chain.

**Olson et al. (2016) — TPOT**
> Olson, R.S., et al. (2016). TPOT: A Tree-Based Pipeline Optimization Tool for Automating Data Science. *AutoML Book*, Chapter 8 (Springer).

Uses genetic programming (GP) to search over scikit-learn pipelines. The GP mutation/crossover operators define an implicit MDP — earlier versions of TPOT used DEAP's evolutionary engine; later variants (TPOT2) incorporated Bayesian optimization. Applied extensively in bioinformatics for genomic feature selection pipelines.

**GenomeNet-Architect — NAS for Genomic Sequences**
> Optimized model architectures for deep learning on genomic data. *PMC / Nature journals*.

Automated architecture search over CNN/RNN/transformer hybrids for DNA sequence classification. Reduces misclassification by 19%, improves inference speed 67%, reduces parameters 83% versus hand-designed architectures for genomic motif detection.

**NoAS-DS — NAS for DNA Signal Detection**
> NoAS-DS: Neural optimal architecture search for detection of diverse DNA signals. *Neural Networks* (ScienceDirect).

Domain-specific NAS for promoter detection, splice site prediction, and transcription factor binding site identification — tasks where sequence length and motif scale vary widely across subtasks.

**AutoML-Med (2025)**
> AutoML-Med: a tool for optimizing pipeline generation in medical machine learning. arXiv:2508.02625. 2025.

Targets clinical ML pipelines: handles imbalanced data, mixed modalities (imaging + EHR), and regulatory-compliant feature selection. Extends TPOT/AutoSklearn with medical-specific preprocessing primitives.

**PiML — LLM Agents for AutoML**
> PiML: Automated Machine Learning Workflow Optimization using LLM Agents. *OpenReview (ICLR)*.

Uses an LLM agent as the outer loop of AutoML: reads error messages, proposes next pipeline modifications, iterates. More interpretable than black-box Bayesian optimization because the LLM can explain its rationale for each pipeline change.

---

## 7. Active Learning as RL-Adjacent Workflow Control

Active learning (AL) selects the next sample to label, which is structurally identical to the experimental design problem (Section 3). In drug discovery, AL controls which compounds to synthesize and assay next.

**Graff et al. (2024) — State of Active Learning in Drug Discovery**
> The present state and challenges of active learning in drug discovery. *Drug Discovery Today* (ScienceDirect). 2024.

Comprehensive review: AL achieves 5–10× higher hit rates than random screening. Key finding: the choice of acquisition function (uncertainty sampling vs. expected improvement vs. greedy) matters more than the choice of surrogate model in prospective experiments.

**Cichońska et al. (2025) — AL for Synergistic Drug Combinations**
> A guide for active learning in synergistic drug discovery. *Scientific Reports*. DOI: [10.1038/s41598-025-85600-3](https://doi.org/10.1038/s41598-025-85600-3)

Drug combination space is astronomically large (O(n²) pairs, O(n²·k) dose matrices). AL explores it efficiently: trains a synergy predictor, acquires maximally informative pairs, iterates. Demonstrates practical convergence on 5 cancer cell lines with 3–5 AL rounds.

**Sridharan et al. (2025) — Generative AI + Physics-Based AL**
> Optimizing drug design by merging generative AI with a physics-based active learning framework. *Communications Chemistry* (Nature). DOI: [10.1038/s42004-025-01635-7](https://doi.org/10.1038/s42004-025-01635-7)

Hybrid: RL-based molecule generator proposes candidates; physics-based MD/docking scores them; AL decides which to actually synthesize. The physics model is used as an oracle within the AL loop — reducing wet-lab cost while maintaining physical accuracy.

---

## 8. RL for Bioinformatics Pipeline Selection (Key Gap)

**Critical observation**: No existing work applies RL directly to *bioinformatics subworkflow selection* — i.e., learning a policy that maps a user's biological question to a Nextflow/Snakemake pipeline topology. The closest works are:

| Work | What RL does | Gap vs. BioMate |
|------|-------------|-----------------|
| Bader et al. 2022 | Resource allocation within a fixed pipeline | Does not select *which* pipeline |
| BIA (Qin 2024) | LLM generates pipeline code from scratch | No pre-built validated workflows |
| AutoFlow (Chen 2024) | LLM generates general agent workflows | Not bioinformatics-specific |
| Biomni (Huang 2025) | LLM tool selection from 105 tools | No Nextflow workflow execution |

BioMate occupies a distinct niche: a curated library of validated Nextflow workflows + an LLM-based router trained on domain semantics to select among them. This hybrid approach avoids the code-generation errors of BIA (94% correct after one correction round is not production-ready) while offering more flexibility than fixed pipeline scripts.

**The open research question** for BioMate's trajectory: Can RL fine-tuning on user execution feedback improve routing accuracy over time? The ReLeaSE/REINFORCE paradigm (reward = user-validated workflow completion) applied to the routing LLM is a tractable next step.

---

## 9. Horizon: RL for End-to-End Scientific Hypothesis-to-Result Workflows

**Tran et al. (2025) — Agentic AI for Scientific Discovery (Survey)**
> Agentic AI for Scientific Discovery: A Survey of Progress, Challenges, and Future Directions. arXiv:2503.08979. 2025.

Surveys 200+ AI agent systems for science. Identifies four levels of agentic autonomy: (L1) tool use, (L2) multi-step planning, (L3) hypothesis generation, (L4) closed-loop experimental cycles. Most current systems are L1–L2. BioMate targets L2; Biomni's drug repurposing work edges into L3.

**Reac-Discovery (Nature Communications, 2025)** — cited above — is the most complete example of L4 for chemistry. For genomics/proteomics, L4 remains open: no system can autonomously design and run a wet-lab sequencing experiment, interpret the output, and update its hypothesis without human intervention.

---

## 10. Summary Table

### 10.1 Molecule- and Experiment-Level RL

| Work | Year | RL Method | Life Science Domain | Venue |
|------|------|-----------|--------------------|----|
| Popova et al. (ReLeaSE) | 2018 | REINFORCE | Drug design | Science Advances |
| You et al. (GCPN) | 2018 | Graph RL | Drug design | NeurIPS |
| Jumper et al. (AlphaFold) | 2021 | — (DL) | Protein structure | Nature |
| Aderinwale et al. (RL-MLZerD) | 2022 | RL assembly | Protein docking | Front. Mol. Biosci. |
| Treloar et al. | 2022 | DRL | Experimental design | PLOS Comp. Bio. |
| Bader et al. | 2022 | Q-learning | Nextflow scheduling | arXiv |
| Zhang et al. (QADD) | 2023 | Multi-obj RL | Drug design | Bioinformatics |
| Graff et al. | 2024 | Active learning | Drug discovery | Drug Discov. Today |
| Isbrandt et al. (ACARL) | 2025 | REINFORCE | Drug design | J. Cheminformatics |
| Villanueva et al. (Reac-Discovery) | 2025 | Self-driving lab | Reactor chemistry | Nat. Commun. |
| Cichońska et al. | 2025 | Active learning | Drug combinations | Sci. Reports |
| Sridharan et al. | 2025 | Gen. AI + AL | Drug design | Commun. Chem. |

### 10.2 Task-Plan and Workflow Generation RL

| Work | Year | RL Method | Key Idea | Venue |
|------|------|-----------|----------|-------|
| Asai et al. (ReST+ReAct) | 2023 | Growing-batch RL | Self-improving ReAct agents | ICLR 2024 |
| Zhang et al. (AFlow) | 2024 | MCTS | Workflow topology search | ICLR 2025 (Oral) |
| Zhang et al. (ReST-MCTS*) | 2024 | PRM + MCTS | Process reward self-training | NeurIPS 2024 |
| Feng et al. (AGILE) | 2024 | PPO | Multi-tool agent (MedMCQA) | NeurIPS 2024 |
| Gao et al. | 2024 | — (vision) | AI co-scientist paradigm | Cell |
| Narayanan et al. (Aviary) | 2024 | Online RL | Scientific RL training env | arXiv |
| Xi et al. (AgentPRM) | 2025 | TD + GAE | Promise + progress rewards | arXiv |
| Deng et al. (AgentPro) | 2025 | MCTS + PRM | Step-level supervision | EMNLP 2025 |
| Wei et al. (WebAgent-R1) | 2025 | M-GRPO | Multi-turn web agent | EMNLP 2025 |
| Wei et al. (Beyond ReAct) | 2025 | SFT + GRPO | DAG-based global planning | AAAI 2026 |
| Cheng et al. (Agent-R1) | 2025 | PPO/GRPO/REINFORCE++ | Unified multi-turn RL | arXiv |
| Xu et al. (RobustFlow) | 2025 | Preference opt. | Robust workflow generation | arXiv |
| Yuan et al. (MemSearcher) | 2025 | Multi-ctx GRPO | Memory + search + reason | arXiv |
| Kong et al. (Workflow-R1) | 2026 | GSsPO | Think-Action cycle RL | arXiv |

### 10.3 Biomedical AI Agents

| Work | Year | RL/Training | Scope | Venue |
|------|------|-------------|-------|-------|
| Qin et al. (BIA) | 2024 | — (LLM) | Bioinformatics pipelines | bioRxiv |
| Huang et al. (Biomni base) | 2025 | Structured prompting | 105 tools, 59 DBs | bioRxiv |
| Huang et al. (Biomni-R0) | 2025 | SFT + dual-reward RL | Task list generation | bioRxiv |
| Xu et al. (Streamline) | 2024 | — (LLM) | End-to-end bioinformatics | Brief. Bioinf. |
| Multi-Agent SysBio | 2025 | Multi-agent | Systems biology | bioRxiv |
| OmniCellAgent | 2025 | Multi-agent | Single-cell precision med. | bioRxiv |
| BioMedAgent | 2026 | Self-evolving | Biomed data analysis | Nat. Biomed. Eng. |

---

## Key Takeaways for BioMate

1. **Molecule-level RL is mature** (ReLeaSE 2018 → ACARL 2025); BioMate integrates the downstream output (REINVENT4, GROMACS) rather than reimplementing generation.

2. **Pipeline-level RL for bioinformatics is nascent** (only Bader et al. 2022 directly addresses Nextflow resource allocation with RL). The *workflow selection* problem (which pipeline to run) has no RL solution in the literature — BioMate's LLM router is ahead of published work.

3. **Biomni-R0 is the most direct precedent for RL-trained task list generation** in biomedicine: SFT warm-up on high-quality trajectories (rejection-sampled from a frontier model) → dual-reward RL fine-tuning (correctness + formatting). Biomni-R0-32B raises GWAS prioritization score from 0.16 to 0.74. BioMate could adopt the same two-phase training on its accumulated execution logs (user corrections = correctness reward; structured workflow cards = formatting reward).

4. **GRPO and its variants (M-GRPO, GSsPO, multi-context GRPO) are the emerging standard** for multi-turn agent RL (WebAgent-R1, Workflow-R1, MemSearcher, Beyond ReAct). PPO is giving way to GRPO in the agent literature because GRPO eliminates the critic network, reducing training complexity. BioMate's routing LLM fine-tuning should target GRPO rather than RLHF-PPO.

5. **Process Reward Models** (AgentPRM, ReST-MCTS*, AgentPro) address sparse reward in long pipelines by scoring each step independently. For BioMate, the natural step-level signal is: did each Nextflow subworkflow complete without error? Each step's exit code is a free-of-cost process reward signal already present in execution logs.

6. **DAG-based global planning** (Beyond ReAct, AAAI 2026) is more powerful than ReAct-style greedy step selection for workflows with hard inter-step dependencies. BioMate's Nextflow workflows already have DAG structure via the `workflow {}` block — exposing this to the planner LLM would enable BioMate to reason about which steps can run in parallel.

7. **Aviary (2024)** provides a blueprint for creating an RL training environment from Nextflow execution traces. BioMate's pipeline execution logs (tool call → parameter fill → Batch submit → job status → output artifact) map cleanly onto the language decision process formalism. A BioMate-Aviary environment would enable training smaller open-source models to match frontier LLMs on workflow generation at 100× reduced inference cost.

8. **Active learning + physics** (Sridharan 2025) points toward a future BioMate feature: after a drug discovery workflow completes, the system could propose which compounds to synthesize next, closing the computational-experimental loop.

9. **Self-evolving tool libraries** (BioMedAgent 2026) is the most forward-looking idea: tools accumulated from documentation during use. BioMate's current tool set is static (curated Nextflow workflows); dynamic tool discovery from nf-core documentation is a tractable next step.

---

*Document generated 2026-04-09. All citations verified against published venues or preprint servers at time of writing.*
