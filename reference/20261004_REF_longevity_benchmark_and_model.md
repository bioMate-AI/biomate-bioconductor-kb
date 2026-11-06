# Reference Note — Longevity Benchmark + Model Paper (PRIMARY)

> Reference note prepared 2026-10-04 to ground BioMate's flagship + RealBio manuscripts.
> Read-only external reference. Full fetched text of the related bioRxiv preprint saved at
> `reference/_fetched/longevitybench_biorxiv_fulltext.txt`.

## Which paper this is

The user's "longevity benchmark and model" paper is almost certainly the **Cell** paper below:
it is the one paper that introduces BOTH an open benchmark AND a family of trained models
(plus an agentic platform) for aging biology. An earlier **benchmark-only** bioRxiv preprint
from the same group is listed under "Alternatives / companion" at the bottom — confirm with the
user which they mean, but the Cell paper is the match for "introduces BOTH a benchmark AND a model."

## Full citation (PRIMARY)

- **Title:** *An open benchmark and language models for AI in aging biology*
- **Authors:** 13 authors incl. Alex Zhavoronkov, Vladimir Naumov, Denis Sidorenko, Alex Aliper,
  Ramin Hasani, Alexander Amini (Liquid AI), Vadim N. Gladyshev (Harvard Medical School / Brigham
  and Women's Hospital), Fedor Galkin. Affiliations: Insilico Medicine, Liquid AI, Buck Institute
  for Research on Aging, Harvard Medical School / Brigham and Women's Hospital.
- **Venue:** *Cell* — **cover study**
- **Year / date:** 2026; published **September 17, 2026**
- **Volume/pages:** Cell **189(19): 5980–5994.e8**
- **URL (publisher):** https://www.cell.com/cell/fulltext/S0092-8674(26)00999-2
  - ScienceDirect mirror: https://www.sciencedirect.com/science/article/pii/S0092867426009992
- **DOI:** not independently verified from an open landing page during this session (publisher page
  returned HTTP 403 to automated fetch). The PII `S0092-8674(26)00999-2` and the volume/page
  `189(19):5980–5994.e8` ARE verified via two independent sources. Confirm the exact DOI from the
  Cell landing page before using it in a bibliography.
- **Access:** Published open access per press materials; verify the open-access link before citing.

> NOTE on provenance: the Cell landing page blocked automated fetching (403). The benchmark design,
> model specs, and headline numbers below are reconstructed from (a) the Insilico Medicine press
> release, (b) the unite.ai writeup, and (c) the Cell search snippet — three independent sources that
> agree. The earlier **bioRxiv LongevityBench preprint** full text (saved locally) corroborates the
> benchmark philosophy and the MMAI Gym framing verbatim. Treat specific numbers as press-sourced
> until checked against the Cell PDF itself.

## Abstract (reconstructed summary — not verbatim)

The paper argues that a model's ability to *emulate aging* and *interpret biodata in the context of
aging* is a key criterion for judging an LLM's utility in biomedical research. It introduces
**LongevityBench**, an open suite of **17 tasks across 5 biodata domains**, uses it to rank
**18 frontier AI systems from 6 developer teams**, and then releases a **family of 5 compact
"Longevity-LLMs" (0.6B–9B params)** fine-tuned on aging data plus an agentic platform,
**"Longevity Claw."** Headline message: carefully curated domain training beats raw model size —
small fine-tuned models match or beat frontier LLMs on aging-biology data interpretation.

(The verbatim abstract of the closely-related bioRxiv preprint is in the saved full-text file.)

## Benchmark design — LongevityBench

- **17 tasks** across **5 biodata domains**: clinical data, genetics, epigenetics, transcriptomics,
  proteomics.
- **Prediction targets** span: human time-to-death / survival from clinical records; biological-age
  inference from omics profiles; effect of genetic perturbations (mutations) on lifespan; age-related
  (age-dependent) expression patterns.
- **Data sources:** NHANES (clinical measurements), GEO (DNA methylation), GTEx (bulk RNA-seq),
  Olink (plasma proteomics), plus genetics resources.
- **Design philosophy:** deliberately avoids rewarding fact-memorization; tests the ability to
  *analyze biological data, recognize patterns, and solve aging-relevant problems.* Each task is
  posed in **multiple question formats** to test whether a model's competence is robust to query
  semantics (i.e., not format-dependent).
- **Scored systems:** 18 frontier systems from OpenAI, Google, Anthropic, xAI, DeepSeek, Moonshot AI.
- **Framing:** serves two purposes — (1) a leaderboard for selecting tools, (2) a *training/development
  target*; it is a module inside the group's **Multi-Modal AI (MMAI) Gym for Science** pipeline
  (SFT + reinforcement fine-tuning against annotated biodata).

## Model design — Longevity-LLMs (L-LLMs)

- **5 compact open-source models, 0.6B–9B parameters.**
- **Base architectures:** Liquid AI **LFM2** family and Alibaba **Qwen3 / Qwen3.5** families.
- **Training:** fine-tuned on aging-specific clinical + multi-omics data via the **MMAI Gym for
  Science** (supervised fine-tuning + reinforcement fine-tuning).
- Released openly (e.g., `LiquidAI/LFM2-2.6B-Longevity`, `LiquidAI/LFM2-1.2B-Longevity` on
  Hugging Face).

## Agentic platform — Longevity Claw

- Open-source **agentic research platform** embedding **L-Qwen3.5-9B** with scientific tools:
  gene-set enrichment, biological aging-clock calculation, population-level profiling,
  evidence retrieval & synthesis, candidate target evaluation & prioritization.
- Applied autonomously across the **14 hallmarks of aging**, nominating **328 genes** as potential
  intervention targets; nominations showed **up to 5.6-fold** statistically-significant enrichment
  vs. independently published aging targets; one gene (**KDM1A**) independently validated as
  lifespan-extending in *C. elegans*.

## Headline results / claims

- **No single frontier model** was strongest across all 5 data types.
- Hardest task: **predicting biological age directly from omics** — even the largest frontier models
  underperformed.
- The compact L-LLMs **matched or exceeded all 16 frontier systems** evaluated.
- **L-Qwen3.5-9B** = highest overall score among all **26 AI systems** tested (aggregate rank score
  **4.4**), beating every frontier model incl. Google Gemini 3.1-Pro. Next: L-LFM2-2.6B (7.6),
  L-Qwen3-1.7B (7.8).
- Specific: **0.868 concordance on DNA-methylation age prediction** (L-Qwen3.5-9B) vs **0.685** for
  the best frontier model.
- **Core thesis:** *curated scientific training data + domain-specific optimization matter more than
  model size for specialized biological applications* — and open infrastructure (benchmark + models +
  agent) should be released to the community.

## How it frames contribution / evaluation (structure cues for OUR papers)

1. **Argue the domain is the right test:** aging is information-rich, multi-scale, multi-modal — an
   ideal probe for whether an AI has a *coherent internal model of biology* vs. surface pattern-matching.
2. **Expose a gap:** no existing benchmark tests interpretation of these heterogeneous biodata types
   in the aging context.
3. **Benchmark → leaderboard → weaknesses:** rank many frontier systems, show nobody wins everywhere.
4. **Benchmark-as-training-target:** position the benchmark not just as a scoreboard but as a
   *development target* inside a training pipeline (MMAI Gym).
5. **Deliver models that beat the frontier at small size:** the "David vs Goliath" headline.
6. **Close the loop with an agent + real biology:** Longevity Claw nominates targets, with an
   enrichment-vs-literature control and one wet-lab-validated hit — i.e., claim-to-evidence ends in a
   concrete, checkable biological result.
7. **Open-source everything** as the community/credibility play (Cell cover study).

## How this should inform BioMate's flagship + RealBio papers

- **Benchmark-and-model-in-one-paper is a proven top-venue template.** Our flagship can mirror it:
  introduce the capability benchmark (RealBio-style execution grading) AND show BioMate's system
  beating general baselines on it, in one arc.
- **"Benchmark as a development target, not a scoreboard"** is exactly our CLAUDE.md
  benchmark-driven-development philosophy — cite this paper as external precedent that a benchmark's
  purpose is to *steer model/system improvement*, not to report a number.
- **"Curated domain grounding > raw size"** maps directly onto BioMate's thesis that the
  system/environment (indexed workflows, tools, QC loop) — not just the LLM — is the product. Use it
  to justify small-model / on-prem positioning and the "model is one component of a composite system"
  memory.
- **End claim-to-evidence on real biology with a control + one validated hit** (their KDM1A /
  5.6-fold enrichment pattern). Our RealBio execution-grading story should likewise terminate in a
  concrete, independently-checkable biological/output result, not just accuracy tables.
- **Multi-format-per-task robustness** (same task, many question phrasings) is a design idea worth
  borrowing for our routing/param-prefill stability benchmarks.

## Alternatives / companion papers (for the primary session to confirm)

- **LongevityBench: Are SotA LLMs ready for aging research?** — Zhavoronkov, Sidorenko, Naumov,
  Pushkov, Zagirova, Aladinskiy, Unutmaz, Aliper, **Galkin** (Insilico Medicine; Buck Institute;
  Jackson Laboratory). bioRxiv, posted **2026-01-30**, DOI **10.64898/2026.01.12.698650**
  (v2). URL: https://www.biorxiv.org/content/10.64898/2026.01.12.698650v2 — This is the
  **benchmark-ONLY** earlier preprint (evaluates commercial models; no trained model released). Full
  text saved locally at `reference/_fetched/longevitybench_biorxiv_fulltext.txt`. It is the companion
  / precursor to the Cell paper, NOT the "benchmark + model" paper.
- **The End of Aging Clocks: Training Foundation Models to Reason in Aging and Longevity** — bioRxiv,
  DOI 10.64898/2026.03.28.714980. Introduces Longevity-LLM v0.1 (Qwen3-14B, SFT+RFT; ~4.34-year MAE
  epigenetic age). A model-focused companion. URL:
  https://www.biorxiv.org/content/10.64898/2026.03.28.714980v1
