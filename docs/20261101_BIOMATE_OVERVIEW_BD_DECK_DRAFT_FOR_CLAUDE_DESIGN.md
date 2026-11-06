# BioMate Overview BD Deck — Draft v0 + Handoff for Claude Design

**Date:** 2026-11-01
**What this is:** An initial draft of a **high-level BioMate introduction / BD deck** — animated, polished to the standard of the drug-development BD deck — but **re-focused off the drug-dev spine** onto: **(1) search-based use cases (literature survey / cited answers, catalog search), (2) faculty research collaboration, (3) hospital-instrument → analysis workflows.** It is an *overview of the platform*, with real use-case UI / information-flow examples cut in as short animated beats.
**Author:** Claude Code (draft). **Next:** Claude Design polishes visuals + animation into the final deck.
**Lineage:** reuses the `biomate-intro-v3` chassis; outline modeled on the drug-dev BD deck (`docs/20260921_BIOMATE_PHARMA_GUANGZHOU_CLIENT_DECK.md` + briefs `20260921_GUANGZHOU_DECK_DESIGN_BRIEF.md`, `20260922_CLAUDE_DESIGN_BRIEF_MARKETING_DECK.md`). Focus content from the faculty / hospital / SYSUCC / search sources cited inline.

---

## 0. Two decisions to settle first (flagged for user / design)
- **D1 — brand palette.** The drug-dev BD deck is **navy + teal (`#0b2545` / `#12808a`)**; the intro-v3 chassis is **cream + navy (`#f6efde` / `#14283a`)**. Pick ONE. *Recommendation: navy+teal, to sit in the same BD family as the drug-dev deck* (the user asked for "as polished as the drug-development deck"). Design decides final.
- **D2 — how the use-case examples appear.** Either (a) **embed the actual animated short demo** (`tutorials_v3/<deck>/… v4 - proposal.zh.html`) in a browser frame that plays on the slide, or (b) **a still UI screenshot** in a browser frame with a short caption. *Recommendation: (a) for the 3–4 hero beats (t0, t3, one instrument, the search flow), (b) elsewhere* — richer, but (a) needs the demo embedded/looped. Design's call on feasibility within `deck-stage.js`.

## 1. Audience, goal, tone
- **Audience:** research-lab PIs/faculty, hospital core-facility directors & clinician-researchers, and institutional partners (e.g. a cancer hospital like SYSUCC). Technical but **not bioinformaticians**.
- **Goal:** land BioMate as *the platform that runs and verifies real biomedical computation by conversation* — breadth first (analysis platform), with search/survey, faculty collaboration, and hospital-instrument analysis as the concrete entry points — and open a focused pilot.
- **Tone:** confident, concrete, credible, **honest**. One headline idea per slide; benefit/outcome over feature lists; 1–3 real big-number stats per section; strong cover + CTA. **中文-primary, English secondary** (bilingual), CJK-safe fonts.

## 2. Design system & animation chassis (reuse, don't rebuild)
- **Engine:** reuse `reference/claude_design/biomate-intro-v3/deck-stage.js` — the bespoke `<deck-stage>` web component (zero third-party libs; fixed 1920×1080 auto-scaled canvas; keyboard nav; speaker-notes bridge; `@media print` → PDF; thumbnail rail; `slidechange` event; slides are hidden-not-unmounted so an embedded demo keeps state). Direct `<section>` children = slides.
- **Animation:** plain CSS keyframes gated by an `.is-playing` class toggled on `slidechange` (as intro-v3 slides 4 & 5 do). **Reuse the two existing harnesses:** (i) the **staged build** (slide 4's `stage-on`/`arrow-on`/`viz-bloom` stagger) → repurpose for the search flow and the instrument→result flow; (ii) the **closed-loop reveal** (slide 5's 4-station + return-arc) → repurpose for the faculty/organoid **learning loop**.
- **Inert:** `data-om-id` / `data-om-validate` are the claude.ai slide-editor's object-model IDs — not animation; ignore/strip.
- **Fix on reuse:** intro-v3 declares `--sans:"Inter"` but never loads Inter (silent fallback). Load the chosen sans (IBM Plex Sans is already loaded) or load Inter.
- **All data-viz = hand-authored inline SVG** (no chart lib), per the house style. Replace any ASCII with vector diagrams.

## 3. Content discipline (hard rules — thread throughout)
From the marketing brief. **This is a BD deck, not an internal report** — confident capability framing only:
- **No method/tool-stack disclosure** externally: no model class, no nf-core / REINVENT / DIA-NN / AWS / GATK names on client slides. Differentiate at the **feature/benefit** level. (Internal names in this doc are for grounding only — do NOT put them on slides.)
- **Breadth number — show ONE clean figure, not two.** Use **"~4,210 indexed workflows · 36 domains · 12,312 tool records"** (these are catalog/index counts — stated as *indexed*, which is true and makes no validation claim). **Do NOT also put the "~1,100 real-execution-validated" subset on the slide** next to it (per user: showing both undercuts the headline). Never phrase the 4,210 as "validated"; "indexed" only. (The validated-subset figure may still be used internally / in a technical appendix if a skeptical audience asks — but not in the headline stat strip.)
- **Lead with the platform, not drug-dev.** Drug discovery is ~200 workflows (~5%); present it, if at all, as a *separate* story, not the spine.
- **NO internal hedging on any slide.** Do not put status markers (✅/🟡/🛑, "registered ≠ validated", "prove-it-in-the-pilot" as a readiness hedge), named capability **gaps** (e.g. digital pathology), self-limiting **boundaries** (e.g. "we don't do ACMG / clinical reporting"), or "roadmap / prototype / not-shipped / emerging / 方向展示 / preview" labels. **If a capability isn't ready to claim, OMIT it — do not show it with a caveat.** (Don't fabricate either: never present a designed mock as a captured "real UI" run — just show it as the product UI without a disclaimer.) Build/demo readiness lives only in §6 (internal notes for the author/designer), never in slide copy.
- **"Protocol generation" = a RESEARCH PROTOCOL** (a new study plan, or a routine-practice protocol), grounded in the literature/standards. Present the **search → survey → research-protocol** arc confidently as a platform capability. (Internal, not a slide: which parts have a real animated demo vs a designed product mock is tracked in §6 — design picks the right visual; no readiness language reaches the slide.)
- Any number on a slide is **real or labeled "illustrative."**

---

## 4. The draft — slide by slide
Each slide: **headline (中文 / EN)** · point · body copy · animation · demo/visual. Reuse intro-v3 layouts where noted.

**S1 · Cover** — 「会思考的虚拟实验室」 / *"BioMate — a virtual lab that thinks."*
Sub: 「用对话驱动真实生物医学计算的 AI 平台——面向科研实验室、医院核心设施，产出每一步都可追溯的结果。」 / *"A conversational AI platform that runs and verifies real biomedical computation — for research labs and hospital core facilities, with results you can trace."* Three pillars (reuse intro-v3 S1): 人机协作 · 自动化工作流 · 证据可追溯. (Founder credit optional.)

**S2 · The bottleneck** — 「数据能产出，分析却卡住了」 / *"Data generation is solved. Turning it into results is the wall."*
Body (reuse intro-v3 S2 three-column skeleton, re-pointed): **速度** 一个分析从排队到结果常以周计；**门槛** 依赖稀缺的生信人力，科研人员无法自助；**可复现** 通用 AI 会幻觉、无验证的 QC、无留痕 = 结论站不住。 (Drop CRO/ADMET/IND line-items.)

**S3 · What BioMate is** — 「用大白话提问，它来做科学——并展示过程」 / *"Ask in plain language. BioMate does the science — and shows its work."*
Two kinds of request: **(a)** 一个**有引用的答案**，几秒钟；**(b)** 一条**经过验证的工作流**，在云端算力上跑完，交回一份报告。 Three steps (reuse intro-v3 S3 verbatim): **Ask**（映射到已验证的工作流）→ **Confirm**（未经确认绝不运行）→ **Results**（QC 分级 · AI 结论 · 自动方法学 · 留痕）.
**▶ DEMO BEAT:** `t0-getting-started` (cold start → one conversation).

**S4 · One platform, the whole analysis stack** — 「一个平台，覆盖整条分析链」 / *"One platform — the whole analysis stack."*
Breadth stat slide (reuse intro-v3 S7 3-card + stat-strip; replace the drug-dev card with a **research/omics analysis** card): 转录组 / 基因组 / 表观组 / 蛋白组 / 单细胞 / 影像 / 变异检测. **Stat strip (one clean figure):** 约 4,210 个已收录工作流 · 36 个领域 · 12,312 条工具记录. (indexed counts — no "validated" claim, and do NOT add the ~1,100 validated subset here.) Conversational front door over all of it.

**S5 · Divider — SEARCH → SURVEY → PROTOCOL** — 「先查文献，再写方案」 / *"From the literature to a study plan."*

**S6 · A cited survey** — 「一个有引用、可辩护的综述」 / *"A cited survey you can defend."*
Flow (staged-build animation, reuse S4 harness): 自然语言问题 → 跨 PubMed / Europe PMC / Semantic Scholar / OpenAlex 并行检索 → 带 `[N]` 标注的综述式答案 + 引用面板. **Differentiator beat (confident):** 每一条引用都是真实可查的——绝不编造文献，参考文献区由检索到的论文直接构建.
*(internal: demo = `m1-search-and-evidence`; §6 notes a v4 refresh.)*

**S6b · From survey to a research protocol** *(new beat — search section is now divider + survey + protocol; design renumbers)* — 「把综述变成一份研究方案」 / *"Turn the survey into a research protocol."*
The second half of the search story — *protocol generation*: from the cited evidence, BioMate drafts a **research protocol** — a **new study plan** (假设 · 设计 · 终点 · 样本量，每一条都链接到支撑它的文献) or a **routine-practice protocol/SOP** (按证据分级：规范 / 同行评审 / 机构) — and points to the **public data that can test it** (GEO / TCGA / CELLxGENE / ClinicalTrials.gov). Closed-loop reveal animation (reuse S5-harness): 证据表 → 研究空白 → 研究方案 → 可行性（样本量 · 效应量 · power）. Confident capability framing — no readiness labels on the slide.
*(internal: no animated demo yet; the "propose a study"/feasibility steps are in-build, so design uses a clean designed product mock of the flow — shown as the product UI, NOT labeled preview/roadmap. See §6.)*

**S7 · Divider — FACULTY RESEARCH** — 「你的方法，我们的执行——共同开发，共同署名」 / *"Your methods, our execution — co-developed, co-authored."*

**S8 · Faculty collaboration** — 「把你的课题，跑成可复现的结果」 / *"Turn your research into reproducible results."*
Collaboration model: BioMate 提供执行基础设施 + GPU/CPU 云算力 + 共同署名 + 学生平台访问；实验室提供领域工具与生物学验证；**联邦式、原始数据不出域**. Hero information-flow (closed-loop reveal animation, reuse S5 harness as a **learning loop**): GWAS summary stats → 映射到免疫细胞类型 → 可复现的靶点-细胞假设（示例：克罗恩病 × Treg）. Plus 自带数据 / 在你的结果上训练模型.
*(internal: demos = `t4-bringing-your-own-data`, `b1-train-custom-model`; present the scGWAS flow as a capability, not a claimed live run — don't fabricate a result.)*

**S9 · Divider — HOSPITAL INSTRUMENTS** — 「设施负责产数据，BioMate 把它变成结果——对话即可，无需写代码」 / *"Your facility generates the data. BioMate turns it into results — by chat, no coding."*

**S10 · Instrument → result** — 「从仪器到结论的一条链」 / *"From instrument to conclusion."*
Instrument→workflow map (staged build) — each instrument lane shown as a clean input→result flow: **RNA-seq**（FASTQ → 差异表达 → 结果+图+方法学）、**质谱蛋白/代谢**（谱图 → 定量 + 通路）、**流式细胞**（.fcs → 免疫分型）、**qPCR ΔΔCq**（Ct → 相对定量）、**酶标仪**（读数 → Z′ · 4PL · IC50）. All driven by chat, no coding. (No status badges, no gaps/boundaries — present the lanes we offer, confidently.)
*(internal: demos = `flow-cytometry`, `lcms-proteomics`, `plate-reader`, `sample-qc`.)*

**S11 · See one full run, end to end** — 「跑一次，读懂一次」 / *"Run it. Read it."*
The run→report story: 实时阶段/步骤进度（SSE）→ QC 闸门 → 运行后三个标签：摘要 / 输出 / 可复现记录（含 SHA-256 校验）. Every number links to its output file.
**▶ DEMO BEAT:** `t3-run-and-report`.

**S12 · Differentiator — traceable evidence** — 「每一个 QC 判定都可追溯到依据」 / *"Every QC decision traces to a citable rule."*
Reuse intro-v3 S8 Gold/Silver/Bronze **evidence-tier** layout: QC decisions made against codified, citable thresholds; full per-run provenance; measured-vs-predicted kept separate. Confident differentiator — this is real and shipped.

**S13 · Deployment & trust** — 「数据和模型都留在你的网络内」 / *"Your data AND the AI model stay inside your network."*
On-prem / data residency — **data AND the AI model stay inside your network**; **model-agnostic — runs on your local models**; access control + full audit logs. (Strong hospital/SYSUCC card; for a SYSUCC presentation add "turns your own data into results that keep improving.")

**S14 · How we'd start — a focused pilot** — 「从一条高频通道开始，4–6 周」 / *"A focused 4–6 week pilot, on one high-volume lane, on real data."*
Jointly scoped: hospitals → one lane (RNA-seq or mass-spec) on real data; faculty → one live tool / co-authored study. Acceptance criteria + what we bring (infra, compute, co-development).

**S15 · Closing / CTA** — 「从提问，到可复现的结果——一个会思考、并展示过程的虚拟实验室」 / *"From question to reproducible result — a virtual lab that thinks, and shows its work."* (reuse intro-v3 S9; CTA 开始试点 / Start a pilot.)

**S16 · Appendix** — domain-coverage table (indexed counts across the 36 domains) + a one-line engagement/contact block. (No "scope & boundaries / limitations" block — this is BD; readiness/boundaries stay in the internal §6, never on a slide.)

---

## 5. Demo insertion map (which animated beat goes where)
| Slide | Demo | Deck path | Status |
|---|---|---|---|
| S3 | cold start / first conversation | `tutorials_v3/t0-getting-started/t0 … v4 - proposal.zh.html` | ✅ v4 rendered |
| S6 | search & cited evidence | `tutorials/m1-search-and-evidence-walkthrough.html` | ⚠️ older-style (recommend v4 refresh) |
| S8 | bring-your-own-data; train model | `tutorials_v3/t4-bringing-your-own-data`, `…/b1-train-custom-model` | ✅ v4 rendered |
| S10 | instruments | `tutorials_v3/{flow-cytometry,lcms-proteomics,plate-reader,sample-qc}` | ✅ v4 rendered |
| S11 | full run → report | `tutorials_v3/t3-run-and-report` | ✅ v4 rendered |

## 6. INTERNAL — build/demo readiness (NOT slide content; for the author/designer only)
*This section never appears on a slide. It exists so design shows the right visual and nobody fabricates a captured run. All client-facing copy above is confident capability framing per §3.*
1. **Search/survey demo is older-style** — `m1-search-and-evidence` is the right content (cited answer, "does not invent references") but not a v4 animated render. **Recommend authoring a v4 `search-and-evidence` short demo** to match the rest, especially since the survey/cited-answer flow is a headline section (S6).
2. **Research-protocol generation is EMERGING, with NO demo yet** — the "propose a study" (study-plan) + feasibility steps are in-build (not shipped); the routine-practice SOP path is the Grounded Standards prototype. S6b must use a **labeled "方向展示 / preview" storyboard/mock**, present it as direction (not a shipped feature), and the survey half (S6) as the shipped, demoed part. A v4 demo for the protocol flow is a follow-on once the study-proposer step is built + tested.
3. **target-identification** — v3 demo under redesign + chat-path not wired; keep it out of this deck for now.
4. **scGWAS faculty hero** has no faculty-framed demo and needs an ECR push to be live — present as capability + info-flow, not a claimed live run.
5. **SYSUCC-specific variant** — if a SYSUCC-facing version is wanted, swap S13/S14 for the on-prem + hospital-HPC-entry-point framing and use the honest-numbers line; keep clinical-AI incumbents (Yidu/Tianshu) acknowledged, never compared.

## 7. Handoff ask to Claude Design
Build the final animated deck from this draft on the `deck-stage.js` chassis: settle D1 (palette) + D2 (embed-demo vs screenshot); rebuild S4/S8/S10 diagrams as designed inline-SVG; repurpose the two intro-v3 animation harnesses (staged build → S6/S10; closed-loop → S8); **follow §3 content discipline — confident BD framing, NO status markers / gaps / boundaries / roadmap labels on any slide (omit what we don't claim, don't caveat it); keep readiness in §6 only**; bilingual 中文-primary. Return `BioMate Overview v1` (+ `.zh`) rendering cleanly at 1920×1080 headless. Claude Code will then re-apply any Chinese narration + record a video if a narrated version is wanted.
