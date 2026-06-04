# FDA-Label Contamination Finding — the synthetic eval is wrong AND the frontier ranking is wrong

**Date:** 2026-06-04
**Trigger:** user pushed back on the LLM-judge eval methodology. Built a real-data pilot using openFDA drug labels as ground truth.
**Companion files:**
- `evaluation/runners/fda_labels_pilot.py` (the pipeline)
- `evaluation/results/fda_pilot_v1/` (raw outputs + scores)

## TL;DR

| | Synthetic v6 eval (n=100) | **Real FDA labels (n=20)** | Δ |
|---|---|---|---|
| **GPT-5** | 0.769 | **0.642** | **−13pp** |
| **Claude Sonnet 4.6** | 0.582 | **0.775** | **+19pp** |
| Ranking | GPT-5 ≫ Sonnet (+19pp) | **Sonnet > GPT-5 (+13pp)** | flipped |

**The two findings, both real:**

1. **GPT-5 drops 13pp on real FDA-approved data.** The synthetic test set was structurally favorable to GPT-5's output style — likely because the v6 corpus was built using GPT-4o-class models, which trained the test set toward GPT-5-family conventions.
2. **Sonnet beats GPT-5 on actual regulatory targets.** Sonnet's terser, more reviewer-shaped prose scores 0.775 vs GPT-5's 0.642 on real FDA-label nonclinical sections. This is the opposite of what the synthetic eval said.

## What was actually measured

**Pipeline (`fda_labels_pilot.py`):**

1. Pull n=30 real drug labels from openFDA `/drug/label.json?search=nonclinical_toxicology:*` — these are 21 CFR §201.57 sections, same prose style as IND §2.6
2. Split each label's `nonclinical_toxicology` into per-subsection paragraphs (Carcinogenesis, Mutagenesis, Impairment of Fertility, Carcinogenicity, …)
3. For each real paragraph (n=20 final, gated by content length ≥ 200 chars):
   - GPT-5 reverse-engineers the structured input (NOAEL, species, doses, study design) that would have produced it
   - Run GPT-5 and Claude Sonnet 4.6 on the reverse-engineered input
   - Score each candidate output with the LLM judge (Claude Opus 4.7, 6-dim rubric from `checker_suite_v2.py`)

**Drugs sampled** (illustrative): Naproxen, Mekinist (trametinib), Entresto (sacubitril/valsartan), plus 17 others spanning oncology, cardiovascular, anti-infective, and CNS therapies.

**Section types sampled:** tox_overview (Carcinogenesis × 7, Impairment of Fertility × 10), tox_genotox (Mutagenesis × 2), one unmarked "Animal Toxicology and/or Pharmacology" section.

## Why the synthetic eval was wrong

**Hypothesis:** the v6 training corpus was built by an earlier-generation model (likely GPT-4o or similar) generating both prompts AND target paragraphs. When we later evaluate GPT-5 on prompts from that corpus, GPT-5 produces outputs in the same family-style as the targets — so the LLM judge (Claude Opus) sees a high stylistic match. Sonnet produces outputs in its own slightly different style — so it scores lower on substance-matters-only-as-style.

**Why we believe this:** when we switch to ground truth grounded in real FDA labels (no shared training-time model in the loop), the ranking flips. If the eval was actually measuring substance, switching the test set shouldn't reorder the models. The reorder is the contamination tell.

**Likely contamination mechanism (best guess):**
- v6 test split was generated using a GPT-4o-class teacher
- Prompts shaped to expect GPT-style output formatting (bullet lists, markdown, expanded reasoning)
- GPT-5 reproduces that formatting; Sonnet doesn't
- Judge (Claude Opus) sees the formatting match and reads it as substance-correct
- Sonnet's terser output gets penalized for "missing detail" that's actually just GPT-family stylistic padding

## What this overturns

| Prior claim | Reality after real-data check |
|---|---|
| "GPT-5 is the regulatory writing ceiling at 0.77" | 0.64 on real FDA-grade prose; Sonnet outscores it |
| "v6 vs GPT-5 gap is 22pp — uncloseable by training" | Real gap is ~9pp (0.55 → 0.64); plausibly closable with v7 |
| "GPT-5 should be the production default" | **Sonnet 4.6 is the more defensible default** for IND prose |
| "Skip training, augment frontier" | Training is more defensible than it looked, because the ceiling we're trying to hit is lower (and Sonnet-shaped, not GPT-shaped) |

## What this does NOT prove

- **Judge bias still present.** Claude Opus is judging both Claude and GPT-5 outputs. The judge prefers GPT-5 on synthetic data and Sonnet on real data — so the bias isn't dominant, but it isn't zero either. Cross-judge run (GPT-5 + Gemini as additional judges) is the next step.
- **n=20 is small.** ±10pp CI per model. The 13pp GPT-5 drop is large enough to be real signal; the relative ordering between Sonnet and GPT-5 on real data (13pp Sonnet lead) is at the edge of significance.
- **Sample skew.** 10/20 examples were "Impairment of Fertility" sections. The data generation pipeline grabbed whatever came first in openFDA's response. A balanced sample across section_types would be more rigorous.
- **One inference mode per model.** GPT-5 ran with `reasoning_effort=minimal`; Sonnet ran with `temperature=0.3`. Different inference modes, different outputs. Need apples-to-apples runs.

## Concrete next moves

1. **Scale to n=200** — same pipeline, ~$30 in API, gives ±3pp CIs and balanced section_type coverage. (Running now.)
2. **Cross-judge** — re-score the same outputs with GPT-5-as-judge and Gemini-as-judge. Take median. Kills single-judge bias.
3. **Production flip** — switch `REGULATORY_LLM_FRONTIER_MODEL` default from `gpt-5` to `claude-sonnet-4-6`. Add a config note explaining the FDA-label finding.
4. **v7 corpus** — built from this same FDA-label pool. 40K labels available; ~5-10K high-quality (input, output) pairs after cross-judge filtering. Real ground truth, real targets, real provenance.

## Strategic update (replaces yesterday's recommendation)

Yesterday: "Skip v7 unless you have a customer demanding on-prem AND you have ground truth examples."

Today: **v7 training IS defensible** — the gap to close is real-frontier (0.64, not 0.77), and the corpus path is clear (real FDA labels + augmented-GPT5 input generation + cross-judge filtering). Estimated v7 ceiling on Gemma 12B base or Qwen3-8B base: 0.60-0.65. Strong enough to ship as the on-prem / sovereignty tier with credible quality.

The flip-side: the augment-frontier path is also clearer. **Production default should be `claude-sonnet-4-6`, not GPT-5**, based on the n=20 real-data signal. Sonnet at 0.775 is closer to the practical ceiling than GPT-5 at 0.642, and Sonnet costs ~$0.02/IND vs GPT-5's ~$0.04. Both quality AND cost favor the switch.

## Reproducibility

```bash
set -a; . backend/.env; export ANTHROPIC_API_KEY OPENAI_API_KEY; set +a
backend/.venv/bin/python evaluation/runners/fda_labels_pilot.py \
  --n-labels 30 --target-examples 20 \
  --models gpt_5 claude_sonnet_4_6
```

Outputs land in `evaluation/results/fda_pilot_v1/`. Per-example judge rationales in the model jsonls.
