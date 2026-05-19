# Domain-specific LLMs for biology: post-train, fine-tune, or train from scratch? Where we did, and where we didn't.

*An honest look at the empirical evidence, what it costs to do each, and the one place at BioMate where we chose to train our own model. With open questions I'd like pushback on.*

---

About once a month, someone asks me whether BioMate is training its own LLM. The honest answer has evolved over the last year, and now has two halves: *mostly no, but for one workload — regulatory writing — yes, and the reasons are instructive.* I think the question itself is more interesting than any single answer, so let me walk through what we've learned, what the literature says, and where we currently land — with the explicit caveat that this is a fast-moving space and my view in six months may shift.

The basic question splits into four architectural options, each with different cost, capability, and lock-in profiles:

1. **Prompt + RAG on a frontier model** (GPT-5, Claude, Gemini). No training of your own. Cost: API fees. Time to deploy: weeks.
2. **Fine-tune a frontier model or strong open-source base** (Llama, Qwen, Mistral) on biomedical instruction data. Cost: low to moderate. Time: 1–3 months.
3. **Continue pre-training** an open-source base on a large biomedical corpus, then instruction-tune. Cost: moderate to high. Time: 3–9 months.
4. **Train a domain-specific model from scratch** on biomedical text. Cost: very high. Time: 9–18+ months.

Each represents a different bet about where value accrues in the stack. Let me walk through what the empirical evidence says, with sources.

## The empirical picture

The most important data point is the [2025 Nature Communications benchmark of LLMs on biomedical NLP](https://www.nature.com/articles/s41467-025-56989-2), which systematically compared GPT-4, GPT-3.5, Llama variants, and traditionally fine-tuned BERT/BART models across 12 biomedical benchmarks spanning six application areas. The headline findings:

- **Traditional fine-tuning beats zero-shot or few-shot LLMs on most tasks** — including named entity recognition, relation extraction, document classification, and text similarity. The smaller, specialized models win when you actually measure carefully.
- **GPT-4 wins on reasoning-heavy tasks** like medical question answering, where the breadth of general knowledge plus the strong reasoning trace matters more than narrow-domain optimization.
- **Open-source LLMs need fine-tuning to close the gap** with closed-source models on most tasks. Out of the box, they don't compete.

This is consistent with the broader literature on domain-adapted biomedical models. [BioMedLM (2.7B parameters)](https://arxiv.org/pdf/2403.18421), trained from scratch on PubMed abstracts and full articles (34.6 billion tokens), achieved competitive performance against much larger general models on biomedical QA — matching Flan-PaLM on Medical Genetics MMLU. [Meditron](https://arxiv.org/pdf/2403.00952) (7B and 70B variants) continuously pre-trained on Llama 2 with curated medical guidelines and PubMed showed similar patterns. [Me-LLaMA](https://physionet.org/content/me-llama/1.0.0/) — pre-trained on 129B tokens of biomedical and clinical data — outperformed ChatGPT on 7 of 8 datasets and GPT-4 on 5 of 8 datasets after task-specific instruction tuning.

The pattern is consistent: **smaller domain-adapted models, properly instruction-tuned, can match or exceed much larger general models on narrow biomedical tasks. They lose to frontier models on broad reasoning. They win on cost, latency, deployability, and (importantly) on-prem capability for sensitive data.**

## The cost reality

Money matters, especially at seed/Series-A stage. Approximate compute costs as of mid-2026 for each option:

**Prompt + RAG.** Pay per query. Frontier models at ~$5–15 per million input tokens, ~$15–60 per million output tokens. For a typical scientific query (5K input tokens, 2K output), call it $0.05–0.15 per query. At a million queries/month, $50K–150K/month. Predictable, no upfront, but scales linearly with usage and has a cost floor.

**Fine-tuning.** LoRA/QLoRA fine-tuning of a 7–70B open-source model on 10K–100K instruction examples runs $5K–50K in compute. Plus the cost of building the instruction dataset, which is the hidden expense — high-quality biomedical instruction data is hard to source and curate. Realistic total: $50K–200K including data work, 4–8 weeks.

**Continued pre-training.** Training a Llama-3-8B-equivalent on ~50–100B biomedical tokens runs $200K–800K in compute, depending on hardware, training duration, and how many epochs. Plus dataset curation, plus eventual instruction-tuning. Realistic total: $500K–1.5M, 3–6 months. [Recent work like MediSwift](https://arxiv.org/pdf/2403.00952) demonstrates 2–2.5x training cost reductions through sparse pre-training, which helps but doesn't change the order of magnitude.

**Training from scratch.** A genuinely competitive from-scratch model at the 7B parameter scale runs $2M–10M+ depending on token count, scale, and how much you reinvent versus copy from Llama/Qwen recipes. At 70B scale, multiply by 5–10x. Realistic total: $10M+, 9–18 months, and you've now committed an engineering team to maintaining a model rather than building product features.

For a young company, option 4 is off the table. Option 3 is on the edge of affordable but represents a large bet that the resulting capability differential is worth the time and capital. Options 1 and 2 are the realistic candidates for most workloads.

> 📊 **Figure 1 — The four options matrix, and where BioMate sits.** Source: `figures/post_9_options_matrix.drawio.xml`
> Open in [diagrams.net](https://app.diagrams.net), export PNG at 1200×800.

## Where we currently land — and where we made the exception

For BioMate's general orchestration, my working bet is **prompt + RAG on a frontier model as the workhorse, with selective fine-tuning for narrow high-value tasks, and one continued-pre-training project for a specific high-value domain.** Here's the reasoning:

**Frontier models are improving faster than we could train.** Between mid-2024 and mid-2026, the frontier roughly doubled in capability on most scientific benchmarks. Any from-scratch model we trained in early 2026 would be matched by a frontier release within 6–9 months and exceeded within 12. The capability ceiling we'd be working toward keeps rising; the cost of catching up keeps rising too. This is the same logic that's pushed almost every applied AI company away from training foundation models — the foundation is moving too fast for non-foundation-model companies to keep up.

**Most of our hard problems aren't language problems.** When a DMPK scientist asks BioMate to design an ADMET screen for a new chemical series, or a structural biologist asks to debug a stalled cryo-EM 2D classification, the bottleneck isn't language understanding — it's the orchestration of nf-core/AutoDock/CryoSPARC/GROMACS/OpenMM tools, the parameter knowledge base, the workflow registry, and the evidence-grounded reasoning about which method applies to their specific assay or instrument configuration. A better language model gives us a 10% lift on the language component, which is maybe 20% of the overall problem. Investing in the other 80% — agent orchestration, tool integration, knowledge curation, evaluation, the prediction-vs-outcome registry — yields more.

**Frontier models with our scaffolding outperform domain-trained models without scaffolding.** This is the most important point, and the most counterintuitive one. A grounded RAG system on top of a frontier model with curated PubMed/UniProt/ChEMBL/FDA-guidance retrieval beats an un-grounded domain-trained model in our internal evaluations across drug discovery, omics analysis, and cryo-EM troubleshooting. The architecture matters more than the base model, up to a surprisingly high quality threshold. This is consistent with the literature — the Nature Communications benchmark shows the gap between general and domain models *narrows substantially* once you add good retrieval.

**Fine-tuning earns its keep for specific narrow tasks.** Where we do fine-tune small models: structured output extraction (parsing CRO study reports into normalized records), classification of QC patterns across modalities, named entity recognition for compounds and proteins, workflow-to-intent routing. These are tasks where the input format is predictable, the output format is rigid, and a small fine-tuned model deployed for cents per call beats a frontier model called for dollars. We're not building a giant fine-tune; we're building a portfolio of small ones for specific bottlenecks.

### The one exception: a domain-specific regulatory LLM

The one workload where we made the opposite bet — continued pre-training plus extensive instruction-tuning on a Llama-derivative — is **regulatory writing for IND submissions**, specifically §2.6.1 (Pharmacology Written Summary) and adjacent CTD sections.

The reasons it earned the investment:

- **The style is genuinely specialized.** FDA-acceptable regulatory prose has a register, structure, and convention set that frontier models don't reliably reproduce even with extensive few-shot prompting. A frontier model writes summaries that read like a good scientific paper. An FDA reviewer wants something that reads like §2.6.1 of a successful IND, which is a different document genre. Domain training closes this gap in a way prompting doesn't.
- **The corpus is constrained and citeable.** The training set is bounded: the FDA guidance corpus, ICH guidelines, OpenFDA, public IND/NDA reviews and approval packages, and a curated set of CTD examples. This is small relative to PubMed but very high signal for the actual writing task. We pair it with a deterministic checker layer that validates every regulatory claim against the source dataset before it leaves the model.
- **On-prem and data residency are real customer requirements here.** Pharma sponsors won't send draft regulatory text to a third-party API. A model we host (and that doesn't phone home) is the only deployable option for the customers who actually pay for this workload.
- **The cost crossover is favorable.** Regulatory writing is high-volume per submission (hundreds of pages, dozens of revisions) and the per-token cost of a frontier model adds up fast across a submission. A domain-tuned 8B-class model deployed at $0.001/query is materially cheaper at scale than the frontier equivalent, with comparable or better output quality for this specific genre.

We're calling this internally the "regulatory LLM" pipeline (v6/v7 in the codebase), and it's the place where continued pre-training plus instruction-tuning plus a deterministic checker layer plus DPO on checker-grounded preference pairs all stack to produce something a frontier model with prompting can't match.

For everything else — the orchestration agent, the workflow routing, the QC interpretation, the parameter selection, the cross-domain reasoning — frontier + scaffolding wins.

## The dissenting view, which I take seriously

The strongest argument against my position comes from people building actual domain-specific foundation models for biology — Recursion (Phenom), Genentech (LabGPT-style efforts), and the academic groups behind Meditron, BioMedLM, ESM, AlphaFold-2/3, RFDiffusion, and the rest.

Their case: a model trained with the right inductive biases for biological sequence, structure, and clinical phenotype can develop capabilities a general model never will. Not just incremental accuracy — qualitatively different behavior on hard problems like cross-modal reasoning between protein sequence and clinical outcome, or grounding chemistry in real reaction kinetics rather than pattern-matched recipe text. The argument is that scaling general models hits diminishing returns on specifically biological reasoning earlier than people think, and that the next generation of breakthrough biology AI will come from domain-specific architectures, not bigger general models.

There's a lot to this. The specialized structural and sequence models — ESM, the AlphaFold lineage, evo, Boltz — are genuinely impressive and not replicable with general LLMs. They're not language models doing biology; they're domain models trained on sequence and structure directly, and that's where the differentiated capability lives.

If we were building a target identification platform, a *de novo* protein binder design tool, or a generative chemistry foundation, I'd be more sympathetic to the from-scratch domain-model thesis. For BioMate's orchestration and workflow intelligence layer — choosing the right pipeline, parameterizing it, interpreting outputs, writing summaries, closing the QC loop — language understanding is the smaller part of the problem and frontier models do that part well enough. We *use* the specialized biology models (ESMFold and ColabFold for structure, the open-source generative chemistry models where relevant) as steps inside the workflows the agent orchestrates. We don't compete with them.

## What would change my mind

A few things would push us toward heavier investment in continued pre-training beyond the regulatory LLM:

**Demonstrable failure modes that frontier models can't overcome with scaffolding.** If we hit a class of problems where retrieval + grounding + agentic orchestration still produces unreliable results, and the failure traces back to the base model's parametric knowledge rather than the scaffolding, then we have a strong case to invest in continued pre-training for that domain too. We haven't hit this outside the regulatory writing case yet.

**Cost crossovers.** If frontier model API costs stay flat or rise while training costs continue to fall (sparse pre-training, distillation, smaller efficient architectures all help), the economic argument flips. At some point a continuously-pre-trained 8B model deployed for $0.001/query becomes more attractive than a frontier model at $0.05/query for high-volume inference workloads. The regulatory LLM is the first place this crossover happened for us; it won't be the last.

**Customer requirements.** When a top-10 pharma asks for on-prem deployment with no external API calls for a workload beyond regulatory writing — and the deal is large enough to justify the investment — we'll build the on-prem model. Until then, we won't.

**Open-source frontier-class models.** If something like Llama-5 or Qwen-4 ships with frontier-comparable reasoning and a permissive license, the "frontier vs. open-source domain-tuned" tradeoff shifts dramatically. Continued pre-training of a near-frontier open model becomes much more attractive than continued pre-training of a model that's clearly weaker than the frontier.

## What I'd love feedback on

This is genuinely an open question in my head, and I'm publishing it partly to invite pushback from people who've made different choices. Specifically:

- **For people who chose to train domain-specific biomedical foundation models:** what's the strongest empirical evidence you have that the foundation training was worth the cost? I've read the published benchmarks; what doesn't show up in those papers?
- **For people who chose pure prompt + RAG:** where have you hit walls that made you reconsider? What kinds of tasks expose the limits of general-model-plus-retrieval most clearly?
- **For people running production biomedical or regulatory LLM workloads at scale:** how do your unit economics actually shake out at high QPS? Are the frontier API costs sustainable, or have you been forced to migrate to fine-tuned alternatives for cost reasons?

I'll write up what I learn from the conversations, with attribution if you're willing.

## The actual stance

To compress all of this into something actionable: **build the scaffolding first, train models second, and train where the domain has a constrained corpus, a specialized output register, and customer-driven deployment constraints that frontier APIs can't satisfy.** The agent orchestration, the tool integration, the curated knowledge layer, the evidence-grounded retrieval, the evaluation framework, the prediction-vs-outcome registry — these compound in value regardless of which base model you use, and they don't become obsolete when a new frontier model ships.

The exception, when you make it, should be principled. For us, that's regulatory writing — a domain where continued pre-training pays for itself through output quality, on-prem deployability, and unit economics. For other teams, it might be a different workload. But the default should be scaffolding; the from-scratch foundation model is the right bet for a small number of teams with very different problem shapes than ours.

This may be wrong, and I'm open to being convinced otherwise. Reply to this post or email me — I read everything.

> 🧪 **Try the orchestration layer.** BioMate is in open trial — bring a workflow and see what frontier + scaffolding can do without a custom foundation model: [**biomate.ai/try**](https://biomate.ai/try)

---

In two weeks: *Building a multi-agent system for end-to-end drug development workflows — architecture decisions, what worked, what we got wrong. The first technical deep-dive into how BioMate actually orchestrates a program from target hypothesis to IND draft.*

— Yaoyun Wang
Founder & CEO, BioMate AI
