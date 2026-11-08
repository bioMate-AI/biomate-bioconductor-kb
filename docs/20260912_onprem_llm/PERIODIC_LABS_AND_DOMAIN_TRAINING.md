# Periodic Labs (strict-domain AI-for-Science) + domain-text training plan for BioMate

Two inputs converge here: (1) a case study of **Periodic Labs** — a strict-domain AI4S lab whose
recipe is almost exactly our intended path — and (2) the **domain-text-resources survey** giving the
commercial-safe corpora to execute the same recipe for bioinformatics.

## Part 1 — Periodic Labs: who they are and how they build for a strict domain
Sources: [a16z](https://a16z.com/announcement/investing-in-periodic-labs/),
[Contrary Research](https://research.contrary.com/company/periodic-labs),
[HyperAI](https://hyper.ai/en/stories/1e9ac8c903b2b6ef401eec65c77632ce),
[Forbes](https://www.forbes.com/sites/iainmartin/2026/05/07/former-openai-researcher-to-raise-500-million-for-ai-science-startup/).

- **What:** AI *scientists* + **autonomous laboratories** for the physical sciences (materials,
  chemistry, physics). North star: discover a high-temperature superconductor. Founded 2025 by
  **Liam Fedus** (ChatGPT co-creator, ex-OpenAI VP Research) and **Ekin Doğuş Çubuk** (led DeepMind
  GNoME materials discovery). Seed $300M (a16z, Bezos, Schmidt); reportedly raising at **$7.5B**.
- **Model — "Periodic Neon" (1T params), built on a strict-domain recipe:**
  1. **Start from an open-weight base** — fine-tune **Kimi K2.6** (open weights). *We start from Qwen.*
  2. **Mid-training (intermediate training) on scientific literature + code** — the domain-knowledge
     injection channel. *Exactly the "中训练 = main channel for domain knowledge" point in the post.*
  3. **RL on proprietary experimental datasets** — reward from **physical reality** (the lab).
  4. **Closed loop:** autonomous lab produces data → AI learns experiments → AI designs/executes new
     experiments → more data. Compute: ~**1,300 H200** GPUs; stack Megatron/SGLang/Miles/Ray.
- **Their own framing:** results were achieved under a *severe compute disadvantage* (1,300 H200 vs
  100k Blackwell) — the **data flywheel + domain mid-training**, not raw scale, is the moat.

### Why this matters to us (near-identical path)
| Periodic Labs | BioMate on-prem LLM |
|---|---|
| Strict domain: materials/chemistry | Strict domain: bioinformatics |
| Open-weight base (Kimi K2.6) | Open-weight base (Qwen3.8-27B) |
| **Mid-training** on domain literature + code | **Mid-training** on bio literature + tool docs + code (this plan) |
| RL on proprietary experimental data | RL/SFT on our proprietary tool/workflow DB + exec logs + corrections |
| Autonomous-lab data closed loop | Self-evolving loop (production logs → verify → improve) |
| Moat = data flywheel + domain mid-training | Same |

**Takeaway:** a $7.5B strict-domain lab independently converged on the recipe we've been assembling.
Two refinements to adopt: **(a) use MID-training (distributional bridge), not pure continued-
pretraining**, and **(b) the proprietary-data flywheel is the moat** — our 300M DB + exec logs +
corrections are the analog of their autonomous-lab data.

## Part 2 — Domain-text resources (survey `wp4z8w0wo`, adversarially verified)
Commercial-on-prem **SAFE to train on**:
| Resource | Size | License | Best use |
|---|---|---|---|
| **peS2o** (AllenAI/S2ORC) | ~40M OA papers, ~42B tok | **ODC-BY** (commercial-OK; per-paper meta) | domain mid-training (literature) |
| **PMC OA — `oa_comm` dir ONLY** | full text | CC0/CC-BY/BY-SA/BY-ND | mid-training (filter out oa_noncomm CC-BY-NC trap) |
| **Biostars** Q&A | large | **CC-BY-4.0** | SFT: tool/error-diagnosis Q&A |
| **Galaxy Training Network** | ~537 tutorials/35 topics | **CC-BY-4.0** | SFT + **decomposition** (multi-step tutorials) |
| **nf-core** pipelines/docs | many | **MIT** | code/param/workflow tasks |
| **Bio-protocol** (CC-BY subset) | post-2023 | CC-BY-4.0 (author choice; skip CC-BY-NC) | protocol Q&A + decomposition |
| **BioProBench/BioProCorpus** | 22,413 protocols / 523,784 tasks | license **unconfirmed** — verify | protocol tasks (verify license first) |
| **UltraMedical** | ~410K instructions | license **unconfirmed** — verify | medical SFT/preference |

**Eval-only (hard):** LAB-Bench, BixBench (frontier agents ~21%) — benchmarks, not training data.
**AVOID / restricted:** PMC `oa_noncomm` (CC-BY-NC), bioRxiv redistribution (mining OK via
Requester-Pays S3, no re-hosting/derivative redistribution), **KEGG** (proprietary), non-OA PubMed
full text. Always check per-article/per-directory license.

**Canonical recipe to reuse:** **Meditron GAP-Replay** — 48.1B tokens = clinical **G**uidelines +
**A**bstracts + **P**apers + ~1% general **Replay** (anti-forgetting). Our bioinformatics analog below.

## Part 3 — Recommended plan (mirrors Periodic + Meditron, commercial-safe)
1. **Mid-training** (distributional bridge: ~70–85% original/general replay + 15–30% domain) on the
   Qwen 27B — domain mix: **peS2o (bio subset) + PMC oa_comm + nf-core code + GTN + Biostars + our
   internal DB text (`scientific_context`, `usage_guide`, workflow descriptions, `real_exec_err`)**.
   *Internal DB text is our highest-value, license-clean, on-domain source — count it first.*
2. **SFT** on grounded task data (routing/param/autofix/decomposition — the multi-task plan) +
   Biostars/GTN/protocol Q&A + UltraMedical (license permitting).
3. **RL / self-evolving loop** on proprietary signal: exec-verified outcomes + corrections (our
   flywheel = Periodic's autonomous-lab loop).
4. **Train-in vs RAG:** TRAIN-IN reasoning/style/protocol-logic/routing-conventions/error patterns;
   keep **volatile catalog/schema/DB facts in RAG** (our finding + GAP-Replay principle).
5. **Cleaning:** dedup (MinHash), decontaminate vs RealBio/LAB-Bench/BixBench, per-article license filter.
6. **Scale:** a 27B needs only a **modest domain-token budget to move the needle** (GAP-Replay used
   ~48B tokens at 70B; far less suffices for narrow task lift) — quality/mix ≫ raw volume.
