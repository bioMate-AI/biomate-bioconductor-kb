# Tool hallucination is the second wall — and the most dangerous one in regulated R&D

*Second in the ChatInvent series. The AstraZeneca Molecular AI team (Jiazhen He et al., incl. Ola Engkvist and Samuel Genheden) named **tool hallucination** as one of the five engineering problems agentic AI hits in pharma R&D — in their *Drug Discovery Today* paper ["Democratising real-world drug discovery through agentic AI"](https://doi.org/10.1016/j.drudis.2026.104605) (doi: 10.1016/j.drudis.2026.104605). This is the failure mode that turns a confident-looking demo into a compliance liability.*

---

## What "tool hallucination" actually means

The LLM agent is asked to run a workflow. It confidently calls a tool that doesn't exist.

- The tool name is plausible (`nf_core_proteomics_dia_quant`) but isn't in your catalog.
- The parameters look reasonable (`--strand reverse`) but the workflow's actual flag is `--strandedness reverse`.
- The output schema the agent expects (`{ "vcf_path": "...", "stats_path": "..." }`) doesn't match what the workflow actually emits.

In a chat app, this is a glitch. In a drug program, it's a record going into a regulatory submission that points at a tool that never ran on data that was never produced.

This is the failure mode that has to go to zero in pharma. Not "low," not "rare." **Zero.**

---

## What we built

> 📊 **Figure 1 — Registry-bounded tool selection.** Source: `figures/post_13_tool_grounding.drawio.xml`. Open in [diagrams.net](https://app.diagrams.net), export PNG at 1200×800.

Four discipline layers, each closing one path the agent could use to invent something.

### 1. The workflow registry is the source of truth

Every workflow BioMate can route to is in `backend/database/galaxy_ai_tools.db` — 2,455 entries, each with name, domain, description, required params, optional params, step file path, and version. The agent **does not generate** workflow names. It picks from a retrieved set of candidate registry entries.

If a workflow isn't in the registry, the agent can't route to it. It can suggest "I don't have this workflow indexed — would you like me to flag it as a coverage gap?" but it cannot fabricate the call.

### 2. Disambiguation gate, not coin flip

When the top-K retrieved candidates are close in score, a naive agent picks one and hopes. We gate disambiguation precisely:

- Fires only when **match_type != high_confidence**, AND
- ≥2 candidates score ≥6.0, AND
- The score gap between them is < 3.0

When the gate fires, the agent returns a `disambiguation` response — a card asking the user which candidate they meant — instead of guessing. We tuned it to fire on genuine ambiguity, not paranoia.

### 3. Citation discipline on every claim

Every factual claim the agent emits is followed by a citation token pointing to a retrieved source — the registry entry, the FDA guidance, the PubMed paper. Claims without supporting context get flagged as "model knowledge — not verified."

This isn't a UX nicety. It's the discipline that makes the difference visible between "this came from the catalog" and "the model thinks this exists."

### 4. Hallucination detection as a separate evaluation pass

We don't trust the agent to grade itself. The `HallucinationDetector` runs as an independent LLM-judge pass over the output, with task-specific rules (e.g., for `screen_gene` outputs: every gene mentioned must be in the input list or in a retrieved knowledge source).

If the detector flags hallucination, the response is reformulated or returned to the user with the offending claim removed.

---

## What the benchmarks say

| Benchmark                                   | Result                                       |
|---------------------------------------------|----------------------------------------------|
| **Workflow registry size**                  | 2,455 entries across 34 biological domains   |
| **HallucinationDetector** on `screen_gene` + `gwas_causal` | 0% hallucination rate (actual fabrication, distinct from overconfidence) |
| **Routing accuracy v5/v6** (120 cases)      | 84% exact (v5); 80% (v6, with variant_calling +20.6pp via 4 structural fixes) |
| **IR layer** (raw retrieval, no LLM)        | Hit@5 = 0.967 — the correct workflow is in the top 5 candidates 97% of the time |
| **Disambiguation candidate pickup**         | When the gate fires correctly, the correct workflow is in the candidate list, so the user's choice flows back as a high-confidence routing signal |

The headline: **0% hallucination on the tested knowledge tasks** (screen_gene, gwas_causal). Not "low" — zero, measured by an independent LLM judge with task-specific rules.

This is the difference between an agent that *sounds confident* and one that *is grounded*.

---

## The discipline that's easy to skip

Most "AI for biology" demos skip three things, and each skip silently re-introduces hallucination:

1. **They retrieve free-text descriptions, then let the LLM rewrite them.** We force exact-match registry IDs through to the executor.
2. **They run one LLM call to pick a tool, with no judge.** We run an independent hallucination judge on outputs that touch known-failure modes.
3. **They have no "I don't know."** We have a disambiguation card, a coverage-gap response, and a "model knowledge — not verified" marker. The agent is allowed to say "this isn't in my catalog."

The third one is the hardest culturally. Demo-grade agents are rewarded for sounding confident. Production-grade agents in pharma are rewarded for *being right when they speak and silent when they aren't*.

---

## What this means for users

When BioMate tells you to route an RNA-seq job to `nf-core/rnaseq` followed by `nf-core/differentialabundance`, you can click through to the registry entry, see the workflow's `nextflow_path`, see the parameter schema, see the version, see the citations behind the routing decision. There is no version of this where the agent says "use the `rnaseq_v2_special_edition` workflow" when no such workflow exists.

When BioMate doesn't know, it says so. That's a feature, not a regression.

---

## The honest limitations

- **Coverage gaps are real.** 2,455 workflows is broad but not exhaustive. If a user asks for something we don't have, the agent admits the gap — but that's still a gap in the product.
- **Routing is 80–84% exact, not 100%.** The remaining 16–20% mostly route to a *close but not exact* workflow (e.g., `nf-core/rnaseq` instead of `nf-core/scrnaseq` for ambiguous transcriptomics queries). The user is still in the right family of tools, and the disambiguation gate catches the genuinely contested cases.
- **The LLM judge for hallucination has its own error rate.** We use it as a guardrail, not as a guarantee. Wet-lab and clinical validation remain the ultimate check.

---

> 🧪 **Try grounded tool selection.** Open trial — ask for a workflow that's clearly out of catalog and watch the agent refuse cleanly instead of inventing one: [**biomate.ai**](https://biomate.ai)

---

*Next post: schema mismatch — why we don't trust the LLM to do unit conversions, and the rule-first / LLM-fallback architecture that fixes it.*

— Yaoyun Wang
Founder & CEO, BioMate AI
