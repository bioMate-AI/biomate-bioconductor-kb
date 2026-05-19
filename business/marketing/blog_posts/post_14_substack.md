# Schema mismatch — why we don't trust the LLM with arithmetic, and the hybrid pipeline that fixes it

*Third in the ChatInvent series. The AstraZeneca Molecular AI team (Jiazhen He, Ola Engkvist, Samuel Genheden et al.) named **schema mismatch** as one of the five engineering problems agentic AI hits in pharma R&D, in their *Drug Discovery Today* paper ["Democratising real-world drug discovery through agentic AI"](https://doi.org/10.1016/j.drudis.2026.104605) (doi: 10.1016/j.drudis.2026.104605). It's the unsexy one — and it eats more programs than tool hallucination does, because the failures don't look like failures.*

---

## What the problem actually is

The agent picks the right tool. Good. Then it has to fill out the tool's parameter schema. That's where it quietly breaks:

- User says "simulate for 100 nanoseconds." The Nextflow workflow takes `n_steps`, not `time_ns`. The model writes `n_steps: 100`. The actual value should be `50_000_000` (100 ns / 2 fs).
- User says "single-end reads." The workflow flag is `single_end: true`. The model writes `paired: false` because that's what it saw in a different tool's docs.
- User says "human genome." The workflow's `genome` enum accepts `GRCh38` / `GRCh37` / `T2T-CHM13`. The model writes `human`.
- User says "remove duplicates." The workflow has a `keep_duplicates` flag. The model writes `remove_duplicates: true` (which isn't a valid key) instead of `keep_duplicates: false`.

Each of these executes. None throw errors. The numbers that come out look reasonable. And the run is silently wrong.

This is **schema mismatch**: the parameter the agent emits is *type-valid* but *semantically wrong*. The workflow ran. The science didn't.

LLMs are bad at this for the same reason they're bad at arithmetic. Unit conversion is exact. Boolean negation is exact. Enum constraints are exact. Models are probabilistic. The mismatch is structural.

---

## What we built

> 📊 **Figure 1 — Rule-first / LLM-fallback / schema-guardrail.** Source: `figures/post_14_param_extraction.drawio.xml`. Open in [diagrams.net](https://app.diagrams.net), export PNG at 1200×800.

Three-stage pipeline. Each stage is allowed to handle only what it's good at.

### Stage 1 — Deterministic rules

Rules handle everything that has a single right answer:

- **Unit conversions.** `100 ns` → `n_steps = 50_000_000` (computed from `dt = 2 fs`). `5 µM` → `concentration_M = 5e-6`. No LLM in the loop; it's a function.
- **Boolean negations.** "remove duplicates" → `keep_duplicates: false`. "exclude introns" → `include_introns: false`. The rule recognizes the negation morpheme and inverts.
- **Canonical alias normalization.** `human` → `GRCh38`. `dUTP` → `reverse` (strandedness). `cyno` → `Macaca fascicularis`. The alias map is curated, versioned, and idempotent.
- **Single-end / paired-end detection.** From the file list or the user's phrasing. Deterministic.

Rules are exact, zero-cost, and testable. We have unit tests for each.

### Stage 2 — LLM fallback for free-text and ambiguity

The LLM handles only what rules can't:

- **Free-text values** — SMILES strings, PDB IDs, gene names, compound names. The LLM extracts; the rule layer doesn't try.
- **Ambiguous enum selection** — when the user's phrasing maps to multiple valid enum values, the LLM picks based on context and emits a confidence.
- **Multi-parameter inference from prose** — when the user describes a study in narrative form and several parameters need to be inferred together, the LLM does the joint extraction.

The LLM is never asked to do arithmetic or boolean logic. It's asked to do *language*, which is what it's actually good at.

### Stage 3 — Schema validation guardrail

After both stages, every extracted value is validated against the workflow's actual JSON schema (which we have, because it's in the registry):

- Values violating `allowed_values` are either normalized (if a close alias exists) or dropped (with a flag to the user).
- Type-violating values are rejected before they reach the executor.
- Required parameters with no extracted value trigger a clarification turn, not a default substitution.

Nothing reaches the executor that the schema doesn't accept.

---

## What the benchmarks say

| Benchmark                                                     | Result                                              |
|---------------------------------------------------------------|-----------------------------------------------------|
| **param_prefill** (115 cases, including 15-case `param_name_disambiguation`) | 61.7% → target ≥70%, climbing                       |
| **PBPK benchmark** after rule-based prereq gate              | 71.7% → **98.5%** (+26.8pp)                         |
| **ADMET benchmark**                                           | **89.3%** with rule-based hERG/DILI/Ames/Ro5 thresholds |
| **BOIN clinical dose escalation**                             | **100%** (intent + extraction unified)              |
| **Routing v6 variant calling** after structural retrieval fixes | 0.567 → **0.824** (+0.206)                          |

The headline: **PBPK from 71.7% to 98.5%** purely by adding a deterministic rule-based gate that validates prerequisites and converts units before the workflow runs. No model change. No prompt change. Just letting rules do what rules do.

ADMET 89.3% comes from the same approach — rules handle the deterministic threshold mapping (hERG IC50 vs free Cmax × 30; DILI risk class boundaries; Ro5 violations count); the LLM handles only the free-text compound names.

---

## Why this matters more than tool hallucination

Tool hallucination is loud. The agent picks `nf-core/rnaseq_v2_special_edition` and the executor errors out: "no such workflow." Someone notices.

Schema mismatch is silent. The agent picks `nf-core/rnaseq` correctly, then writes `strand: reverse` when the flag is `strandedness: reverse`. The workflow ran on the *default* strandedness because the misspelled flag was ignored. The DEG results are wrong by 30% in the direction of false discoveries. The biologist publishes. Two years later someone tries to replicate and can't.

In a regulated environment this is worse than worse. It's the kind of failure that fails an audit, not a sanity check.

The architecture has to take it seriously, and "the LLM will figure it out" is not taking it seriously.

---

## The honest limitations

- **The rule library has gaps.** Every new domain we add (e.g., proteomics LFQ, single-cell sub-clustering) requires its own rule set. We add them incrementally; until we have them, the LLM fallback handles the gap with lower accuracy.
- **param_prefill is at 61.7%, not 100%.** The biggest miss class is ambiguous-but-not-impossible cases that genuinely need user clarification — and our current pipeline doesn't always trigger the clarification, sometimes filling with a best guess instead.
- **Schema validation is only as strong as the schema definition.** If the registered schema is lenient (e.g., `string` instead of an explicit enum), the guardrail can't catch a semantic miss. We're tightening schemas workflow-by-workflow.

---

> 🧪 **Try parameter extraction.** Open trial — describe a workflow in narrative prose ("simulate this PDB for 100 ns with explicit solvent in water at 310 K") and watch the parameter strip fill in. Edit anything that's wrong; the correction feeds back into the rule layer: [**biomate.ai/try**](https://biomate.ai/try)

---

*Next post: workflow instability — what the auto-loop QC layer does when a run produces results that don't pass the gate.*

— Yaoyun Wang
Founder & CEO, BioMate AI
