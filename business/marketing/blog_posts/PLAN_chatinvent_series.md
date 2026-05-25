# ChatInvent series — pharma-needs mapping plan

**Trigger:** AstraZeneca's *Drug Discovery Today* paper
**"Democratising real-world drug discovery through agentic AI"**
(doi: [10.1016/j.drudis.2026.104605](https://doi.org/10.1016/j.drudis.2026.104605))
by Jiazhen He, Helen Lai, Lakshidaa Saigiridharan, Gian Marco Ghiandoni,
K. Jenei, Umur Gokalp, Ajsa Nukovic, **Ola Engkvist**, Jon Paul Janet,
and **Samuel Genheden** — describing their **ChatInvent** system.
Surfaced via screenshot at `/home/yzhang/Desktop/business/phama_needs.png`.

The paper publicly disclosed the five engineering problems agentic AI
hits when it enters real pharma drug-discovery production:

1. **Context explosion**
2. **Tool hallucination**
3. **Schema mismatch**
4. **Memory corruption**
5. **Workflow instability**

And argued that the biggest shift in the Agent era is from "model
capability" to "system stability," with six capability pillars: tool
orchestration, evaluation, traceability, governance, human-in-the-loop,
memory.

BioMate's existing engineering matches these problems 1:1. This series
of five post pairs (Substack + LinkedIn + draw.io figure each) walks
through each problem, shows the BioMate architecture that addresses it,
and cites the benchmark evidence that the architecture works.

## The five pairs

| Post | Problem               | BioMate match                                   | Benchmark evidence cited                                  |
|------|-----------------------|-------------------------------------------------|-----------------------------------------------------------|
| 12   | Context explosion     | Domain-gated rules, hybrid retrieval, lazy step fetch | Routing v5 84% exact / mean 0.875; IR MRR 0.847, P@1 0.742 |
| 13   | Tool hallucination    | Grounded workflow registry + disambiguation gate + citation discipline | 2,455 workflows; HallucinationDetector ~0% on tested paths; param prefill name-disambig 15 cases |
| 14   | Schema mismatch       | Hybrid rule + LLM parameter extraction with schema-validation guardrail | param_prefill 61.7%→target ≥70%; 115 cases; PBPK 98.5%; ADMET 89.3% |
| 15   | Workflow instability  | Auto-loop QC + remediation across drug-dev + cryo-EM | ADMET/CYP-DDI/Docking/NCA-PK 96/96 tests; CryoEM 95/95; auto-loop 96.4% conv ≤3 iters |
| 16   | Memory + traceability + governance | Persistent memory injection + prediction registry + audit trail | Memory benchmark 20/20 (100%); LongMemEval-aligned; Session 8 episode + correction memory live |

## Voice

Same founder voice (Yaoyun Wang). Each post leads with the
AstraZeneca/ChatInvent reference as third-party validation, then shows
what BioMate actually does, then cites benchmarks. Trial link
`biomate.ai` woven into each.

## Numbering

Posts 10 and 11 are reserved (per `figures/README.md`) for the
ANDV-inhibitor two-agent post and the Plan A epitope-prediction post.
This series uses 12–16.
