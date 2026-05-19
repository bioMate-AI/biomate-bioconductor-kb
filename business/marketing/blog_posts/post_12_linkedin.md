# LinkedIn feed post — Post 12

**Hero image:** `figures/post_12_context_stack.drawio.xml` exported as 1200×627 PNG.

**Character count:** ~2,600 / 3,000.

**Posting note:** When pasting into LinkedIn's composer, retype the `@` in front of each name below so LinkedIn auto-resolves the real profile (it won't resolve from pasted plain text).

---

@Jiazhen He @Ola Engkvist @Samuel Genheden and the AstraZeneca Molecular AI team just published "Democratising real-world drug discovery through agentic AI" in Drug Discovery Today (doi: 10.1016/j.drudis.2026.104605), describing their ChatInvent system.

They publicly named the five engineering problems agentic AI hits in real pharma R&D:

1️⃣ Context explosion
2️⃣ Tool hallucination
3️⃣ Schema mismatch
4️⃣ Memory corruption
5️⃣ Workflow instability

This is the most useful AI-for-pharma disclosure I've seen this year. The biggest shift in the Agent era isn't "smarter models" — it's system stability.

Over the next five posts I'll walk through each problem with what we've built at BioMate.

Starting with the one that breaks every prototype first: CONTEXT EXPLOSION.

The naive setup looks fine on a demo. One query, one tool, one result.

Then a real program comes in. RNA-seq → PBPK → ADMET → IND draft, across 30 turns, touching 2,455 workflows. The prompt balloons. The model loses the thread by turn 4. By turn 8 it's hallucinating tools.

You can't fix this with a longer context window. Long-context models get slower and dumber as the prompt grows.

Architecture, not window size:

🔹 DOMAIN-GATED RULES
Classify intent first → inject only the 3–4 rules relevant to that domain. No 50K-token mega-prompt.

🔹 HYBRID RETRIEVAL
BGE dense + Postgres FTS + named-anchor + LLM rerank. The 2,455-workflow catalog stays in the DB. Only top-K enters the prompt.

🔹 LAZY STEP FETCHING
Workflow steps + parameters are pulled on demand, after the user picks.

🔹 EPISODE + CORRECTION MEMORY
Long conversations compact into structured episodes. The distilled memory rides into new turns. The raw chat log doesn't.

The number that matters: P@1 of 0.742 on raw retrieval. The correct workflow is rank-1 three-quarters of the time before any LLM is even asked to pick.

That's the difference between an agent that handles 2,455 workflows by thinking harder (it can't) and one that handles them by retrieving better (it can).

📊 Benchmarks behind the architecture:
✓ Routing v5: 84% exact, mean 0.875 (120 cases)
✓ IR baseline: MRR 0.847, P@1 0.742, NDCG@3 0.920
✓ Memory benchmark: 20/20 (recall, correction, temporal, synthesis, adversarial)
✓ +45% vs GPT-4o no-injection baseline

Open trial — bring a multi-turn program and watch the context-management work:

👉 biomate.ai/try

Full essay (with stack diagram + the five-post series): [Substack link]

@Jiazhen He @Ola Engkvist @Samuel Genheden — would love your reaction on the context-management piece. We have a different bet on how to handle the 2,455-workflow catalog than ChatInvent and I'd value the pushback.

#AIinPharma #DrugDiscovery #AgenticAI #LLM #Bioinformatics #AstraZeneca
