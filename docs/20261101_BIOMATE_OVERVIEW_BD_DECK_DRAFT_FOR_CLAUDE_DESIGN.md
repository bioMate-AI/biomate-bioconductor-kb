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

## 3. Content discipline & honesty anchors (hard rules — thread throughout)
From the marketing brief + the capability-honesty audits:
- **No method/tool-stack disclosure** externally: no model class, no nf-core / REINVENT / DIA-NN / AWS / GATK names on client slides. Differentiate at the **feature/benefit** level. (Internal names in this doc are for grounding only — do NOT put them on slides.)
- **Honest numbers only.** Breadth = **~4,210 indexed workflows · 36 domains · 12,312 tool records**, of which **~1,100 carry recorded real-execution validation** — say it that way; never "thousands validated."
- **Lead with the platform, not drug-dev.** Drug discovery is ~200 workflows (~5%); present it, if at all, as a *separate* story, not the spine.
- **Name the boundaries out loud** (they build trust): BioMate runs the *analysis*, it does **not** produce the graded **clinical/regulatory report** (ACMG variant calling stays a vendor job; GxP-certified provenance is roadmap). **Digital pathology is a known gap** (no Chinese WSI format reader, no pathology foundation model — the FM surface is transcriptomic today). **"Registered ≠ validated"** — mark instrument lanes that are registered-but-unverified as "prove-it-in-the-pilot."
- **Mark prototype/roadmap honestly:** the Grounded Standards Assistant and the full "survey → propose study → measure" pipeline are **prototype/roadmap**, not shipped. There is **no protocol-SOP-writing tool** — frame "protocol" only as *turning intent into a runnable, parameterized pipeline* + retrieving domain parameters/QC thresholds.
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
Breadth stat slide (reuse intro-v3 S7 3-card + stat-strip; replace the drug-dev card with a **research/omics analysis** card): 转录组 / 基因组 / 表观组 / 蛋白组 / 单细胞 / 影像 / 变异检测. **Stat strip (honest):** ~4,210 工作流 · 36 领域 · 12,312 工具记录（其中约 1,100 条有真实执行验证）. Conversational front door over all of it.

**S5 · Divider — SEARCH & EVIDENCE** — 「先问：已经知道了什么？」 / *"First ask: what is already known?"*

**S6 · Search in action** — 「一个有引用、可辩护的答案」 / *"A cited answer you can defend."*
Flow (staged-build animation, reuse S4 harness): 自然语言问题 → 跨 PubMed / Europe PMC / Semantic Scholar / OpenAlex 并行检索 → 带 `[N]` 标注的综述式答案 + 引用面板 + 边界说明. **Differentiator beat:** 两道「绝不编造引用」的护栏——越界的引用标记被判为未引用；参考文献区始终由后端引用对象重建，不让模型自由发挥. Honesty line on-slide: 文献综述写作已可用且有护栏；全自动「综述→提出研究→公共数据验证」管线仍在路线图上.
**▶ DEMO BEAT:** `m1-search-and-evidence` *(older-style render — see §6 gap: a v4 refresh is recommended before this ships).*

**S7 · Divider — FACULTY RESEARCH** — 「你的方法，我们的执行——共同开发，共同署名」 / *"Your methods, our execution — co-developed, co-authored."*

**S8 · Faculty collaboration** — 「把你的课题，跑成可复现的结果」 / *"Turn your research into reproducible results."*
Collaboration model: BioMate 提供执行基础设施 + GPU/CPU 云算力 + 共同署名 + 学生平台访问；实验室提供领域工具与生物学验证；**联邦式、原始数据不出域**. Hero information-flow (closed-loop reveal animation, reuse S5 harness as a **learning loop**): GWAS summary stats → 映射到免疫细胞类型 → 可复现的靶点-细胞假设（示例：克罗恩病 × Treg）. Plus 自带数据 / 在你的结果上训练模型.
**▶ DEMO BEATS:** `t4-bringing-your-own-data`, `b1-train-custom-model`. *(Honesty: the scGWAS lane is real + container-built but needs an ECR push to go live — present the capability, not a claimed live result.)*

**S9 · Divider — HOSPITAL INSTRUMENTS** — 「设施负责产数据，BioMate 把它变成结果——对话即可，无需写代码」 / *"Your facility generates the data. BioMate turns it into results — by chat, no coding."*

**S10 · Instrument → result** — 「从仪器到结论的一条链」 / *"From instrument to conclusion."*
Instrument→workflow map (staged build). **Hero lanes (✅ ready today):** RNA-seq（FASTQ → 差异表达 → 结果+图+方法学）、质谱蛋白/代谢（谱图 → 定量+通路）. **Registered, prove-it-in-the-pilot (🟡):** 流式细胞 / qPCR ΔΔCq / 酶标仪 Z′·4PL. **Name the honest gap + boundary on-slide:** 数字病理（中国切片格式与病理大模型）尚是空白；ACMG 临床变异报告仍由专业厂商完成，BioMate 做的是分析而非临床报告.
**▶ DEMO BEATS:** `flow-cytometry`, `lcms-proteomics`, `plate-reader`, `sample-qc`.

**S11 · See one full run, end to end** — 「跑一次，读懂一次」 / *"Run it. Read it."*
The run→report story: 实时阶段/步骤进度（SSE）→ QC 闸门 → 运行后三个标签：摘要 / 输出 / 可复现记录（含 SHA-256 校验）. Every number links to its output file.
**▶ DEMO BEAT:** `t3-run-and-report`.

**S12 · Differentiator — traceable evidence** — 「每一个 QC 判定都可追溯到依据」 / *"Every QC decision traces to a citable rule."*
Reuse intro-v3 S8 Gold/Silver/Bronze **evidence-tier** layout (reframe sources beyond FDA/ICH to community standards + peer-reviewed benchmarks): codified, citable thresholds; full per-run provenance; measured-vs-predicted kept separate. Optional on-slide vision note: a **Grounded Standards Assistant** for regulated-domain Q&A (label *prototype*).

**S13 · Deployment & trust** — 「数据和模型都留在你的网络内」 / *"Your data AND the AI model stay inside your network."*
On-prem / data residency; **model-agnostic — runs on your local models**; access control + audit logs; **research-use framing** (not clinical decision support). (Strong hospital/SYSUCC card; for a SYSUCC presentation add the on-prem + "turns your own data into results that keep improving" line.)

**S14 · How we'd start — a focused pilot** — 「从一条高频通道开始，4–6 周」 / *"A focused 4–6 week pilot, on one high-volume lane, on real data."*
Jointly scoped: hospitals → one lane (RNA-seq or mass-spec) on real data; faculty → one live tool / co-authored study. Acceptance criteria + what we bring (infra, compute, co-development).

**S15 · Closing / CTA** — 「从提问，到可复现的结果——一个会思考、并展示过程的虚拟实验室」 / *"From question to reproducible result — a virtual lab that thinks, and shows its work."* (reuse intro-v3 S9; CTA 开始试点 / Start a pilot.)

**S16 · Appendix** — full domain-coverage table (honest counts); **scope & boundaries** block (registered≠validated; ACMG/clinical-report boundary; no protocol-SOP writing; target-ID & accession-resolver are MCP-only, not yet in chat; survey-pipeline & Grounded Standards are roadmap/prototype; digital-pathology gap); sources. Optional SYSUCC honest-numbers variant.

---

## 5. Demo insertion map (which animated beat goes where)
| Slide | Demo | Deck path | Status |
|---|---|---|---|
| S3 | cold start / first conversation | `tutorials_v3/t0-getting-started/t0 … v4 - proposal.zh.html` | ✅ v4 rendered |
| S6 | search & cited evidence | `tutorials/m1-search-and-evidence-walkthrough.html` | ⚠️ older-style (recommend v4 refresh) |
| S8 | bring-your-own-data; train model | `tutorials_v3/t4-bringing-your-own-data`, `…/b1-train-custom-model` | ✅ v4 rendered |
| S10 | instruments | `tutorials_v3/{flow-cytometry,lcms-proteomics,plate-reader,sample-qc}` | ✅ v4 rendered |
| S11 | full run → report | `tutorials_v3/t3-run-and-report` | ✅ v4 rendered |

## 6. Gaps to resolve before this ships (flagged)
1. **Search/survey demo is older-style** — `m1-search-and-evidence` is the right content (cited answer, "does not invent references") but not a v4 animated render. **Recommend authoring a v4 `search-and-evidence` short demo** to match the rest, especially since the survey/cited-answer flow is a headline section (S6).
2. **No protocol-generation capability/demo** — do NOT promise a protocol-writing demo; S6/appendix frame "protocol" as runnable-pipeline + domain-parameter retrieval only.
3. **target-identification** — v3 demo under redesign + chat-path not wired; keep it out of this deck for now.
4. **scGWAS faculty hero** has no faculty-framed demo and needs an ECR push to be live — present as capability + info-flow, not a claimed live run.
5. **SYSUCC-specific variant** — if a SYSUCC-facing version is wanted, swap S13/S14 for the on-prem + hospital-HPC-entry-point framing and use the honest-numbers line; keep clinical-AI incumbents (Yidu/Tianshu) acknowledged, never compared.

## 7. Handoff ask to Claude Design
Build the final animated deck from this draft on the `deck-stage.js` chassis: settle D1 (palette) + D2 (embed-demo vs screenshot); rebuild S4/S8/S10 diagrams as designed inline-SVG; repurpose the two intro-v3 animation harnesses (staged build → S6/S10; closed-loop → S8); keep the copy's honesty anchors verbatim; bilingual 中文-primary. Return `BioMate Overview v1` (+ `.zh`) rendering cleanly at 1920×1080 headless. Claude Code will then re-apply any Chinese narration + record a video if a narrated version is wanted.
