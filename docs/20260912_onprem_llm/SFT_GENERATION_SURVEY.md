# SFT dataset-generation survey (generalizable / paraphrasable / accurate / scenario-aligned)

State-of-the-art SFT/instruction data generation converges on a small set of method families, each addressing one or more of BioMate's four goals. Bootstrapping from an LLM's own generations (Self-Instruct -> Alpaca, Unnatural Instructions) is the foundational template that solves the quantity/diversity/creativity limits of human data, using rephrasing for paraphrase diversity and heuristic filtering for accuracy; instruction evolution (Evol-Instruct/WizardLM, now automated by Auto-Evol-Instruct) raises difficulty and complexity beyond human-authored instructions; and self-synthesis from aligned models (Magpie) generates high-quality data at massive scale with no seeds or prompt engineering, matching official Llama-3-Instruct with far less data. For scenario alignment and paraphrasability, persona-driven synthesis (PersonaHub) and downstream-tailored generation (CodecLM's encode-decode with Self-Rubrics + Contrastive Filtering) steer data toward specific use cases and perspectives rather than generic diversity, while skill-combination sampling (Instruct-SkillMix) is the diversity/difficulty engine. Across all families the dominant empirical lesson is that quality beats quantity (LIMA's 1K > 52K Alpaca; Instruct-SkillMix reaching frontier AlpacaEval with ~4K), and that injecting even 20% low-quality answers measurably degrades models -- so BioMate should prioritize execution/schema-verified, auditor-filtered, persona- and taxonomy-covered data over raw volume.

## Findings

### Self-Instruct is the foundational bootstrapping template for synthetic SFT data: an LLM generates instructions, then inputs, then outputs, then invali
Self-Instruct abstract: 'generates instructions, input, and output samples from a language model, then filters invalid or similar ones before using them to finetune the original model'; and human data is 'often limited in quantity, diversity, and creativity, therefore hindering the generality of the tuned model'. 175 seed tasks -> 52K instructions/82K instances, +33% absolute on Super-NaturalInstructions. Caveat noted in source: ~46% of sampled data may have problems and an external teacher (GPT-3) is used in practice. For BioMate: use this pipeline shape (generate instruction -> ground input in RAG/schema context -> generate output -> filter) as the backbone.
  - https://arxiv.org/abs/2212.10560
  - https://aclanthology.org/2023.acl-long.754/

### Alpaca operationalizes Self-Instruct at low cost: a 52K instruction-following SFT set generated with text-davinci-003 from the 175 human seed tasks, r
Alpaca README: 'built on the data generation pipeline from self-instruct' and 'We used text-davinci-003 to generate the instruction data instead of davinci'; 52K examples fine-tuning a 7B LLaMA. Seeds are the reused Self-Instruct 175 human tasks; bulk is LLM-generated. Relevant to BioMate as the minimal viable template to seed from ~28 intents.
  - https://github.com/tatsu-lab/stanford_alpaca

### Unnatural Instructions shows near-fully-automatic generation plus paraphrase augmentation works: 3 seed examples elicit a 4th, yielding ~64K core trip
Abstract: collect 64,000 examples then 'expanded by prompting the model to rephrase each instruction, creating a total of approximately 240,000 examples'; 'rivals... open-source manually-curated datasets, surpassing... T0++ and Tk-Instruct'. Actual ratio 240,670/68,478 ~= 3.51x ('roughly quadrupling' is a mild overstatement). Directly grounds BioMate's paraphrase-augmentation step: rephrase each instruction/surface-form while preserving input args and outputs to fight format-overfitting. Failure mode: noise (accepted here, but BioMate has verifiable targets so should filter harder).
  - https://arxiv.org/abs/2212.09689

### Evol-Instruct/WizardLM generates data by having an LLM iteratively rewrite seed instructions step-by-step into progressively more complex ones (add-co
Abstract: 'Starting with an initial set of instructions, we use our proposed Evol-Instruct to rewrite them step by step into more complex instructions' and 'instructions from Evol-Instruct are superior to human-created ones'. Seeded from Alpaca, M=4 evolutions via gpt-3.5-turbo. Scope caveat: 'human-created' baseline is specifically ShareGPT, not all manual authoring. For BioMate: evolve base intent instructions to harder multi-tool / ambiguous / constrained variants to broaden difficulty coverage.
  - https://arxiv.org/abs/2304.12244

### Auto-Evol-Instruct removes the hand-crafted evolution rules Evol-Instruct required: an end-to-end framework where an optimizer LLM automatically analy
Abstract: 'evolves instruction datasets using large language models without any human effort'; optimizer LLM 'automatically analyzes and summarizes suitable evolutionary strategies... and iteratively improves the evolving method based on issues exposed during the instruction evolution process'; 'the best method optimized by Auto Evol-Instruct outperforms human-designed methods on various benchmarks, including MT-Bench, AlpacaEval, GSM8K, and HumanEval' (e.g., Mixtral-8x7B MT-Bench 8.09 / AlpacaEval 91.4; GSM8K 82.49 / HumanEval 77.4). EMNLP 2024. For BioMate: let an optimizer LLM tune evolution operators to BioMate's task distribution instead of hand-writing them. Caveat: humans still supply seeds + initial method template.
  - https://arxiv.org/abs/2406.00770
  - https://aclanthology.org/2024.emnlp-main.397/

### Magpie synthesizes alignment data from scratch by feeding an aligned LLM only the pre-query chat template (left-side, up to the user-message slot) so 
Abstract: 'aligned LLMs like Llama-3-Instruct can generate a user query when we input only the left-side templates up to the position reserved for user messages'; '4 million instructions along with their corresponding responses... select 300K high-quality instances'; 'models fine-tuned with Magpie perform comparably to the official Llama-3-8B-Instruct, despite the latter being enhanced with 10 million data points'. ICLR 2025. For BioMate: if a strong aligned base is available, Magpie-style self-synthesis can cheaply produce a large, diverse pool to then filter/verify. Caveats: comparability is benchmark-specific ('in some tasks'); the 10M figure is the authors' characterization of Meta's volume.
  - https://arxiv.org/abs/2406.08464

### CodecLM directly targets scenario/downstream alignment (BioMate's goal #4): an encode-decode framework encodes seed instructions into concise keyword 
Abstract: 'encode seed instructions into metadata, which are concise keywords... to capture the target instruction distribution, and then decode metadata to create tailored instructions'; 'Recent works focus on generating diverse instructions... often neglecting downstream use cases'; 'we further introduce Self-Rubrics and Contrastive Filtering during decoding to tailor data-efficient samples'; framed as 'alignment with different downstream instruction distributions and LLMs'. NAACL 2024 Findings. For BioMate: encode real workflow/tool artifacts into metadata (use case + skills) so synthetic data matches actual BioMate usage distribution, and use Contrastive Filtering to keep examples the 27B model currently fails.
  - https://arxiv.org/pdf/2404.05875
  - https://aclanthology.org/2024.findings-naacl.235/

### Instruct-SkillMix is the diversity/difficulty engine via random skill combination: stage 1 prompts a frontier LLM to extract core instruction-followin
Abstract/Fig 1: '(1) Skill extraction: uses the LLM to extract core "skills"... (2) Data generation: uses the powerful LLM to generate (instruction, response) data that exhibit a randomly chosen pair of these skills. Here, the use of random skill combinations promotes diversity and difficulty'; Fig 1 generalizes to 'combine k random skills'. ICLR 2025. For BioMate: enumerate skills (intent-decompose, route, extract-param, diagnose-error, interpret-results, clarify, refuse) and sample k-combinations to force cross-capability examples.
  - https://arxiv.org/pdf/2408.14774

### PersonaHub provides persona-driven synthesis for scenario coverage and paraphrase diversity: personas act as 'distributed carriers of world knowledge'
Abstract: personas are 'distributed carriers of world knowledge' that 'can tap into almost every perspective encapsulated within the LLM, thereby facilitating the creation of diverse synthetic data at scale for various scenarios'; paper demonstrates synthesizing user instructions and tools/functions across scenarios. For BioMate: condition instruction generation on domain personas to produce multiple realistic surface forms per workflow/tool and broaden scenario coverage. Note: the specific '1 billion personas / 13% of world population' framing was REFUTED (0-3) in verification, so cite the methodology, not that headline number.
  - https://arxiv.org/abs/2406.20094

### Quality dominates quantity, and low-quality answers actively harm: curated small sets can beat large noisy ones (LIMA's 1K > Alpaca 52K at 65B), Instr
Instruct-SkillMix: 'adding 20% low quality answers ("shirkers") causes a noticeable degradation in performance.' LIMA (Zhou et al., NeurIPS 2023, arXiv:2305.11206): 1,000 curated examples on 65B outperform Alpaca-65B's 52K, responses equal-or-preferred vs GPT-4 in 43% of cases. Caveat: the 1K>52K result is LIMA's (blended source), and the specific '4K / $600 / surpasses GPT-4' framing from Instruct-SkillMix was REFUTED (1-2) so avoid that exact headline. For BioMate: invest in verification and auditing over volume; a few thousand execution/schema-verified examples likely beat tens of thousands of unfiltered ones.
  - https://arxiv.org/pdf/2408.14774
  - https://arxiv.org/abs/2305.11206

### Synthesized BioMate SFT pipeline recipe (synthesis of the above families): a coverage-and-verification pipeline is the recommended blueprint -- taxono
Composed from the confirmed families, each contributing one stage: (1) COVERAGE/CURRICULUM: enumerate BioMate's ~28 intents as a taxonomy and extract skills (Instruct-SkillMix), sample k-skill combinations and difficulty tiers, and deliberately include negatives/clarification/refusal examples (motivated by generalizability rationale in Self-Instruct). (2) SCENARIO ALIGNMENT: condition on domain personas (PersonaHub) and encode real workflow/tool artifacts into target-distribution metadata (CodecLM) so data matches actual usage; ground prompts in RAG context + tool schemas for schema-grounded param extraction. (3) DIFFICULTY: evolve instructions (Evol-Instruct) with an optimizer-tuned method (Auto-Evol-Instruct). (4) PARAPHRASABILITY: generate multiple surface forms per instruction AND mult
  - https://arxiv.org/abs/2212.10560
  - https://arxiv.org/abs/2304.12244
  - https://arxiv.org/abs/2406.00770
