# Synthetic SFT Task Generation — Approach

**Date:** 2026-05-10
**Scope:** v6 corpus generation methodology (task5 MRSD, task6 skeleton, future task7–9)

---

## Core principle: **checker-first generation**

Every synthetic example is generated against a deterministic verifier and **rejected if it fails**. The verifier is the same one used at evaluation and inference time. This means:

- 100% of training data passes the checker by construction (verified: 500/500 task5, 1288/1288 task6)
- The model can never learn a pattern that violates the checker
- The checker doubles as: data filter → eval metric → inference-time guardrail → RL reward component

This is the inverse of "generate, then measure" pipelines that produce noisy supervision. We **define the spec first** (`mrsd_verifier.py`, `structural_validator.py`) and generate to satisfy it.

---

## Generation pipeline (per task)

```
[domain knowledge] → [parametric example sampler] → [prose realizer] → [verifier]
                                                                          │
                                                  ┌──── reject ──────────┘
                                                  │
                                                accept → JSONL
```

### Stage 1 — Parametric sampler

Defines the **parameter space** of the task with explicit exclusions for regulatory edge cases:

- **task5 (MRSD)**: species ∈ {mouse, rat, dog, monkey, rabbit, minipig}; NOAEL ∈ {0.5–2000 mg/kg}; safety factor ∈ {10, 50, 100}; **oncology indications excluded** (ICH S9 uses STD10/HNSTD path, not NOAEL/MRSD)
- **task6 (skeleton)**: drawn from existing 1,727 prose examples; section_type → ICH section ID mapping (tox_overview/tox_genotox → §2.6.6, pk_overview → §2.6.4, etc.)

Sampler decisions encode domain knowledge that the model would otherwise have to infer from sparse signal.

### Stage 2 — Prose realizer

Two failure modes to avoid:

**(a) Template memorization.** If every example uses the same opener ("In the most sensitive species, the {species}, the NOAEL of..."), the model memorizes the surface form rather than the underlying skill. **Mitigation:** 3+ prose variants chosen randomly per example. Variants must agree on facts but differ in structure (explanatory / methodological / concise).

**(b) Multi-task confusion.** If a task6 user prompt is appended to the *original* prompt (which asked for EMA adaptation), the example trains two contradictory tasks at once. **Mitigation:** user prompts are rewritten cleanly with the new task's framing, not appended to existing ones.

### Stage 3 — Verifier

Pure-Python deterministic checker. For task5: parse the assistant output, extract `(species, NOAEL, HED, MRSD, safety_factor)`, recompute HED via FDA BSA factor, recompute MRSD = HED / safety_factor, compare to stated values with 10% relative tolerance. For task6: parse the assistant output for required ICH M4S(R2) subsection headings in order; flag missing or out-of-order; flag in-vivo-before-in-vitro genotox.

If the verifier rejects, the example is discarded and a new one is sampled. Reject rate is monitored: task5 currently ~4% (rounding edge cases on tiny MRSDs), task6 ~25% (source prose lacks routable content).

### Stage 4 — Persist

JSONL with `{messages: [system, user, assistant], meta: {task, section_type, ...params}}` — schema-compatible with the existing SFT pipeline.

---

## Domain-knowledge guardrails baked into the generator

The audit revealed that naive generation produces regulatory errors that pass the verifier but would fail an FDA reviewer. Hard exclusions baked into the sampler:

| Guardrail | Why |
|---|---|
| Exclude oncology from MRSD task | ICH S9 §2.2.3: oncology FIH dosing uses STD10/HNSTD with 1/10 rule, not NOAEL/HED. Mixing oncology + NOAEL/MRSD trains the model to give wrong answers for oncology programs. |
| Most-sensitive-species selection requires ≥2 species | Real §2.6.6 picks the species with the *lowest* HED across the toxicology package. A single-species generator skips a meaningful regulatory step. |
| Reject sentence fragments in source prose (`is_well_formed`) | Source corpora often contain mid-paragraph cuts that produce lowercase-starting "sentences." These would teach the model to emit broken prose. |
| Strip FDA-labeling section numbers (`13.1 Carcinogenesis,...`) | These are USPI/PI label conventions, not ICH M4S(R2). Letting them through trains the model on cross-format contamination. |
| Generated Brief Summary, not first source sentence | First source sentence is often a topic-specific finding ("Tadalafil was not carcinogenic..."), which makes a poor general opener and biases the section. |

These guardrails are documented in code comments tied to the regulatory citation that motivated them.

---

## What this approach **does not** solve

1. **Distribution mismatch from real submissions.** Synthetic data follows our generator's distribution; real sponsor §2.6.x has more variety, more nuance in adversity language, more cross-references. → addressed by Option B (real §2.6.x scraping) as parallel long-tail.

2. **Non-checkable regulatory judgment.** Adversity calls, weight-of-evidence integration, novel-target safety extrapolation. Requires LLM-judge supervision and ultimately human review.

3. **Cross-section consistency over a full document.** Each task generates one section in isolation. Document-level coherence (§2.6.6 NOAEL == §2.6.7 table NOAEL == §2.7.4 reference) needs a multi-section generator.

These three are explicit deferrals to v7+ (RL with checker reward) and v8 (human-in-the-loop deployment).

---

## Approach extensions for future tasks (task7–9)

| Task | Sampler | Verifier | Notes |
|---|---|---|---|
| task7 phase-gating | proposed Phase + trial duration | encoded ICH M3(R2) Table 1 | trivial — Table 1 is 15 cells |
| task8 §2.6.7 tabulated | §2.6.6 narrative + ICH template choice | template-conformance checker | 34 ICH templates as Python dataclasses |
| task9 adversity-language | study conclusion text + target phrasing | exact-match against ICH adversity vocabulary | source: existing FDA labels |

All three follow the **checker-first** principle.

---

## Auditable trail

Each task generator file is paired with:
- Verifier module (`backend/lib/galaxy/ai/drug_discovery/*.py`)
- Quality baseline script (`scripts/baseline_v6_task_quality.py`) — runs verifiers on generated output
- Generated JSONL committed to repo for reproducibility

All four are versioned together so any future model regression can be traced back to corpus changes.
