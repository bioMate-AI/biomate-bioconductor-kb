# 复现用例 · 用户视角流程顺滑度审计（UX Journey Audit）

**Date:** 2026-09-11 · **内部文档**
**问题:** 不只是"工作流能否正确路由"，而是**从用户视角，"拿论文/数据 → 得到复现结果+报告"的整个过程是否顺滑**([[feedback_ux_walkthrough_priority]] UX 优先于后端)。
**方法:** 对复现用例(例:"reproduce GSE104687")在真实 dev(`/api/chat/stream` + 参数检视)逐步走查，对照 CLAUDE.md "Chat + Workflow Panel Presentation Standard"。承接 [[20260910_BIOMATE_REPLICATION_TEST_EASTHOSPITAL]]。

---

## 用户旅程：理想 vs 实际

| 步 | 理想(顺滑) | 实际(现 dev) | 判 |
|---|---|---|---|
| 1. 说"复现 GSE104687" | AI 摘要 + 正确工作流卡 | 出卡，但**路由不确定**(同一请求时而 differentialabundance、时而 "Gene Set Enrichment Analysis" 仅富集半段) | 🟡 |
| 2. 卡片显示分析+数据 | 输入参数**由 accession 预填** | **matrix/samplesheet = null**——GSE 号从未被解析成数据；且标 `required:false` → 面板**不报"缺数据"**，给出一张**看似可运行的空卡** | ❌ **关键** |
| 3. Confirm & Run | 自动拉取 GEO 数据 → Batch 跑 + 实时进度 | 无数据可跑；用户须**自己去找并上传 count 矩阵** = 顺滑度杀手 | ⛔ |
| 4. 实时进度 | SSE 分步更新 | (受执行阻塞;且 agentic loop 曾静默失败——已修 #220) | ⛔(待部署) |
| 5. Findings + 报告 | 方法+结果+图，可下载 | (受阻塞) | ⛔(待部署) |

**另有(已在 #220 修复的硬失败——比"不顺滑"更糟，是死路):** open-claw loop "Unknown tool" 静默耗尽、scRNA 生成 500、search 500、scRNA 聚类被塌缩为 pseudobulk。

---

## 核心结论：真正的顺滑度缺口 ≠ 工作流本身

工作流**能正确路由、用的工具也和作者等效**(已验证)。但**"贴 accession → 得结果"这一用户最期待的魔法在数据接线处断裂**：

1. **P0 · accession→数据未自动接线(最大杀手).** prompt 里有 GSE 号、平台也有 geo_data_connector 能拉取，但通用路由路径**不把 accession 接进 matrix/samplesheet**。用户拿到空卡。
   - *机制(已核实):* differentialabundance schema **无** `geo_accession`(输入=input/matrix/samplesheet/contrasts)——**不能靠预填一个参数自动拉取**;open-claw run 里 agent 手造的 `geo_accession` 是无效参数(也是它 `missing_required_params` 的一部分)。
   - *正确修法 = 链式(chain):* `geo_data_connector`(按 accession 拉取→输出 matrix+samplesheet)**→** `differentialabundance`。已有 `bioc_chain_templates.py` 支持此类链。→ 需:(a) 定义/登记 geo_data_connector→DE 链;(b) GSE+DE 意图路由到该链;(c) 执行器把连接器输出接到 DE 输入;(d) **真·Batch 跑验证**。属设计改动 + 需部署验证,**不盲改**(遵循 review-before-deploy)。这是本用例核心顺滑修复的准确形态。
2. **P1 · 路由不确定 + DE 请求被路由到仅富集.** 同一请求两种结果(differentialabundance / GSEA-only);GSEA 需要上游 DE 排序输入，单独给它=死路。→ 路由确定化 + DE 意图落到 DE 工作流。
3. **P2 · 必填标注错误 → 面板不引导.** matrix 描述写"Required."却 `required:false`，故面板的"缺必填→Fix now"告警不触发,用户被放行去跑空工作流。→ 真正的输入在无法自动解析时应 `required:true`,让面板按 presentation standard 拦截+引导。
4. **P3 · 需在部署后做真·UI 走查(浏览器).** 现审计基于 API+参数;presentation standard 的视觉/状态项(无 "undefined"、失败不卡 "Analysis in progress…"、报告下载可见、实时 data-status 迁移)须在 #220 部署后用产品 UI(或 e2e)实测。

---

## 优先级路线（顺滑度）

| 优先 | 修什么 | 状态 |
|---|---|---|
| 已修(#220) | 4 个硬失败(loop 工具/search 500/scRNA 生成/scRNA 聚类路由) | ✅ 待合并部署 |
| **P0** | accession→数据自动接线(预填 geo_accession,执行器自动拉取) | 待设计+部署验证 |
| P1 | 路由确定化;DE 请求→DE 工作流(非仅富集) | 待办 |
| P2 | 真输入 required 标注/面板引导(presentation standard) | 待办(小改) |
| P3 | 部署后浏览器端 UI 走查(全 presentation standard) | 待 #220 部署 |

**一句话:** BioMate 已能"选对工作流、用对工具";**离"用户贴一个 accession 就顺滑拿到复现结果+报告"还差 P0 数据自动接线 + P1 路由确定性 + P3 UI 走查**——这几项(而非工作流本身)才是用户视角顺滑度的真正门槛。
