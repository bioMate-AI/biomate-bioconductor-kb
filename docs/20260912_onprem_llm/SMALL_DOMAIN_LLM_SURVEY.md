# Small Domain-Specialized LLMs — Survey, Baselines & Lessons

_Deep-research survey (2023–2026), 112 agents, adversarially verified. Purpose: learn from + benchmark against existing work; we build our own (grounded Qwen+LoRA)._

## Executive summary

For BioMate's structured, retrieval-grounded agentic tasks (intent classification, routing over a 4,200-workflow catalog, schema-grounded parameter extraction, log/error diagnosis, parsed-output interpretation) plus on-demand figure interpretation, the evidence favors fine-tuning a strong general instruct model (e.g. Qwen2.5 ~27B, natively multimodal) with LoRA on grounded data over starting from a small biomedical specialist. Multiple 2024-2026 primary sources show that biomedical domain pretraining/fine-tuning frequently fails to beat the generalist base on unseen or contamination-controlled medical data, with reported gains often reflecting benchmark adaptation rather than real capability; for retrieval-grounded (open-book) tasks where knowledge is supplied in-context, the deciding factors are instruction-following, context-handling, tool-use quality, and multimodal support rather than parametric closed-book domain knowledge. Notably, a Qwen-2.5-based biomedical specialist already exists (Aloe Beta 7B/72B), providing a direct comparison point rather than a hypothetical. The genomics/single-cell foundation models (Evo2, DNABERT-2, scGPT, Geneformer, scFoundation) are explicitly NOT chat/agentic LLMs — they are sequence/embedding models with no natural-language interface — so they belong as tools the agent calls, not as the agent's reasoning core, and current genomic LMs are not clinically ready. Licensing is the main practical caveat: Llama-3-based OpenBioLLM (Meta Llama community license) and fully-open Meditron variants (permissive) are on-prem/commercial deployable, whereas Gemma-3-based and some CC-restricted models carry constraints.

## Verified findings

### 1. Biomedical domain specialization frequently fails to beat the generalist base model on unseen/contamination-controlled medical data; reported gains often reflect contamination or benchmark adaptation, not real clinical capability — a core argument against starting from a biomedical specialist for BioMate.
- **Confidence:** high  |  **Votes:** 3-0 (plus independent corroboration)
- Fully Open Meditron paper: 'Prior work shows that biomedical specialists frequently fail to outperform their generalist bases on unseen medical data, suggesting reported gains may reflect contamination or benchmark adaptation rather than clinical capability.' Corroborated by arXiv:2408.13833 (OpenBioLLM-8B scored 30% on NEJM cases vs Llama-3-8B-Instruct 64.3%) and Nature Medicine 'General-purpose LLMs outperform specialized clinical AI tools on medical benchmarks.'
  - https://arxiv.org/pdf/2605.16215
  - https://arxiv.org/abs/2408.13833
  - https://www.nature.com/articles/s41591-026-04431-5

### 2. A Qwen-2.5-based open medical LLM already exists (Aloe Beta 7B/72B), giving BioMate a directly comparable data point for the Qwen-base decision; it was built via SFT + model merging (DARE_TIES) + DPO on Qwen2.5-Instruct, not pure LoRA.
- **Confidence:** high  |  **Votes:** 3-0
- Aloe recipe paper: 'Building on top of strong base models like Llama 3.1 and Qwen 2.5, Aloe Beta uses a custom dataset to enhance public data with synthetic Chain of Thought examples.' Released artifacts HPAI-BSC/Qwen2.5-Aloe-Beta-7B and -72B confirm the Qwen-based specialists are real. Note: Aloe Beta license was refuted as 'permissive' — deployability must be checked per variant.
  - https://arxiv.org/pdf/2505.04388
  - https://huggingface.co/HPAI-BSC/Qwen2.5-Aloe-Beta-7B

### 3. BioMistral (7B) is built on Mistral via continued/domain-adaptive pretraining on PubMed Central — i.e. domain pretraining on top of an existing checkpoint, not instruction-tuning from scratch. Its license is NOT CC0.
- **Confidence:** high  |  **Votes:** 3-0 (base/method); CC0 licensing refuted 0-3
- arXiv abstract: 'Mistral as its foundation model and further pre-trained on PubMed Central.' The specific base was Mistral-7B-Instruct-v0.1. The claim that BioMistral is CC0-licensed was explicitly REFUTED (vote 0-3), so commercial/on-prem terms cannot be assumed permissive.
  - https://arxiv.org/abs/2402.10373
  - https://huggingface.co/BioMistral/BioMistral-7B

### 4. Llama3-OpenBioLLM (8B/70B) is distributed under Meta's Llama 3 Community License, which permits commercial and on-prem use subject to Meta's terms; the 8B variant is trivially deployable and QLoRA-fine-tunable on a single 48GB GPU.
- **Confidence:** high  |  **Votes:** 3-0 (license/48GB); Instruct-base derivation refuted 0-3
- 8B card lists license 'llama3', fine-tuned from Meta-Llama-3-8B. Llama 3 community license permits commercial/on-prem (with >700M MAU clause, AUP, no-using-outputs-to-train-other-LLMs). 8B needs ~18GB FP16 / ~4.4GB INT4; QLoRA of 8B fits ~23GB on a 48GB A6000. NOTE: the specific claim that OpenBioLLM 8B/70B derive from the -Instruct bases was REFUTED (0-3) — they derive from base Meta-Llama-3, not Instruct.
  - https://huggingface.co/aaditya/Llama3-OpenBioLLM-70B
  - https://huggingface.co/aaditya/Llama3-OpenBioLLM-8B
  - https://arxiv.org/abs/2408.10715

### 5. Fully Open Meditron: three variants (Apertus-70B, OLMo-2-32B, EuroLLM-22B MeditronFO) carry a permissive open license (O) across all openness dimensions, while Gemma-3-27B-MeditronFO carries an inherited community license (IC). Gemma's terms restrict medical/health professional use, constraining commercial on-prem clinical deployment.
- **Confidence:** high  |  **Votes:** 3-0 (license classification); roster/sizes 1-2
- Paper Table 1: Apertus-70B/OLMo-2-32B/EuroLLM-22B MeditronFO = O (permissive open); Gemma-3-27B-MeditronFO = IC (inherited community license). Legend: 'O = permissive open license; IC = inherited C(ommunity) license.' Gemma Terms carry a Prohibited Use Policy restricting medical/health professional use plus unilateral termination. NOTE: the full five-model roster/size enumeration claim was split-voted (1-2), so treat exact size list cautiously.
  - https://arxiv.org/pdf/2605.16215

### 6. Authors of the 2025 BioASQ open-weight study explicitly frame small, self-deployable open-weight models as the practical/compelling choice for on-premise deployment with highly restricted medical data.
- **Confidence:** high  |  **Votes:** 3-0 (framing); competitive-with-proprietary claim 1-2
- Conclusion: 'This is particularly relevant for applications involving highly restricted data that require on-premise deployment, a common scenario with medical data. In such contexts, smaller self-deployable models offer a compelling and practical alternative.' CAVEAT: the paper's empirical strength centers on ENSEMBLES and includes large open models (DeepSeek-V3); the specific claim that <=14B models match/surpass proprietary models was split-voted (1-2).
  - https://arxiv.org/pdf/2509.18843

### 7. For retrieval-grounded (in-context/RAG) knowledge tasks, in-context retrieval tends to beat parametric domain fine-tuning, but this specific evidence is only medium-confidence (split votes).
- **Confidence:** medium  |  **Votes:** 1-2 on the specific RAG>FT quantitative claims
- MDPI study reported RAG and hybrid FT+RAG outperformed fine-tuning alone across small instruct models (e.g. Llama-3.1-8B RAG BLEU 0.163 vs FT 0.025), and BioASQ framing that context quality is the critical factor. HOWEVER these specific claims were split-voted (1-2), so the 'RAG beats domain FT' conclusion for BioMate's open-book tasks is directionally supported but not firmly established. Combined with the high-confidence 'specialists don't beat generalists' finding, it still favors general-base + LoRA + retrieval.
  - https://www.mdpi.com/2306-5354/12/7/687
  - https://arxiv.org/pdf/2509.18843

### 8. Single-cell foundation models (scGPT, Geneformer, scFoundation, scBERT) are NOT chat/NL LLMs — they learn cell/gene embeddings from scRNA-seq via masked-gene or rank-based reconstruction. Natural-language coupling requires a separate 'Text-Bridge' class (Cell2Sentence, GenePT, scELMo).
- **Confidence:** high  |  **Votes:** 3-0
- LLM4Cell survey: foundation models 'learn transferable cell and gene embeddings directly from large-scale scRNA-seq' using 'masked-gene or rank-based reconstruction'; a distinct 'Text-Bridge' category (Cell2Sentence, Cell2Text, GenePT, scELMo) couples embeddings to language. Implication for BioMate: these are TOOLS the agent calls, not the agent reasoning core.
  - https://arxiv.org/pdf/2510.07793

### 9. Agentic single-cell frameworks currently lack standardized benchmarks for reasoning fidelity and depend on the reliability of the underlying general LLM; reasoning accuracy/safety/reproducibility are not yet reliably measurable.
- **Confidence:** medium  |  **Votes:** 2-1
- LLM4Cell: 'lack standardized benchmarks for reasoning fidelity and rely on underlying LLM reliability.' The dedicated benchmark arXiv:2508.13201 (Genome Biology 2026) confirms plan/reasoning scores had no significant correlation with task completion quality and lists reasoning-trace analysis as future work. Split vote (2-1) reflects the emergence of that benchmarking platform softening the absolute 'lack standardized benchmarks' phrasing.
  - https://arxiv.org/pdf/2510.07793
  - https://arxiv.org/abs/2508.13201

### 10. Genomic language models (gLMs) report success on simplistic benchmarks that fail to capture genomic regulation, and simple baselines (token-frequency / one-hot) match them on many tasks — undermining claims of genuine genome 'understanding'; gLMs are not yet clinically ready.
- **Confidence:** high  |  **Votes:** 3-0
- npj Digital Medicine: 'Many gLMs report success on simple benchmarking tasks that fail to capture the complexity of genomic regulation'; 'even a simple model focusing solely on token frequencies performs well'; 'Most current evaluation strategies...fail to differentiate...true genome comprehension or statistical recapitulation.' Genome Biology 2025 shows gLM representations 'provided little to no advantage over standard one-hot encoded sequences' for regulatory activity.
  - https://www.nature.com/articles/s41746-025-01603-4
  - https://doi.org/10.1186/s13059-025-03674-8

### 11. Evo 2 is a DNA/RNA/protein sequence foundation model (NOT a chat LLM), released in 40B/20B/7B/1B variants on the StripedHyena 2 architecture (Savanna pretraining framework).
- **Confidence:** high  |  **Votes:** 3-0
- Arc Institute: 'Model Sizes: 40B, 20B, 7B, and 1B parameter variants available... Base Architecture: StripedHyena 2, with pretraining via Savanna framework.' Described as a genomic foundation model across DNA/RNA/proteins at single-nucleotide resolution. 1B has 8K context vs 1M for larger variants.
  - https://arcinstitute.org/tools/evo
  - https://github.com/arcinstitute/evo2

### 12. Evo 2 exposes NO natural-language, chat, or agentic interface — it operates via forward-pass scoring, embedding extraction, and sequence generation; downstream use requires feeding embeddings into separate classifiers (e.g. a feed-forward NN for pathogenicity). It cannot serve as an agentic assistant directly.
- **Confidence:** high  |  **Votes:** 3-0
- Arc: 'No natural language, chat, or agentic interface... forward pass scoring, embedding extraction, and generation capabilities—not conversational interaction.' bioRxiv usage example: 'We extracted embeddings from the layer of final block of the Evo2 1B model... used as inputs to train a classification model that consists of a feed-forward neural network with one hidden layer.' Reinforces that genomics FMs are agent tools, not agent cores.
  - https://arcinstitute.org/tools/evo
  - https://www.biorxiv.org/content/10.1101/2025.09.10.675279v1.full.pdf
