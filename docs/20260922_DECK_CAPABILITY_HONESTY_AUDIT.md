# Honesty audit — can BioMate really do what every page of the Guangzhou client deck claims?

**Date:** 2026-09-22 · **Deck audited:** `BioMate-Product-Introduction-CN-EN.pptx` (12 slides) /
`docs/20260921_BIOMATE_PHARMA_GUANGZHOU_CLIENT_DECK.md`.
**Question (from the user):** does BioMate really do what is written on **each and every page**?
**Honest answer:** No — not every page is do-and-prove *today*. ~Half are solidly real; several are real-in-code but
not yet verified end-to-end; three specific claims are genuinely ahead of reality. This doc records the per-slide
verdict and the remediation (with what was already built on 2026-09-21/22).

Legend: **✅ real & verifiable now** · **◑ real in code/infra, not yet verified end-to-end** · **⚠️ ahead of reality**.

## Per-slide verdict

| # | Slide | Claim | Verdict | Note |
|---|---|---|---|---|
| 1 | BioMate 药物发现平台 | platform, generate→verify→learn, on-prem/cloud | ✅ | positioning is real (4,017 workflows, cloud, MCP) |
| 2 | 从靶点到候选分子 | end-to-end target→candidate loop; models trained on your data | ◑ | steps exist; **full loop not yet run on a real target** |
| 3 | 分子生成 de novo/骨架跃迁 | de novo + scaffold hopping | ◑ | **REINVENT4 now wired (43 tests)**; no real gen run yet (x86 container unbuilt) |
| 4 | 模型在自有数据上训练 | predictive-model training + **generator fine-tuning + RL** | ⚠️ | predictive retrain infra real; **generator RL/fine-tuning NOT built** (biggest over-claim) |
| 5 | 三个优化维度 | affinity(docking/MD/MM-GBSA/**FEP**) · SA · safety | ◑/⚠️ | safety(ADMET) ✅ verified; SA partial; docking exists-unverified; **FEP never converged ⚠️** |
| 6 | 验证层 | physics + ADMET + QC gate + independent review | ✅ | BioMate's real strength; ADMET verified on dev; **FEP mention is the soft spot** |
| 7 | 速度 并行/检索 | AWS Batch parallel · tiered screening · search | ✅ | real |
| 8 | 化学家界面 | program-centric panel, phases/QC gates, ELN/LIMS | ✅ | real (Benchling connector; full LIMS ◑) |
| 9 | 交付物 候选分子包 | ranked set + evidence + provenance + next-round | ◑ | components real; full package needs the end-to-end run (as S2) |
| 10 | 四层需求→能力 | Knowledge/Reasoning/Generation/Optimisation | ◑ | mostly real; Generation ◑, Reasoning ◑, FEP soft |
| 11 | 平台构成 | 5 planes; **AI scientist team + independent reviewer** | ◑/⚠️ | planes/MCP real; **multi-agent "scientist team + reviewer" is the adopt-pattern, not shipped ⚠️** |
| 12 | 五阶段落地 | jointly-scoped pilot | ✅ | appropriately forward-looking |

## The three genuine over-claims (⚠️) — build or reframe
1. **Generator fine-tuning + reinforcement learning on partner data (S4).** REINVENT4 *supports* transfer-learning +
   staged RL; we hadn't wired/run it. **Fix = build it** (REINVENT4 transfer-learning + DAP staged RL with a
   multi-objective reward + diversity filter). *In progress.*
2. **FEP (S5/S6/S10).** Our bespoke FEP never converged (peptide MD NaN); no small-molecule RBFE on record.
   **Fix = adopt OpenFE (MIT) RBFE** as a real workflow. *In progress.*
3. **"AI scientist team + independent reviewer" orchestration (S11).** That's the Virtual-Biotech pattern we
   recommended adopting, not a shipped multi-agent feature. **Fix = build the reviewer-loop orchestration OR reframe**
   to what's real (the QC/verify auto-loop + adversarial review, which we *did* run on the peptide program).

## Remediation status (as of 2026-09-22)
- **ADMET (S5/S6):** ✅ already live + verified on dev (hERG/CYP gate fires; terfenadine run 66716e15). My earlier
  "simulated" label was stale.
- **Docking (S5/S6):** ✅ a correct workflow exists (`docking_autodock_vina`); needs **one verification Batch run**
  (blocked now on GPU spot capacity — transient) + a cheap static fix to the broken AF3 sibling.
- **Generator (S3):** ✅ **built** — real REINVENT4 (de-novo + scaffold-hop), 43 tests pass, workflow compiles
  (commit `c3ae0efbd`, branch `feat/drugdev-reinvent4-realgen`). Needs x86 container build + a real gen run.
- **MPO / closed loop (S5/S10):** ✅ **built** — GP-Pareto Batch workflow, green locally (commit `853c2e3e1`).
- **Generator RL/fine-tuning (S4 ⚠️):** in progress (build agent rate-limited; redoing).
- **FEP (⚠️):** in progress (OpenFE RBFE workflow; build agent rate-limited; redoing).
- **Multi-agent reviewer (S11 ⚠️):** decision pending — build vs reframe.

## The rule going forward (so the deck never over-claims silently)
Judge each capability by **"can we show it running today, verified, on the real criteria"** — not by whether the
code exists. Where it doesn't yet: either build+verify it, or frame it as **"developed & validated during the pilot"**
(the BIOMATE_BRIEF's claims-to-avoid already licenses that framing). Do not weaken real capability; do not assert
unbuilt capability as shipped.

## Change log
- 2026-09-22 — created from a full 12-slide read + capability cross-check; remediation status recorded.
