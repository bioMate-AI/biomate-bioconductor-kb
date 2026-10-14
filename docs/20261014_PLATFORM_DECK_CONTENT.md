# BioMate Platform Deck — Content (EN + CN) — source of truth for HTML / PPTX / video

**Date:** 2026-10-14
**Purpose:** The platform-wide reframe of `BioMate_BD_Deck_CN_v2.pptx` — from a *drug-discovery* deck to a *general AI bioinformatics platform* deck centred on **research domains, instrument-connected workflows, and search**, with drug discovery as one domain among many. This file is the single source of truth rendered into: (a) an auto-play HTML walkthrough (video source, like `reference/claude_design/tutorials_v2/`), (b) a `.pptx`, (c) the intro-video narration — each in **EN and CN**.
**Register:** formal, factual, no salesy superlatives. Capability framing only (WHAT we deliver), no internal program/method disclosure. Numbers are ground-truth (CLAUDE.md, 2026-10-05): **4,210 workflows · 42 domain tags · 12,312 tools; 1,092 workflows with clean real-execution evidence.**

---

## Slide 1 — Title
**EN:** BioMate — The AI bioinformatics platform · From any instrument and dataset to a reproducible, decision-ready result · Search · Run · Verify · Learn
**CN:** BioMate — AI 生物信息平台 · 从任意仪器与数据到可复现、可决策的结果 · 检索 · 运行 · 验证 · 学习

## Slide 2 — The problem (research, not just drug R&D)
**EN title:** Bioinformatics today is fragmented
- Tools scattered per domain — RNA-seq, variants, proteomics, cryo-EM each need different, separately-licensed software
- Instruments are islands — a sequencer, flow cytometer, LC-MS or plate reader each writes files someone copies by hand
- Expert workflows aren't captured — how an analyst chose a method or threshold lives in their head, not the system
- Results don't accumulate — runs, QC and negative results aren't fed back into a reusable knowledge base
- Compute is outsourced and costly; multiple specialist packages bought and maintained separately
- Data security & compliance — research data is core IP; external tools and outsourcing carry leakage risk

**CN title:** 当下生物信息分析的痛点
- 工具按领域割裂 — RNA-seq、变异、蛋白质组、冷冻电镜各需不同且需单独授权的软件
- 仪器成为孤岛 — 测序仪、流式、液质、酶标仪各自产出文件，需人工搬运
- 专家工作流难沉淀 — 分析师如何选方法、定阈值只存在脑中，未被系统记录
- 结果不积累 — 运行、质控与阴性结果未回流到可复用的知识库
- 计算依赖外包且成本高；多套专业软件分别采购与维护
- 数据安全与合规 — 研发数据是核心知识产权，外部工具与外包存在泄露风险

## Slide 3 — Why BioMate
**EN title:** One platform, every domain, your environment
- **One platform across domains** — search, run and read results for any bioinformatics task in one workspace
- **Instrument connectivity** — real connectors for sequencers, flow cytometers, LC-MS, plate readers, cryo-EM, liquid handlers and ELN/LIMS
- **Search built in** — literature, databases and a 4,210-workflow catalog, routed to the right method
- **Unified execution** — cloud (AWS Batch / Nextflow) or on-prem, with QC gates and a closed-loop that learns from each run
- **Private & auditable** — data stays in your environment; deterministic execution; versioned, traceable evidence

**CN title:** 一个平台，覆盖全领域，部署在你的环境
- **一个平台贯通各领域** — 任意生物信息任务的检索、运行与结果解读，都在同一工作台
- **仪器连接** — 为测序仪、流式、液质、酶标仪、冷冻电镜、移液机器人及 ELN/LIMS 提供真实连接器
- **内置检索** — 文献、数据库与 4,210 个工作流目录，智能路由到正确方法
- **统一执行** — 云端（AWS Batch / Nextflow）或本地部署，带质控门与从每轮运行中学习的闭环
- **私域可审计** — 数据不出域；确定性执行；结果可版本化、可溯源

## Slide 4 — Research domains (the breadth)
**EN title:** 42 domains · 4,210 workflows · 12,312 tools
- **Transcriptomics** (1,695) — bulk & single-cell RNA-seq, differential expression, splicing, spatial
- **Genomics** (756) — assembly, annotation, alignment, QC
- **Variant calling** (181) — germline/somatic SNV/indel/SV (GATK, DeepVariant, nf-core/sarek)
- **Epigenomics** (265) — ATAC-seq, ChIP-seq, bisulfite, Hi-C
- **Single-cell** (100) — clustering, annotation, trajectory, ambient-RNA removal
- **Proteomics** (186) — DIA/DDA MS, label-free quant, peptide ID
- **Drug discovery** (200) — ADMET, docking, QSAR, PBPK — *one domain among many*
- **Cryo-EM** (19), metabolomics, metagenomics, immunology, structural biology, imaging, systems biology…
- *Footer:* 1,092 workflows carry clean real-execution evidence (validated subset)

**CN title:** 42 个领域 · 4,210 个工作流 · 12,312 个工具
- **转录组学**（1,695）— bulk 与单细胞 RNA-seq、差异表达、剪接、空间转录组
- **基因组学**（756）— 组装、注释、比对、质控
- **变异检测**（181）— 胚系/体细胞 SNV/indel/SV（GATK、DeepVariant、nf-core/sarek）
- **表观基因组学**（265）— ATAC-seq、ChIP-seq、甲基化、Hi-C
- **单细胞**（100）— 聚类、注释、拟时序、环境 RNA 去除
- **蛋白质组学**（186）— DIA/DDA 质谱、非标定量、肽段鉴定
- **药物发现**（200）— ADMET、对接、QSAR、PBPK — *众多领域之一*
- **冷冻电镜**（19）、代谢组、宏基因组、免疫、结构生物学、影像、系统生物学……
- *脚注：* 其中 1,092 个工作流具备干净的真实执行证据（验证子集）

## Slide 5 — Instrument-connected workflows
**EN title:** From the bench instrument to the analysis, in one flow
- **Flow cytometer** (FCS) → gating → marker-positive subset quantification (immunophenotyping)
- **Plate reader** (BMG/BioTek/Tecan) → ELISA standard-curve → titers by group
- **LC-MS** (Thermo/Waters/Bruker/SCIEX) → proteomics / metabolomics
- **Sequencers** — Illumina BaseSpace, Nanopore MinKNOW → FASTQ → the matching pipeline
- **Cryo-EM** (Thermo EPU) → single-particle reconstruction
- **Liquid handlers** — Opentrons OT-2 / Flex (driven from chat); **ELN/LIMS** — Benchling
- *Footer:* real connectors in `backend/lib/integrations/`; residency-aware (on-prem / mount / cloud)

**CN title:** 从实验台仪器到分析，一气呵成
- **流式细胞仪**（FCS）→ 圈门 → 标志物阳性亚群定量（免疫表型）
- **酶标仪**（BMG/BioTek/Tecan）→ ELISA 标准曲线 → 分组滴度
- **液质联用**（Thermo/Waters/Bruker/SCIEX）→ 蛋白质组 / 代谢组
- **测序仪** — Illumina BaseSpace、Nanopore MinKNOW → FASTQ → 对应流程
- **冷冻电镜**（Thermo EPU）→ 单颗粒重构
- **移液机器人** — Opentrons OT-2 / Flex（对话驱动）；**ELN/LIMS** — Benchling
- *脚注：* 真实连接器位于 `backend/lib/integrations/`；感知数据驻留（本地 / 挂载 / 云）

## Slide 6 — Search & evidence
**EN title:** Find the right method, and the evidence behind it
- **Workflow routing** — describe the goal in plain language; BioMate selects from 4,210 workflows and explains why
- **Accession → workflow** — paste a GEO/SRA/EMPIAR accession; it resolves modality and the matching pipeline
- **Literature** — grounded literature Q&A with citations (not fabricated references)
- **Databases & structures** — activity/SAR, structure and similarity search; FTO/patent for applicable domains
- *Footer:* every routing decision is explained; every number traces to its source file

**CN title:** 找到正确的方法，以及背后的证据
- **工作流路由** — 用自然语言描述目标，BioMate 从 4,210 个工作流中选择并解释原因
- **编号 → 工作流** — 粘贴 GEO/SRA/EMPIAR 编号，自动识别模态并匹配流程
- **文献** — 带引用的文献问答（不编造参考文献）
- **数据库与结构** — 活性/SAR、结构与相似性检索；适用领域的 FTO/专利
- *脚注：* 每个路由决策都有解释；每个数字都可溯源到其来源文件

## Slide 7 — Product interface (RNA-seq example)
**EN title:** A project-centric workspace
- One workspace per project — chats, data, workflows and runs together
- The workflow panel — an RNA-seq differential-expression run: params before it runs, phases live, one merged Results report after
- Attach data or bind an instrument/accession; preview every input as an object, not a path string
- Pilot a small subset before a full run; override parameters and QC thresholds inline
- *Footer:* results write back to your ELN / data systems

**CN title:** 以项目为中心的工作台
- 每个项目一个工作空间 — 对话、数据、工作流与运行集中在一起
- 工作流面板 — 一次 RNA-seq 差异表达运行：运行前看参数、运行中看阶段、运行后看合并的结果报告
- 挂载数据或绑定仪器/编号；每个输入都作为对象预览，而非一串路径
- 全量前可先跑小样试点；参数与质控阈值可就地调整
- *脚注：* 结果可回写到你的 ELN / 数据系统

## Slide 8 — Execution + QC
**EN title:** Run anywhere, with quality gates and a closed loop
- **Execution** — AWS Batch + Nextflow DSL2 in the cloud, or on-prem; jobs stream results to storage
- **Phases & steps** — every run is broken into inspectable phases and tool steps
- **QC gates** — automatic mid-run checks that never silently pass a failed result; halt → expert review → resume
- **Auto-loop** — on a recoverable failure, remediate parameters and re-run, with the was→now diff shown
- **After-run report** — one merged Results view (findings + every output previewed) + a reproducibility record
- *Footer:* same mechanism across all domains — RNA-seq, variants, proteomics, cryo-EM, ADMET

**CN title:** 随处运行，带质控门与闭环
- **执行** — 云端 AWS Batch + Nextflow DSL2，或本地部署；任务将结果流式写入存储
- **阶段与步骤** — 每次运行拆分为可检视的阶段与工具步骤
- **质控门** — 运行中自动检查，绝不默默放过失败结果；暂停 → 专家复核 → 恢复
- **自动循环** — 可恢复失败时自动调整参数重跑，并展示 was→now 差异
- **运行后报告** — 一个合并的"结果"视图（发现 + 每个输出预览）+ 一份可复现记录
- *脚注：* 所有领域共用同一机制 — RNA-seq、变异、蛋白质组、冷冻电镜、ADMET

## Slide 9 — Private / auditable engineering (carries over)
**EN title:** Private deployment, auditable, reproducible
- **Data stays in your environment** — local / private deployment as the default; compute runs inside your estate
- **Reference data & models localized** — train and fine-tune on your own data
- **Deterministic execution** — the same input yields the same output at inference
- **Auditable** — scores shown as formulas and explanation columns; evidence sources traceable
- **Versioned** — exploration happens in an evolution layer; production runs only accepted versions, with a change record
- **Permissions & integration** — access by team/project/person; two-way with ELN / compound library / LIMS

**CN title:** 私域部署，可审计，可复现
- **数据不出域** — 本地/私有化部署为默认；计算在自有环境内完成
- **参考数据与模型本地化** — 可在自有数据上训练与微调
- **确定性执行** — 同一输入在推理阶段得到一致输出
- **可审计** — 评分以公式与解释列呈现，证据来源可追溯
- **版本化** — 探索在演化层完成，线上只执行已接受的版本，变更留有记录
- **权限与对接** — 按团队/项目/人员授权；与 ELN / 化合物库 / LIMS 双向打通

## Slide 10 — Value
**EN title:** What the platform delivers
- **Cost** — one platform replaces many single-point tools; less compute outsourcing; pilot-before-full-run reduces wasted runs
- **Speed** — from data to insight faster; QC gates and auto-loop reduce rework
- **Integration** — instruments, data systems and domains unified; results write back
- **Knowledge** — runs, QC and expert corrections accumulate as reusable, auditable assets

**CN title:** 平台能带来什么
- **成本** — 一个平台替代多套单点软件；减少计算外包；先试点后全量，减少无效运行
- **效率** — 从数据到洞见更快；质控门与自动循环减少返工
- **整合** — 仪器、数据系统与领域统一；结果回写
- **知识** — 运行、质控与专家纠正沉淀为可复用、可审计的资产

## Slide 11 — Deliverable
**EN title:** The deliverable is a reproducible result — for any domain
- **Findings** — a plain-language summary with the key numbers, each traced to its output file
- **Outputs** — every file the run produced, previewed inline by type (table, image, structure, VCF…)
- **Reproducibility record** — workflow, parameters, versions, checksums, methods & citations
- **Next step** — what the result supports, and what to run next
- *Footer:* the same package whether the task was RNA-seq, variant calling, an instrument readout, or ADMET

**CN title:** 交付的是可复现的结果 — 适用于任意领域
- **发现** — 自然语言摘要与关键数字，每项溯源到其输出文件
- **输出** — 运行产出的每个文件，按类型内联预览（表格、图像、结构、VCF……）
- **可复现记录** — 工作流、参数、版本、校验和、方法与引用
- **下一步** — 结果支持什么，下一步该运行什么
- *脚注：* 无论任务是 RNA-seq、变异检测、仪器读出还是 ADMET，交付同一套结果包

## Slide 12 — Collaboration / landing path
**EN title:** How we start
- **01 Survey & data audit** — your domains, instruments, data systems and goals
- **02 Connect** — wire up instruments / ELN / accessions; bring a representative dataset
- **03 Run** — route to the right workflow, run with QC, read the merged Results report
- **04 Verify** — compare against your established method; retrospective on your historical data
- **05 Deploy** — cloud or on-prem; permissions, versioning and audit configured for your team

**CN title:** 如何开始
- **01 调研与数据审计** — 你的领域、仪器、数据系统与目标
- **02 连接** — 接入仪器 / ELN / 编号；带入一份代表性数据
- **03 运行** — 路由到正确的工作流，带质控运行，查看合并的结果报告
- **04 验证** — 与你既有方法对比；在历史数据上回顾性评估
- **05 部署** — 云端或本地；为你的团队配置权限、版本与审计

---

## Intro video — structure (multi-domain tour)
1. **Open** — title + one-line positioning (Slide 1), ~8s
2. **Deck segment** — the platform story, narrated from the slides above (domains → instruments → search → execution/QC → private/auditable → deliverable), ~60–90s
3. **E2E demo (multi-domain tour)** — a real BioMate session:
   - **Search** — plain-language goal → workflow routing picks the method
   - **Domain A: RNA-seq differential expression** — the MG PBMC demo: run on Batch → phases live → QC → merged Results report (findings + outputs + reproducibility record)
   - **Domain B: an instrument→analysis flow** — e.g. ELISA/plate-reader titers or flow-cytometry immunophenotyping → results
   - **Close** — the deliverable package + "search · run · verify · learn", ~90–120s
4. **Close card** — contact / collaboration path (Slide 12)

**Build order:** HTML auto-play deck (EN + CN, reuse `tutorials_v2` style, `window.__timeline`) → PPTX (EN + CN) → record the HTML deck via `scripts/make_tutorial_video.py` + capture the E2E demo (multi-domain) → stitch into the intro video.
