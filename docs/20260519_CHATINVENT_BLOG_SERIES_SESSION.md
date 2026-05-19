# ChatInvent blog series — 2026-05-19

## Goal

User flagged a screenshot of AstraZeneca's *Drug Discovery Today* paper
**"Democratising real-world drug discovery through agentic AI"** (doi:
[10.1016/j.drudis.2026.104605](https://doi.org/10.1016/j.drudis.2026.104605))
describing the **ChatInvent** system. The paper publicly disclosed five
engineering problems agentic AI hits in real pharma R&D plus six
capability pillars the Agent era requires.

BioMate's existing work maps 1:1 to those problems. Wrote five paired
posts (Substack long-form + LinkedIn feed) with one draw.io figure each,
weaving in benchmark evidence including head-to-head numbers vs Biomni,
Claude Code Opus 4.6, and GPT-4o.

## Five problems → five post pairs

| Post | AstraZeneca-named problem | BioMate architecture                                          |
|------|---------------------------|----------------------------------------------------------------|
| 12   | Context explosion         | Domain-gated rules + hybrid retrieval + lazy step fetch + episode memory |
| 13   | Tool hallucination        | Registry-bounded selection + disambiguation gate + citation discipline + hallucination judge |
| 14   | Schema mismatch           | Rule-first / LLM-fallback / schema-validation guardrail        |
| 15   | Workflow instability      | Auto-loop QC remediation with was→now diff + HITL approval     |
| 16   | Memory corruption + pillars (traceability, governance, HITL) | Episode + correction memory + prediction registry + governance + HITL surface |

## Benchmark numbers cited as evidence

| Benchmark | BioMate | Comparator |
|---|---|---|
| BixBench MCQ (bioinformatics execution) | **80% (v21)** | Biomni Lab 52.2% • Claude Code Opus 4.6 39.5% • GPT-4o 17% |
| BiomniEval1 (Biomni's own benchmark) | **~71%** | Biomni-R0-32B >80% (specialized biomedical foundation model) |
| BiomniEval1 patient_gene | **84% (v9)** | competitive with Biomni-R0-32B on its home benchmark |
| Routing v5 (120 cases) | 84% exact, mean 0.875 | — |
| IR baseline (search_ranked) | MRR 0.847, P@1 0.742, NDCG@3 0.920, Hit@5 0.967 | — |
| Memory benchmark (LongMemEval + LoCoMo aligned) | 20/20, 100% weighted | +45% vs GPT-4o no-injection baseline |
| Auto-loop convergence (cross-domain) | 96.4% ≤ 3 iters | — |
| ADMET / CYP-DDI / Docking / NCA-PK auto-loops | 96/96 tests | — |
| CryoEM auto-loop | 95/95 + 24 E2E | — |
| PBPK benchmark | 71.7% → **98.5%** (+26.8pp via rule-based prereq gate) | — |
| ADMET benchmark | 89.3% | — |
| BOIN dose escalation | 100% | — |
| HallucinationDetector on screen_gene + gwas_causal | 0% fabrication | — |

## Discoverability strategy applied

Each LinkedIn post @-tags the three highest-leverage AstraZeneca
co-authors: **@Jiazhen He** (first author), **@Ola Engkvist** (Senior
Director Molecular AI, most visible publicly), **@Samuel Genheden**
(senior author). Each post includes:

- Paper citation with DOI in the opening line
- Closing line directly addressing the authors with a specific question
- A "Posting note" at the top instructing the user to retype `@` in the
  LinkedIn composer so the tag resolves to a real profile

For Substack posts, the author team is credited by name (no @-tags;
those don't resolve on Substack) with the DOI link.

## Files

```
business/marketing/blog_posts/
├── PLAN_chatinvent_series.md
├── post_12_substack.md       post_12_linkedin.md        ← Context explosion
├── post_13_substack.md       post_13_linkedin.md        ← Tool hallucination
├── post_14_substack.md       post_14_linkedin.md        ← Schema mismatch
├── post_15_substack.md       post_15_linkedin.md        ← Workflow instability
├── post_16_substack.md       post_16_linkedin.md        ← Memory + governance
└── figures/
    ├── post_12_context_stack.drawio.xml
    ├── post_13_tool_grounding.drawio.xml
    ├── post_14_param_extraction.drawio.xml
    ├── post_15_auto_loop.drawio.xml
    └── post_16_memory_governance.drawio.xml
```

## Pending

- User to verify the three @-handles map to the correct LinkedIn
  profiles before posting.
- Confirm `biomate.ai/try` is the live trial URL.
- Render all five new draw.io files to PNG/SVG at the sizes in
  `figures/README.md` before publication.
- Consider a DM to Jiazhen He, Ola Engkvist, and Samuel Genheden with
  the Substack links after publication, per the discoverability
  playbook (see prior session message).
- Posts 10 and 11 (ANDV inhibitor two-agent; Plan A epitope) still TBD.

## Commits

Pending at the end of this session.
