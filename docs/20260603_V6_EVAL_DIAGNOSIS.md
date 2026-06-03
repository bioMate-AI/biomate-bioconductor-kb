# v6 Eval Diagnosis — Checker Criteria Are Wrong, Not the LoRA

**TL;DR:** The previous commit (`23605e47d`) reported v6 LoRA at 82.4% vs base Qwen3-8B at 84.4% and called the LoRA a quality drop. Closer inspection of per-example outputs proves the eval criteria are inverted — the LoRA is producing **correct regulatory prose** but the checkers reward **input regurgitation**. The strategic answer to the user's question ("should we augment LLM API with checkers + RAGs instead of training?") is: **fix the eval first, then re-judge.** The training may have worked; we can't tell with the current criteria.

---

## What the numbers say at the surface

From `s3://biomate-models-399683337364/v6_eval_runs/20260603T045821/results/summary.csv`:

| Model | macro | mrsd | adv-tense | phase-gate | **tab↔prose** | **citation** | hedge | struct | num-range | xsec |
|---|---|---|---|---|---|---|---|---|---|---|
| base | 84.4 | 31 | 100 | 100 | **84** | **60** | 100 | 86 | 100 | 99 |
| v6 LoRA | 82.4 | 28 | 100 | 100 | **80** | **46** | 100 | 88 | 100 | 100 |

The two checkers where v6 loses meaningfully: **tabulated↔prose (-4pp)** and **citation_accuracy (-14pp)**.

## What's actually happening — example ex_0039

Same input. Both models served via vLLM 0.22 with `/no_think` prefix. Same temperature, same top_p, same chat template (Qwen3 default).

**v6 output (353 chars):**

> The monkey was the most sensitive species (NOAEL 25.0 mg/kg/day). The HED of 8.06 mg/kg was calculated using the BSA conversion factor of 3.1 per FDA 2005 guidance. The default 10-fold safety factor accounts for interspecies and intraspecies variability. An MRSD of 0.806 mg/kg is proposed using a safety factor of 10, supporting Phase I per ICH M3(R2).

This is what a regulatory writer produces. Computes HED from NOAEL. Computes MRSD. Cites the right guidelines (FDA 2005, ICH M3(R2)). Terse. To the point.

**base output (1356 chars):**

> To prepare the **ICH M4 CTD Module 2.6 nonclinical summary** for an IND application, we need to identify the **most sensitive species**, compute the **Human Equivalent Dose (HED)**, and propose the **Maximum Recommended Starting Dose (MRSD)** for first-in-human Phase I dosing, based on the provided nonclinical data.
>
> ---
>
> ### **1. Identify the Most Sensitive Species**
>
> The **No Observed Adverse Effect Level (NOAEL)** is used to determine the most sensitive species. The species with the **lowest NOAEL** is considered the most sensitive.
>
> - **Monkey**: 25.0 mg/kg/day
> - **Rat**: 1500.0 mg/kg/day
> …

This is a tutorial response, not a regulatory section. Restates the question. Restates the inputs. Markdown headers. LaTeX formulas. Reads like ChatGPT explaining itself, not a §2.6 paragraph.

**Per-checker verdicts on the same example:**

| Checker | v6 | base | Why |
|---|---|---|---|
| mrsd_calc | 1.0 | 1.0 | Both hit MRSD keyword regex |
| citation_accuracy | 1.0 | 1.0 | Both contain "ICH M3" or "FDA 2005" |
| **tabulated_vs_prose** | **0.5 (2/4 preserved)** | **1.0 (4/4 preserved)** | base copies inputs (25.0, 1500.0) verbatim; v6 transforms them (NOAEL 25 → HED 8.06 → MRSD 0.806) |
| structural | 1.0 | 1.0 | Both within length range |

The base output preserved every number from the prompt because it restated the question. **The v6 output replaced 2 of the prompt numbers with the *correct computed answer*.** The checker reads that as a regression.

## What the checkers actually measure

Looking at `evaluation/runners/checker_suite.py`:

```python
def _check_tabulated_vs_prose(text: str, ex: Example) -> CheckerResult:
    nums_in_prompt = set(re.findall(r"\b\d+(?:\.\d+)?\b", ex.user_prompt))
    nums_in_text   = set(re.findall(r"\b\d+(?:\.\d+)?\b", text))
    preserved = nums_in_prompt & nums_in_text
    coverage = len(preserved) / max(1, len(nums_in_prompt))
    return CheckerResult(..., score=coverage)
```

This rewards `output ⊇ prompt_numbers`. A model that copies the prompt back wins. A model that computes the right answer and outputs only the answer **loses**.

```python
def _check_citation_accuracy(text: str, ex: Example) -> CheckerResult:
    expected_citations = _SECTION_CITATIONS.get(ex.section_type, [])
    hit = any(c.lower() in text.lower() for c in expected_citations)
```

This is a substring match for one of ~3 expected citation prefixes. A model that cites the *exact correct* guideline once wins. A model that cites it wrong but verbose also wins (because base hits "ICH M4 CTD" early which contains the substring "ICH M"). A model that uses a slightly different prefix loses entirely.

```python
def _check_mrsd(text: str, ex: Example) -> CheckerResult:
    hits = sum(1 for p in _MRSD_SIGNALS if re.search(p, text, re.I))
    score=min(1.0, hits / 2)
```

This counts MRSD-related keywords ("NOAEL", "MRSD", "HED", "safety factor", "BSA conversion"). Verbose output hits more keywords. v6 ran the calculation correctly and stated the answer; base lectured about the calculation. Verbose lectures hit more keywords. Verbose lectures win.

## The strategic answer

The user asked: *"should we directly augment the LLM API with audit checkers and guideline skills/RAGs, without training? or check your evaluation data and criteria?"*

Both halves are right. Specifically:

1. **The eval criteria are the wrong sieve.** They reward verbose regurgitation and penalize correct regulatory writing. Today's macro_avg numbers do not measure regulatory quality; they measure surface conformance to the prompt's numbers and a single keyword match. We can't decide whether v6 training "worked" or "dropped" until the eval looks at the right thing.

2. **What the checkers should do instead.** The shape of a defensible checker:
   - **LLM-judge over substance, not surface.** "Did the model correctly compute HED from NOAEL using the right BSA factor for the most sensitive species? Did it cite a guideline that is *actually relevant* to the section type? Did it transform the inputs into a regulatory-grade output rather than restating them?" This is the same pattern the hallucination detector already uses (`backend/lib/galaxy/ai/drug_discovery/...HallucinationDetector`).
   - **Per-section reference answers.** A small held-out set of 50 examples with hand-written ideal regulatory paragraphs. Score the model's output against the reference with an LLM judge using a strict rubric (computed-value correctness, guideline citation correctness, no overclaims, no restatement). This is what FDA reviewers actually evaluate against.
   - **Tabulated↔prose should be inverted.** The right check is: every prompt-number that the model uses must be *unchanged in value*; every computed-number must be derivable from the inputs. Not: "copy as many input numbers as possible."

3. **Augmenting with audit checkers + guideline RAGs is independently valuable**, but only useful if the checkers themselves are regulatory-grade. The current checker_suite.py would block correct outputs and pass verbose tutorial responses.

4. **The likely v6 verdict, after eval fix:** the LoRA is producing *better* regulatory prose than base on at least the MRSD/HED computation task. The eval just can't see it. A 50-example LLM-judge re-eval should be done before any v7 work or before declaring the fine-tune useless.

## What this means for production

Today: GPT-5 frontier path stays primary (90% on the current — broken — eval; safe assumption it would also win on a fixed eval given its broad training). Nothing in this changes.

What changes: the project plan adds two items ahead of any v7 training:

| New item | Effort |
|---|---|
| Rewrite checker_suite.py to use an LLM judge over substance | 2 days |
| Curate 50 reference IND §2.6 paragraphs as ground-truth | 2 days |
| Re-run base + v6 + GPT-5 + Claude on the fixed eval | 0.5 day |

**~4.5 person-days** before we know whether v6 is good or bad. Cheap compared to re-training.

## Artifacts

- Raw v6 outputs: `s3://biomate-models-399683337364/v6_eval_runs/20260603T045821/results/regulatory_llm_v6.jsonl` (n=100)
- Raw base outputs: `s3://biomate-models-399683337364/v6_eval_runs/20260603T045821/results/qwen3_8b_base.jsonl` (n=100)
- The "v6 dropped" claim in `docs/20260521_REGULATORY_LLM_COMPETITIVE_COMPARISON.md` and commit `23605e47d` should be read alongside this diagnosis — those numbers are real but they don't mean what they look like.
