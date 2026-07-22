# UQU Context Refactor — 2026-07-20

## Problem

BioMate's Unified Query Understanding (UQU) classifier was receiving only the **current
bare message** with no conversation history. On multi-turn conversations this meant:

- T2 "s3://mybucket/sample.fastq.gz" was classified without knowing T1 asked for RNA-seq
- T2 "yes go ahead" was classified without domain context
- UQU produced `subQuery: "s3://mybucket/..."` — a literal copy, not a semantic description
- Galaxy FTS received that literal string, scored below `medium_confidence`, fell to
  NextflowComposer, which failed → "Could not generate workflow"

The codebase accumulated **15+ programmatic keyword-regex overrides** as patches:
each time the LLM misclassified a specific pattern, a new `if (message.matches(...))` block
was added to force `needsWorkflowGeneration=true`. This grew into 200+ lines of rules
that the LLM should have been handling.

## Root Cause

```
analyzeIntent(message, context)
  └─ LLM call: messages: [{ role: 'user', content: message }]
                                                    ^^^^^^^^
                                         bare current message only — no history
```

`context.previousMessages` existed and was used in the *response generation* step,
but was never passed to the *intent classification* step.

## Fix

### 1. UQU receives conversation history

`analyzeIntent` now builds `messageForUQU` from the last 3 prior user turns + the
current message, and passes it to every UQU LLM path (Gemini, Haiku fallback, chain):

```typescript
const priorUserTurns = (context.previousMessages || [])
  .filter((m) => m.role === 'user' && (m.content || '').trim().length > 10)
  .slice(-3)
  .map((m, i) => `Turn ${i + 1}: ${(m.content || '').trim().slice(0, 400)}`);
const messageForUQU = priorUserTurns.length > 0
  ? `[Prior conversation context:\n${priorUserTurns.join('\n')}\n]\n\nCurrent user message (classify this):\n${message}`
  : message;
```

The LLM now produces a semantically enriched `subQuery` — e.g. "RNA-seq alignment and
quantification on mouse GRCm38 paired-end samples using S3 inputs" — rather than copying
"s3://mybucket/sample.fastq.gz". That `subQuery` flows directly into Galaxy FTS.

The LLM decides when history is relevant. No programmatic gate.

### 2. UQU prompt: hard classification examples

Added an 18-row table to the UQU system prompt with the exact edge cases that
previously required code overrides (ADMET+SMILES, noun-phrase method descriptions,
AI model names, PBPK/BOIN/CryoEM, bare S3/SRA follow-ups). The LLM generalises to
novel cases; the code list never could.

### 3. 162 lines of hardcoded overrides deleted

Removed all classification-only overrides. These existed solely because UQU had no
context; they are now redundant:

| Deleted override | What it patched |
|---|---|
| ADMET+SMILES fast path | Raw SMILES + ADMET keyword → `workflow_generation` |
| Bioinformatics method-description (4 nested regexes) | Noun-phrase queries ("Spectral counting from DDA") |
| AI model name list (ProTrek, Boltz-2, Chai-1…) | Known AI/ML workflow names |
| PBPK / named PK tool override | PK-Sim, Simcyp, NONMEM, PBPK concepts |
| BOIN dose-escalation override | Phase I dose-escalation trial design |
| ADMET profile without SMILES | Compound name + ADMET intent |
| CryoEM SPA keyword list | CryoSPARC, single-particle analysis |
| Multi-turn data-provision session-memory override | S3/SRA in follow-up turn |

### 4. `generateWorkflow` — no more string-concatenation rescue

Removed the regex-gated FTS enrichment that prepended prior user turns to `user_intent`
inside `generateWorkflow`. That was patching the symptom (FTS got no domain signal)
rather than the cause (UQU was classifying in isolation). UQU now synthesises the
correct `subQuery` before `generateWorkflow` is called.

## What was kept (intentionally)

These are **correct behaviour guards**, not classification patches:

| Guard | Why it stays |
|---|---|
| HPO+ENSG reversal | Prevents pipeline launch on patient gene detection tasks |
| Paper-question suppression | Prevents pipeline launch when user reads a PDF |
| Inline CSV + tool name short-circuit | Pre-LLM; LLM unreliable on pasted tabular data |
| Target-evidence, trial-feasibility, pathway-enrichment, GWAS-chain, multi-omics, macrophage overrides | Still inject `keyTerms`/`preferredDomains` post-UQU; scheduled for second-pass cleanup once E2E confirms UQU returns these natively |

## Before / After

| | Before | After |
|---|---|---|
| Lines of classification overrides | ~200 | ~80 (remaining are domain-routing, not classification) |
| UQU context awareness | Current message only | Last 3 prior user turns |
| T2 data-provision FTS query | "s3://mybucket/sample.fastq.gz" | "RNA-seq alignment on mouse GRCm38 with S3 paired-end inputs" |
| T2 confirmation FTS query | "yes go ahead" | "nf-core/rnaseq on mouse GRCm38 samples, confirmation to proceed" |
| New override required per new domain | Yes | No — LLM generalises from examples |
