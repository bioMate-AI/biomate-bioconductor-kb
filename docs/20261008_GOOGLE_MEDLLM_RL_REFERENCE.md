# Google medical-LLM RL training recipe — reference & implications for the on-prem LLM program

**Date:** 2026-10-08
**Author:** Yaoyun Zhang · xiaoni5122@gmail.com
**Scope:** External-paper reference note. Extracts a Google open-weight medical-LLM training recipe and maps its *training-recipe* lessons (not its vision stack) to our on-prem 9B decomposition program. All program items below are labelled **REFERENCE**, not commitments.

---

## 0. TL;DR — which paper, and the honest match verdict

The paper that matches the user's description is **MedGemma** (Google — Health AI / Google Research / Google DeepMind), with its **MedGemma 1.5** 2026 update.

- **Primary, fully verifiable source:** *MedGemma Technical Report*, arXiv:**2507.05201** (submitted 2025-07-08; HTML v4). All numeric detail in this note is quoted from this report.
  Link: https://arxiv.org/abs/2507.05201 · HTML: https://arxiv.org/html/2507.05201v4
- **2026 open release:** *MedGemma 1.5* (release reported 2026-01-13; 4B multimodal, 128K context, ~200k synthetic medical questions added, reported under **Apache 2.0**). I could **not** cleanly parse a separate 1.5 technical-report PDF (candidate id arXiv:2604.05081 did not extract), so I do **not** cite 1.5-specific method numbers; treat 1.5 as "the newer open weights," and the recipe detail as coming from the 2507.05201 report.
- **Weights (open):** https://goo.gle/medgemma (Hugging Face; Gemma-compatible infra). Sizes **4B** (multimodal) and **27B** (text-only; 27B multimodal in the appendix). License: the paper header lists **CC BY 4.0**; the open weights ship under Google's Health AI Developer Foundations terms, and MedGemma 1.5 is reported as **Apache 2.0**.

**Feature-by-feature verdict (user's identifying features a–f):**

| # | Feature | MedGemma | Verdict |
|---|---|---|---|
| a | Google (DeepMind / Research / Health AI) | Yes | ✅ match |
| b | Multimodal medical LLM | Yes (vision+text→text) | ✅ match |
| c | Open-released weights | Yes (goo.gle/medgemma, HF) | ✅ match |
| d | Small medical-data fraction to preserve generic ability | Yes — **2%** weight (vision encoder stage), **10%** weight (decoder pretraining), rest = original Gemma 3 general mixture | ✅ match |
| e | RL applied directly *without* an SFT stage, **better** than SFT | **Partial** — "all multimodal post-training was performed via RL"; "RL enables better generalization compared to supervised fine-tuning" (§2.2.2). But this is a **qualitative** claim, not a controlled RL-only-vs-SFT-only ablation with matched data; and SFT is still used for some tasks (MIMIC-CXR report style). | ⚠️ partial |
| f | Multiple model sizes evaluated | Yes — 4B and 27B | ✅ match |

**Honest bottom line.** No single paper I could verify matches **all** of (a–f) with feature (e) in its strongest form (a numeric "RL-only beats SFT" ablation across sizes). MedGemma is the real **Google** paper matching 5/6 cleanly, with (e) true only as a qualitative generalization claim. The **clean** "RL-only (no SFT) matches SFT in-distribution and +8 points out-of-distribution" result belongs to a **different, non-Google** paper — **Med-RLVR** (Zhang, Liu, Qin, Naumann, Poon — **Microsoft Research**, arXiv:2502.19655, 2025-02-27), which is **text-only** medical MCQA on a **single 3B** base (Qwen2.5-3B), i.e. it fails (a), (b) and (f). The two together bracket the user's description; neither alone is a perfect fit, and I have not fabricated one that is.

---

## 1. DATA — composition, fraction, mixing, reward data

**Medical datasets & sizes (MedGemma, §2.2):**
- Vision-encoder stage fine-tuned **MedSigLIP** on **33M medical image–text pairs** spanning radiology (CXR, CT, MRI), histopathology, dermatology, ophthalmology.
- Text/QA training drew on MedQA, MedMCQA, PubMedQA, MedExpQA, AfriMed-QA, HealthSearchQA, LiveQA, plus (in the 1.5 release) **~200,000 synthetic medical questions**.

**Fraction vs base general data — the catastrophic-forgetting control (§2.2.2):**
- **Vision-encoder enhancement:** medical data mixed in at **2% weight**; 98% remained the original encoder-training distribution.
- **Multimodal decoder pretraining:** continued pretraining on top of the Gemma 3 checkpoints with medical image data at **10% weight**; the remaining ~90% is the original Gemma 3 mixture. They explicitly **did not add further medical text-only data** here "as the original Gemma 3 mixture was already general-purpose."
- The design intent is stated directly: keep the medical slice *small* and keep the original general mixture dominant so general capability is retained (verified in the retention table — §3 below).

**Curation/filtering:** the report describes assembling curated public medical corpora and de-duplicating against eval sets (MedXpertQA flagged as "not seen during any model development stage"); it does **not** give a full filtering pipeline — treat detailed curation as **not reported**.

**RL reward data construction:** the report states the "recipes for distillation and reinforcement learning were the same as in Gemma 3 development" and does **not** disclose the reward model, verifier design, prompt set, or reference-answer construction for the medical RL. **Reward-data construction: not reported.**

> **What it means for us.** The quantified lesson is the mix ratio: a **2–10% domain slice over a dominant general mixture** was enough to add large medical gains while holding general ability roughly flat. Our regressions (param-prefill `must_not_fill` rising from base **34 → 61** after decomposition SFT; chain-collapse of parallel/mixed) are consistent with a **too-heavy / too-narrow** domain fraction — the opposite of MedGemma's small-slice discipline. REFERENCE: cap the synthetic-decomposition slice and co-train with a dominant general/instruction mixture, rather than SFT-saturating on the narrow synthetic distribution.

---

## 2. TASK DESIGN — what was optimized, and how it was framed for RL

- **Tasks (multi-task):** medical text QA, medical visual QA (VQA-RAD, SLAKE), image classification (CXR findings, dermatology, histopathology, retina), agentic clinical dialogue (AgentClinic), and a separate EHR-QA fine-tune.
- **RL framing (§2.2.2, §5.2):** "all multimodal post-training was performed via RL." A concrete demonstrated RL task is **EHR-QA**: MedGemma 27B was RL-fine-tuned on an EHR-QA training set.
- **Reward signal type:** **not reported** in method detail (inherited from Gemma 3's recipe). The report does not state whether the medical reward was rule/verifiable vs. a preference/judge model — so I will not claim RLVR for MedGemma specifically. (By contrast, the non-Google Med-RLVR is explicitly **rule-based verifiable**: reward **1.0** for an answer matching the gold label in the required format, **−1.0** for format violation, **0.0** otherwise.)
- **Single- vs multi-task:** multi-task across the medical suite; the EHR-QA RL is a task-specific fine-tune on top of the released model.
- **Task-format ↔ eval-format:** tasks are framed to match eval format (MCQA accuracy, classification macro-F1, VQA token-F1, agentic task success), i.e. the training objective is aligned to the reported metric.

> **What it means for us.** Our STAGE-2 harness is already the *verifiable-reward* design MedGemma is vague about, and closer to Med-RLVR's explicit rule reward: `decomp_reward.py` computes `w_node·node_f1 + w_edge·edge_f1 + w_struct·struct_validity − malformed_penalty` against the real catalog (`galaxy_ai_tools.db`), deterministic, ~0 ms/rollout (`docs/20260912_onprem_llm/20261006_DECOMP_STAGE2_GRPO_DESIGN.md §2`). REFERENCE: our reward design is *more* verifiable than the Google recipe; the task→reward→eval alignment they emphasize is exactly our node/edge-F1-is-both-reward-and-metric setup — a strength to lean on, not a gap to close.

---

## 3. EVALUATION — medical gains, the forgetting check, and RL-vs-SFT

**Medical benchmarks & headline gains vs base Gemma 3 (MedGemma 4B unless noted; Tables 3–11):**

| Task | Benchmark | Metric | MedGemma | Gemma 3 | Δ |
|---|---|---|---|---|---|
| Text QA | MedQA | acc | 64.4% | 50.7% | +13.7 |
| Text QA | MedMCQA | acc | 55.7% | 45.4% | +10.3 |
| CXR classification | MIMIC-CXR | macro-F1 | 88.9 | 81.2 | +7.7 |
| CXR classification | **CXR14 (OOD)** | macro-F1 | 50.1 | 32.0 | **+18.1** |
| Medical VQA | VQA-RAD | token-F1 | 49.9 | 33.6 | +16.3 |
| Dermatology | US-Derm MCQA | acc | 71.8% | 52.5% | +19.3 |
| Histopathology | PathMCQA | acc | 69.8% | 37.1% | +32.7 |
| Agentic | AgentClinic-MedQA (27B) | acc | 56.2% | 50.7% | +5.5 |

- **Held-out / OOD:** MedXpertQA ("not seen during any model development stage"), CheXpert-OOD, CXR14-OOD, AgentClinic-MIMIC-OOD — the largest relative gains are on the OOD sets (e.g. CXR14 +18.1), which is the evidence behind the "RL generalizes better" framing.

**Generic-ability retention (the forgetting check, Table 12, non-medical):**

| Benchmark | MedGemma 4B | Gemma 3 4B | Δ |
|---|---|---|---|
| MMLU Pro | 39.1% | 43.6% | −4.5 |
| Global MMLU Lite | 55.5% | 54.5% | +1.0 |
| MMMU (val) | 47.3% | 48.8% | −1.5 |

Characterized as "only minor decreases in performance relative to the general models of the same size" (§4). (Note: at 27B the MMLU-Pro drop was larger, ~−7.3 per the v4 text — the "minor" claim is strongest at 4B.)

**RL-vs-SFT numbers:** the only *numeric* RL result is EHR-QA — RL lifted MedGemma 27B from **86.3% → 93.6%** (Table 14). This is an RL-improves-the-task number, **not** a head-to-head RL-vs-SFT-on-the-same-data table. The RL-beats-SFT claim stays qualitative: "RL enables better generalization compared to supervised fine-tuning" (§2.2.2). **A controlled RL-vs-SFT per-benchmark table: not reported.** (The clean RL-only-vs-SFT numbers — in-dist parity + **+8** OOD — are Med-RLVR's, not Google's.)

> **What it means for us.** Two transferable eval disciplines: (1) **always report an OOD/held-out split** — their headline evidence is OOD generalization, and our real analogue is `decomposition_real` (out-of-synthetic-generator) vs the in-family `decomposition_v2`; the real finding is precisely that synthetic SFT did **not** transfer to real topologies (`20261007_SFT_V3_CLEAN_RETRAIN.md §Honesty`). (2) **Always run a forgetting check** — a non-medical retention panel like Table 12. We have the analogue: the RealBio regression guard (routing / param_prefill / litqa2 / findings). MedGemma's "small-slice → minor drop" is the target; our "narrow SFT → param-discipline regression (34→61)" is the failure mode their recipe is designed to avoid.

---

## 4. LLM ARCHITECTURE — and why most of it does NOT transfer to us

- **Base family / sizes:** Gemma 3; **4B** (vision+text multimodal) and **27B** (text-only primary; 27B multimodal in appendix). Gemma-compatible serving/infra; weights on Hugging Face.
- **Vision encoder:** **SigLIP-400M** (released as **MedSigLIP**), input **896×896** (448×448 for the released MedSigLIP with down-sampled positional embeddings).
- **Image fusion:** "arbitrary image–text interleaving" with **pre-computed visual tokens** fed into the decoder (token-level interleaving; the report does not spell out a separate projector/adapter block — treat exact adapter design as **not reported**).
- **Context length:** **128K**.
- **Trained vs frozen:** staged — encoder fine-tuned on the 33M medical pairs (2% mix); decoder continued-pretrained (10% mix); post-training via distillation+RL. Per-stage frozen/trainable breakdown and full-FT-vs-LoRA: **not reported**.
- **Weights/serving format:** open Gemma-format checkpoints on HF; license CC BY 4.0 (paper) / Apache 2.0 (MedGemma 1.5 release) / Health AI Developer Foundations terms for the weights.

> **What it means for us — the non-transferable boundary.** The entire **vision stack** (SigLIP encoder, 896×896 images, visual-token interleaving, 33M image–text pairs, CXR/path/derm/retina modalities) is **not applicable** to our program. We are **text + a bioinformatics-execution harness**, not imaging; we have no vision encoder to protect and no image modalities to add. What transfers is only the **language-model training recipe** (small domain mix over a dominant general mixture; RL-with-a-reward as the post-train stage; OOD + retention eval discipline; multi-size reporting). Separate cleanly: **recipe = transferable; vision architecture + scale/compute = not.** Their RL ran on large TPU compute with the full Gemma 3 recipe; ours is spot-GPU QLoRA GRPO on a 9B.

---

## 5. Mapping to our program — concrete REFERENCE points (not commitments)

Context: our just-finished finding is that **SFT on synthetic decomposition data overfit our own generator and did not transfer to real topologies** (node/edge-F1 floored on `decomposition_real`), **while regressing param discipline** (param-prefill `must_not_fill` 34→61) — `project_sft_from_gold_result` memory + `20261007_SFT_V3_CLEAN_RETRAIN.md`. We have **already built** a GRPO + catalog-structural-verifier harness (`evaluation/local_trial/train_grpo_decomp.py`, `decomp_reward.py`, `run_grpo_decomp_9b.sh`) but **not run** it (`20261006_DECOMP_STAGE2_GRPO_DESIGN.md`). We also hold a scaling-curve interest (harness dividend vs model size).

**REFERENCE 1 — "RL-direct generalizes better than SFT" argues for running our GRPO-on-verifiable-reward rather than more SFT-on-synthetic.**
Both MedGemma (qualitative: multimodal post-training is RL; RL generalizes better than SFT) and Med-RLVR (numeric: RL-only matches SFT in-dist, **+8 OOD**) point the same way: when the failure is **generalization to out-of-distribution structure** (exactly our synthetic→real transfer gap), RL that directly optimizes the measured reward tends to generalize where likelihood-SFT overfits the generator. This is the precise argument for our STAGE-2 lever: GRPO KL-anchored to the SFT-decomp policy, optimizing node/edge-F1 + structural validity — the thing we actually measure — instead of one more SFT pass on generator output. **Honest caveat:** Med-RLVR's +8 is a single 3B text MCQA result and MedGemma's claim is qualitative; neither guarantees our transfer. Treat as directional support to *run the GRPO arm*, with `decomposition_real` as the arbiter — not a promised gain.

**REFERENCE 2 — "small medical slice preserves generic ability" argues our param/instruction regression came from too-heavy/too-narrow SFT.**
MedGemma kept the domain slice at **2–10%** over a dominant general mixture and saw only minor general-benchmark drops. Our param-discipline regression (34→61 `must_not_fill`) and parallel/mixed chain-collapse look like the symptom of the opposite choice — SFT weighted too heavily on a narrow synthetic distribution. REFERENCE: if we keep any SFT stage, **cap the synthetic-decomp fraction and co-train with a dominant general/instruction + param-discipline mixture** (we already added 854 `must_not_fill` anchors — that is the same instinct, applied as a mix-ratio rather than a bolt-on). Prefer moving the structural learning into **GRPO** (which is KL-anchored and reward-shaped) over heavier SFT.

**REFERENCE 3 — multiple sizes ↔ our scaling-curve interest.**
MedGemma reports 4B and 27B, and its "minor drop" retention claim is **stronger at 4B than 27B** (MMLU-Pro −4.5 at 4B vs ~−7.3 at 27B) — i.e. the recipe's side-effects are size-dependent. REFERENCE for our harness-dividend-vs-size question: run the GRPO/verifier arm at ≥2 sizes (e.g. our 9B and a smaller base) and report **both** the capability lift **and** the retention cost per size, rather than a single-size number. Their data is a reminder that retention and transfer both move with scale, so our scaling curve should track the regression guard, not just the decomposition metric.

**REFERENCE 4 — transferable recipe vs non-transferable stack (keep these separate in any writeup).**
Transferable: (a) small-domain-slice-over-general-mixture; (b) RL-with-reward as the post-train stage for generalization; (c) OOD/held-out + forgetting-check eval discipline; (d) multi-size reporting. **Not transferable:** the SigLIP vision encoder, image-token interleaving, imaging modalities, and the TPU-scale compute — we are text + execution-harness and should not import any of the multimodal design. Our **advantage** over the Google recipe for our task: our reward is an **explicit, deterministic catalog verifier** (stronger than MedGemma's undisclosed medical reward), so our RL signal is auditable in a way theirs is not.

---

## 6. Honesty / open items

- The user's feature (e) in its strongest form ("RL directly without SFT, **numerically** better than SFT, across sizes") is **not** fully met by any single verifiable Google paper. MedGemma meets it qualitatively; Med-RLVR meets it numerically but is **Microsoft, text-only, single 3B**. Reported both rather than force-fitting one.
- MedGemma 1.5 (2026) is the newer open release (Apache 2.0, 128K, +~200k synthetic questions); I could not parse a standalone 1.5 technical-report PDF, so **all numeric method detail here is from arXiv:2507.05201**, not 1.5.
- MedGemma's **reward design / verifier for medical RL is not disclosed** ("same as Gemma 3"); do not cite MedGemma as "RLVR." The RLVR characterization applies to Med-RLVR.
- The only numeric RL result in the MedGemma report is EHR-QA (86.3→93.6); there is **no** controlled RL-vs-SFT per-benchmark table in the paper.

---

## Sources

- MedGemma Technical Report — arXiv:2507.05201 (2025-07-08): https://arxiv.org/abs/2507.05201 · https://arxiv.org/html/2507.05201v4
- MedGemma open weights: https://goo.gle/medgemma · developer page: https://developers.google.com/health-ai-developer-foundations/medgemma
- MedGemma 1.5 (2026 release, Apache 2.0) — reference pages reviewed; standalone report PDF not verified.
- Med-RLVR (non-Google, clean RL-only-vs-SFT reference) — arXiv:2502.19655 (2025-02-27): https://arxiv.org/abs/2502.19655
- Our program: `docs/20260912_onprem_llm/20261007_SFT_V3_CLEAN_RETRAIN.md`; `docs/20260912_onprem_llm/20261006_DECOMP_STAGE2_GRPO_DESIGN.md`; `evaluation/local_trial/{train_grpo_decomp.py,decomp_reward.py,run_grpo_decomp_9b.sh}`; memory `project_sft_from_gold_result`.
