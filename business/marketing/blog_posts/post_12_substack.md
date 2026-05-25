# Context explosion is the first wall agentic AI hits in pharma. Here's how we get past it.

*AstraZeneca's Molecular AI team — Jiazhen He, Helen Lai, Lakshidaa Saigiridharan, Gian Marco Ghiandoni, K. Jenei, Umur Gokalp, Ajsa Nukovic, Ola Engkvist, Jon Paul Janet, and Samuel Genheden — just published ["Democratising real-world drug discovery through agentic AI"](https://doi.org/10.1016/j.drudis.2026.104605) in *Drug Discovery Today* (doi: 10.1016/j.drudis.2026.104605), describing their **ChatInvent** system. The most useful part of the paper isn't the demo — it's that they publicly named the five engineering problems agentic AI hits when it enters real pharma R&D. Over the next five posts I'll walk through each one and show what we've built at BioMate to address it.*

*Starting with the one that breaks every prototype first: **context explosion**.*

---

## What the problem actually is

You build a clean LLM agent for drug discovery. It works on the demo: one query, one tool call, one result.

Then you try a real program. The user asks for a workflow that touches RNA-seq, then PBPK, then ADMET. The agent has to know:

- Which of 2,455 workflows could match
- What the user said three turns ago
- What parameters were already fixed earlier in the session
- What QC gates are configured
- What corrections the user made on previous runs

And the prompt now has to carry all of it.

The result is what AstraZeneca calls **context explosion**: the prompt balloons past the useful window, the model loses the thread, and the agent starts behaving worse on turn 4 than it did on turn 1. By turn 8 it's hallucinating tools.

The fix is not "buy a longer context window." Long-context models get *slower and dumber* fast as the prompt grows. The fix is architecture.

---

## What we built

Four layers, all designed to keep the active context small and the right information retrievable on demand.

> 📊 **Figure 1 — BioMate's context-management stack.** Source: `figures/post_12_context_stack.drawio.xml`. Open in [diagrams.net](https://app.diagrams.net), export PNG at 1200×800.

### 1. Domain-gated rule injection, not flat rule lists

The naive approach is to dump all your routing rules into the system prompt. With 2,455 workflows that's a 50K-token prompt before the user has said anything.

Instead, we **classify the user's intent first** (Haiku, ~150 tokens) and inject only the 3–4 rules relevant to their domain. A user asking about RNA-seq sees the transcriptomics rules. A user asking about ADMET sees the drug-discovery rules. They never see each other's.

### 2. Hybrid retrieval over the workflow registry

The agent doesn't "remember" the 2,455-workflow catalog. It retrieves at query time using a hybrid stack:

- **BGE dense embeddings** (`bge-small-en-v1.5`) for semantic match
- **PostgreSQL FTS** for keyword match
- **Named-anchor extraction** for compound IDs, gene symbols, PDB IDs
- **LLM Pass-0 reranking** with citation back to the registry entry

Only the top-K candidates (typically 5) enter the active context. The other 2,450 stay in the database.

### 3. Lazy step fetching

A workflow can have 20+ steps with parameters, descriptions, and provenance. Loading all of that into the prompt for every workflow under consideration is wasteful.

We lazy-fetch: when the user picks a workflow, *then* we pull its step definitions via `/api/nextflow/steps`. The agent only ever holds the steps it actually needs.

### 4. Conversation compaction with episode + correction memory

Long conversations get compacted into structured **episodes** (what was run, what was the outcome, what the user corrected). On the next turn we inject:

- The current task message
- A small block of the most-recent episode memory
- A block of any standing user corrections (e.g., "user prefers paired-end reads when ambiguous")

The raw conversation history doesn't ride into every new turn. The *distilled* memory does.

---

## What the benchmarks say

| Benchmark               | Result                                  |
|-------------------------|-----------------------------------------|
| **Routing v5** (120 cases) | 84% exact match, mean score 0.875       |
| **IR baseline** on `search_ranked` | MRR 0.847, P@1 0.742, NDCG@3 0.920, Hit@5 0.967 |
| **Disambiguation gate** | Fires only when ≥2 candidates score ≥6.0 *and* the gap is <3.0 — i.e., genuine ambiguity, not false alarms |
| **Param prefill (115 cases)**  | 61.7% baseline, climbing toward the ≥70% target |
| **Memory benchmark (20 scenarios)** | 20/20 pass — recall, correction, temporal, synthesis, adversarial |

The single number that matters most: **P@1 of 0.742 on raw search**. The correct workflow is the top result three-quarters of the time before any LLM is even asked to pick. The LLM only has to break ties.

This is the difference between an agent that handles 2,455 workflows by *thinking harder* (it can't) and one that handles 2,455 workflows by *retrieving better* (it can).

---

## What this means for users

When you bring a multi-step program to BioMate — say, an ADMET screen of a hit series, followed by a PBPK simulation for the top candidate, followed by IND §2.6.1 draft generation — the agent does *not* try to hold all three workflows + your 30 previous turns in the prompt at once.

It holds the active task, the immediate retrieved candidates, the distilled memory, and the standing corrections. Then it routes, executes, and forgets the irrelevant 99% on the way to the next step.

---

## The honest limitations

- **Episode compaction is lossy.** A summary of "we ran sarek with these params and got these VCFs" is not the same as the full chat log. We compensate with the prediction registry, so the *facts* are queryable even when the *chat* is gone.
- **Routing P@1 of 0.742 means 26% of queries don't have the right answer at rank 1.** The disambiguation gate catches the genuinely ambiguous cases; the rest get the wrong workflow ranked first and need user correction. We're working on it.
- **Long-context models are still useful** for the actual reasoning step — we just don't use them as a substitute for retrieval.

---

> 🧪 **Try the orchestration layer.** BioMate is in open trial. Bring a workflow that spans two or three specialties and watch the context-management work end-to-end: [**biomate.ai**](https://biomate.ai)

---

*Next post: tool hallucination — how we stop the agent from inventing workflows that don't exist.*

— Yaoyun Wang
Founder & CEO, BioMate AI
