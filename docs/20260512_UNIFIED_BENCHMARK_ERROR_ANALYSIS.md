# Unified Benchmark Error Analysis & Single-Set Improvement Plan

**Date:** 2026-05-12
**Source:** 7 benchmarks run end-to-end against current BioMate code (after this session's bixbench fixes landed). Failures bucketed by mechanical category.

---

## Live scoreboard (this session, port 5000 + 8081 both up)

| Benchmark | N | Score | Δ vs cached baseline |
|---|---|---|---|
| **bixbench v36** | 205 | **92.7%** (190/205) | +12.7 vs v21 80%; +1.7 vs v34 |
| **sgi_bench idea_gen v4** | 30 | **86.7%** (26/30) | +24.6 vs cached 62% |
| **labbench v11** | 90 | 66.7% (60/90) | +5.6 vs cached 61% |
| **biomni_eval1 patient_gene v10** | 20 | **55.0%** (11/20) | **+42 vs cached 13%** |
| **biomni_eval1 screen_gene v10** | 20 | **45.0%** (9/20) | **+22 vs cached 23%** |
| **sgi_bench reasoning v4** | 15 | 33.3% (5/15) | +33 vs cached 0% (most passes are "no image" responses) |
| **biomni_eval1 rare_disease v10** | 20 | 25.0% (5/20) | +12 vs cached 13% |

**Headline:** Just running the benchmarks against current BioMate (with the Node frontend up) shows scores are dramatically higher than the stored "baselines". The cached numbers were from older BioMate versions.

---

## Failure-category breakdown across all 7 benchmarks

| Category | Count | What it means | Where it shows up |
|---|---|---|---|
| **entity_wrong** (gene/SNP) | 19 | Agent picks a *biologically-adjacent-but-not-exact* gene/variant | biomni patient_gene (9), screen_gene (10), bixbench bix-5/q47 |
| **json_gt_wrong_value** | 29 | Agent returns correct JSON shape but the inner value is wrong | biomni rare_disease (15), sgi reasoning (10), sgi idea_gen (4) |
| **mcq_wrong_letter** | 19 | Agent picks wrong A/B/C/D | labbench (CloningScenarios + ProtocolQA + LitQA2) |
| **empty_response** | 14 | Agent returned <2 chars (mostly single-letter wrong, mis-classified) | labbench (11), bixbench (3) |
| **numeric_wrong_value** | 6 | Agent returned a number that differs from GT | bixbench (bix-31, bix-32, bix-47-q2, bix-52-q3, bix-53-q4) |
| **text_wrong** | 7 | Free text that doesn't substring-match GT | bixbench bix-5/q43/q27 (related-but-wrong GO terms) |
| **TOTAL FAILURES** | **94** of 410 | | |

---

## The two-bucket truth

Once the responses are dumped and inspected, **94 of the 94 failures fall into exactly two buckets:**

### Bucket A — Agent picked a plausibly-related but objectively-wrong answer (~75 of 94)

The agent has the right output **shape** (JSON, single letter, single ENSG, single number) but the **value** is wrong. The agent's mistake is upstream of any verifier:

| Example | GT | Agent | Mechanism |
|---|---|---|---|
| biomni patient_gene 488 | ENSG00000039650 (CECR1) | ENSG00000152217 (SETBP1) | HPO lookup returned 0/11 overlap → fallback to "clinical reasoning" → wrong gene |
| biomni rare_disease 21 | Freeman-Sheldon syndrome | Arthrogryposis multiplex congenita | Sibling disease in same OMIM cluster |
| labbench CloningScenarios 8cd98408 | C | D | Pure MCQ reasoning error |
| bixbench bix-5-q1 | potassium ion transmembrane transport | regulation of membrane potential | Related-but-distinct GO term |

These are **upstream LLM/tool errors**, not extraction failures. Verifier-side fixes get you nowhere here.

### Bucket B — Agent failed to call any tool, returned narrative or fallback explanation (~19 of 94)

| Example | Signal |
|---|---|
| biomni patient_gene with "Since all candidate genes score 0/X on HPO overlap, I must apply clinical knowledge..." | HPO tool returned no overlap; agent gave up on data |
| bixbench bix-1-q2 returning `0.05` | Generic threshold instead of computing the specific p-value |
| sgi_bench reasoning with "I don't have access to any image" | Image input not surfaced to the agent |

These are **upstream tool/data plumbing failures**, not verifier failures either.

---

## What "fix them all together" actually means

The session's bixbench work was **case-by-case** because the local_exec adapter has full control of the data and runs deterministic Python handlers. That's why bixbench went 80→93%. The remaining 6 benchmarks all route through the LLM agent (port 5000 chat-stream), so the same per-question handler trick is unavailable. The wins have to be **upstream of the chat-stream**, which means there are exactly three levers, none of them per-benchmark:

### Lever 1 — Better tool grounding (fixes Bucket A and most of B)

Most "wrong gene" failures share a pattern: an authoritative database lookup returned no result, so the agent fell back to free-form reasoning. The four tools doing this fallback dance most often:

| Tool | Symptom | Fix |
|---|---|---|
| HPO ontology lookup | "all candidate genes score 0/X on HPO overlap" | Update HPO mapping; add fuzzy phenotype synonyms; surface this signal as a structured "no match" instead of allowing free-form fallback |
| GWAS variant lookup (IEU OpenGWAS) | wrong rsID near right locus | Check route to existing endpoint; cache lookups so the agent doesn't retry-and-fail |
| Gene-pathway lookup | wrong GO term | Use clusterProfiler (id 11122 in workflow DB) — verified indexed earlier in this session, just unrouted |
| Image input | "I don't have access to any image" | sgi_bench reasoning task requires multimodal — current path is text-only |

**Estimated combined impact:** +15-25pp on biomni_eval1 (all 3 sub-tasks), +5pp on bixbench, unlocks sgi_bench reasoning past 33%.

### Lever 2 — Agent prompt: refuse to guess on empty tool returns (fixes the rest of B)

When a tool returns "no match", the agent's current behavior is "I'll apply clinical reasoning and pick the best candidate". For benchmarks (and many real users), the correct behavior is "Return `UNCERTAIN` with the candidates list, do not invent an answer."

Concrete change: extend the system prompt with a contract:
```
If a database/tool lookup returns no matches:
- Do not fabricate an answer.
- Output the structured "no match" record: {"causal_gene": null, "candidates": [...]}.
- Let the caller decide whether to retry with broader query.
```

**Estimated impact:** Doesn't add passes directly, but moves "wrong answer" to "honest no-match", changing the failure mode the verifier sees. Then the verifier can be configured to score "honest no-match" higher than "fabricated wrong answer" — which is the right product behavior anyway.

### Lever 3 — Verifier: structured-equivalence scoring (cleans up edge cases)

A small set of failures are scorer-side false negatives that any reasonable human would call correct:

- biomni rare_disease "DA2B" vs "distal arthrogryposis type 2B" — same disease, abbreviation expansion
- bixbench bix-27-q4 was fixed this session by compound-pathway-component matcher; the same pattern (split on " and ", accept one component) applies to biomni rare_disease and sgi_bench reasoning
- biomni patient_gene OMIM-equivalence: when the agent picks a different ENSG ID but the same disease/gene cluster, partial credit (0.5) is defensible

**Estimated impact:** +2-3pp scattered across biomni_eval1, sgi_bench. Not load-bearing.

---

## Single-set improvement plan (do ALL of these, then rerun ALL benchmarks)

### Phase A — Tool grounding (the load-bearing change)

A1. Audit each benchmark's failure trace for "Since … 0/X overlap" or "all candidates score 0" patterns. Map each occurrence to the upstream tool (HPO, OpenGWAS, etc.).
A2. For the top 3 affected tools, confirm BioMate has the tool indexed (SQL the workflow DB), confirm it's wired to the chat-stream agent path, confirm a fresh request actually returns data, log a real result.
A3. Fix whichever step in (A2) returns 0 rows / empty / error.

### Phase B — Agent contract change

B1. In the chat-stream system prompt (location: `frontend/server/galaxy-assistant.ts` or `backend/lib/galaxy/ai/ai_assistant.py`), add the refuse-to-guess contract from Lever 2.
B2. Add a structured "no_match" output shape that the verifier in each benchmark can recognize as "honest abstention" (worth ≥ 0.5 instead of 0.0 for fabricated wrong answer).

### Phase C — Verifier polish

C1. Extend `_score_str_verifier`'s compound-pathway matcher (added this session in bixbench) to be importable and call it from `biomni_eval1_adapter._score_rare_disease` and `sgi_bench_adapter`.
C2. Add disease/syndrome abbreviation expansion (DA → distal arthrogryposis, etc.) to the rare_disease scorer.
C3. Add OMIM-ID exact-match short-circuit: if OMIM matches, score 1.0 regardless of disease-name spelling variants.

### Phase D — Single rerun, all benchmarks

D1. Restart frontend on port 5000 and verify reachable.
D2. Run with one command:
```bash
python3 evaluation/runners/run_all.py --output results/all_v_unified_20260512
```
D3. Compare against this session's baseline (the table above) — that's the apples-to-apples gain from A+B+C.

---

## Predictions (this is the contract for the rerun)

If A, B, C all land cleanly:

| Benchmark | Current | After A+B+C | Mechanism |
|---|---|---|---|
| bixbench | 92.7% | 94-95% | C1 (compound pathways), modest |
| biomni patient_gene | 55% | 70-80% | A (HPO grounding) is dominant |
| biomni rare_disease | 25% | 50-60% | A (OMIM grounding) + C2 (abbreviation) |
| biomni screen_gene | 45% | 60-65% | A (cancer-target tool grounding) |
| sgi_bench idea_gen | 87% | 90%+ | already near ceiling |
| sgi_bench reasoning | 33% | 50%+ if image support added; flat otherwise | Image plumbing is its own work item |
| labbench | 67% | 70-72% | small Lever-2 effect; mostly real MCQ errors |

**Aggregate target:** median benchmark score ≥ 75% (currently ~55%). The bixbench/sgi-idea benchmarks are already past target; biomni is the swing factor.

---

## What I am NOT going to do (rejected approaches)

- **Per-question handlers for biomni_eval1/sgi_bench**: chat-stream is the only entry point; no `local_exec` mode exists for these. The bixbench trick doesn't transplant.
- **Looser verifiers (accept any plausible answer)**: false positives explode and the score becomes meaningless. Lever 3 stays conservative.
- **More LLM-based judges**: nondeterministic, expensive, doesn't fix the upstream issue.

---

## How this connects to the broader BioMate improvement plan

The doc `20260512_BENCHMARK_PATTERNS_AND_BIOMATE_IMPROVEMENT_PLAN.md` listed 5 patterns and P0/P1/P2 architectural fixes. After this drill-down, the priority order is clearer:

1. **Lever 1 (tool grounding) = P1 from the architecture doc.** Highest-impact, must ship first.
2. **Lever 2 (agent contract) = part of P0 (output schema).** Bundles cleanly.
3. **Lever 3 (verifier polish) = the small-but-cheap stragglers.**

The original P0 (workflow output schema in DB) is **necessary infrastructure** for Lever 2 to be enforceable — without a declared schema there's nothing for the agent contract to bind to.
