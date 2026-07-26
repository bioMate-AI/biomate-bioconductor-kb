# BioMate 自动化深度学习训练平台 — 选型报告与架构设计

- **日期**: 2026-07-17
- **作者**: (调研 / 架构草案)
- **状态**: 草案 · 待评审
- **需求来源**: 为 biomate 新增一套「开源、低代码、自动化训练 → 测试/评估 → 部署」的深度学习平台

---

## 0. TL;DR（一页纸结论）

- **不存在单一软件能全包** "低代码训练 + 自动训练 + 自动测试 + 自动部署"。业界成熟做法是**分四层组合**：低代码建模 / 编排 / 追踪注册 / 服务。
- **推荐主栈（无 K8s，复用现有 AWS Batch + Galaxy Python 后端）**：
  - **建模（低代码）**: **Ludwig**（YAML 声明式）+ 领域框架 **DeepChem / Chemprop**（分子/药物发现）
  - **追踪 + 模型注册**: **MLflow**（事实标准，自托管）
  - **编排**: **复用 biomate 现有 workflow 编排**（把训练当作一类新 workflow），必要时补 **ZenML**
  - **部署/服务**: **BentoML**（Python 优先，不强依赖 K8s）
  - **训练算力**: 复用现有 **AWS Batch**（nextflow_executor 已有内存分层 + GPU 逻辑）
- **K8s 待定**: 本方案**无需 K8s** 即可完整落地。若未来要多租户大规模在线推理再评估 KServe/Kubeflow（见 §7 升级路径）。
- **两类用户都覆盖**:
  - 内部生信团队 → 领域框架（DeepChem/Chemprop）产 ADMET/分子/蛋白模型
  - 终端用户低代码 → Ludwig YAML/表单，复用现有 workflow 卡片 UX
- **第一步产出**: 本文档（选型 + 架构）。下一步建议做一个 Ludwig→MLflow→AWS Batch 的端到端最小 PoC（见 §8）。

---

## 1. 需求拆解：四层能力，不要当成一个"平台"

"自动化训练/测试/部署 + 低代码"实际上是四个能力层，选型必须分层，否则会误买一个重型平台（如 Kubeflow）却只用到 20%：

| 层 | 作用 | 低代码要求 | biomate 现状 |
|---|---|---|---|
| **A. 低代码建模/训练** | 用配置（而非手写 PyTorch）定义并训练模型 | ★★★ 核心 | 无 |
| **B. 编排 / 流水线** | 把 train→eval→register→deploy 串成可复现 DAG | ★★ | ✅ 已有（Nextflow 执行 + 路由 + SSE） |
| **C. 实验追踪 / 模型注册表** | 记录指标、超参、版本、血缘 | ★ 后台 | 无（仅 LLM 成本/billing） |
| **D. 部署 / 在线服务** | 训练好的模型自动上线成 API | ★★ 自动化 | 无 |

**关键洞察**：biomate 的 B 层已经很强（AWS Batch 执行、workflow_ga schema、SSE 实时状态、RunStateStore 跨 worker 持久化）。所以真正要新增的是 **A（低代码建模）、C（追踪注册）、D（服务）**，B 层直接复用。

---

## 2. 各层开源候选对比

### A 层 · 低代码建模

| 工具 | 定位 | 低代码方式 | 深度学习 | 适配 biomate |
|---|---|---|---|---|
| **Ludwig** (LF AI & Data, 原 Uber) | 声明式 DL 框架 | **YAML 声明输入/输出数据类型**，自动组装/训练/微调/部署 | ✅ 表格/文本/图像/音频/LLM 微调 | ★★★★★ 最契合；YAML 天然对应现有 workflow 参数卡片 |
| **H2O AutoML** (H2O.ai) | 分布式 AutoML | Flow UI / Python API，时间预算内自动训练一批算法 | 部分（DL 非强项） | ★★★ 偏经典 ML/表格；企业采用广 |
| **AutoGluon** (AWS) | AutoML 库 | 3 行 Python 出基线 | ✅ 表格/文本/图像 | ★★★ 快速基线，非"平台" |
| **TPOT** | 遗传编程 AutoML | 自动搜索完整 pipeline | ✗ 经典 ML | ★★ 表格特征工程 |

**选择**: **Ludwig 为主**（低代码建模核心），AutoGluon 作为表格类快速基线的补充。

### 领域专用（biomate 的真实业务 — 药物发现/生信）

通用 AutoML 之外，这些**领域 DL 框架**直接对接你已有的 ADMET/分子/蛋白场景，往往比通用平台更快产出价值：

| 框架 | 能力 | 对接现有域 |
|---|---|---|
| **DeepChem** | QSAR、蛋白-配体、材料/量子化学 DL 工具链 | drug_discovery / ADMET |
| **Chemprop** | GNN 分子性质预测（本身即 AutoML 化） | **直接对接现有 ADMET 工作流** |
| **DeepPurpose** | 化合物性质、蛋白功能、DTI 预测 | drug_discovery / proteomics |
| **TorchDrug** | GNN、几何深度学习、生成模型、RL | 高级药物发现 |
| **Uni-QSAR / Deep-AutoQSAR** | 分子性质 AutoML | ADMET |

**选择**: **DeepChem + Chemprop 为主**（内部生信团队产模型），封装成 biomate workflow。

### B 层 · 编排（对比，但结论是复用现有）

| 工具 | 特点 | 门槛 |
|---|---|---|
| **biomate 现有 workflow 编排** | Nextflow 执行 + 路由 + SSE + RunStateStore | 零新增 |
| ZenML | 最轻、Python 优先、可插拔（底层可接 Kubeflow/Airflow） | 低 |
| Metaflow (Netflix) | CLI 友好、上手最快 | 低 |
| Flyte | K8s 原生、强类型、生产级（Lyft 百万 pipeline/月） | 高（需 K8s） |
| Kubeflow | K8s 原生、分布式训练 + KServe，最全最重 | 很高（需 K8s + 运维） |

**选择**: **复用现有编排**。训练 = 一类新 workflow（`domain=ml_training`），走 `/api/nextflow/execute`。若后续需要独立 DL DAG（如超参搜索 fan-out），再补 **ZenML**（不需要 K8s）。

### C 层 · 追踪 / 注册表

| 工具 | 特点 |
|---|---|
| **MLflow** | **事实标准**、轻量、自托管、追踪 + 模型注册 + 部署一体；MLflow 3.0 增加 LLM 评估。几乎所有工具都能集成 |
| Weights & Biases | 体验好但 SaaS/商业 |

**选择**: **MLflow**（自托管在现有 EC2，SQLite/Postgres backend + S3 artifact store，复用现有 `biomate-nextflow-work` 桶）。

### D 层 · 部署 / 服务

| 工具 | 特点 | K8s 依赖 |
|---|---|---|
| **BentoML** | Python 优先、代码即服务、打包成"Bento"、可容器化 | ✗ 不强依赖 |
| Ray Serve | 笔记本→集群平滑扩展，Ray 生态 | 可选 |
| KServe | K8s 原生、scale-to-zero、CNCF 标准 | ✅ 强依赖 |
| Seldon Core | 灵活部署（A/B、推理图） | ✅ 强依赖 |

**选择**: **BentoML**（Python 优先，无 K8s，容器化后可跑在现有 ECS/EC2 或 AWS Batch 推理端点）。

---

## 3. 推荐主栈总览

```
┌─────────────────────────────────────────────────────────────────┐
│  用户入口（复用现有 biomate chat + workflow 卡片 UX）            │
│  · 内部生信: "训练一个 hERG 抑制预测模型" → DeepChem/Chemprop wf │
│  · 终端用户: 上传数据 + YAML/表单 → Ludwig 声明式训练            │
└───────────────┬─────────────────────────────────────────────────┘
                │ /api/ai_assistant  (workflow_ga: domain=ml_training)
                ▼
┌─────────────────────────────────────────────────────────────────┐
│  A. 低代码建模层                                                  │
│     Ludwig (YAML)  |  DeepChem / Chemprop (领域)  | AutoGluon     │
│     → 封装为 ml_training workflow（.nf 或 run_code 包装）         │
└───────────────┬─────────────────────────────────────────────────┘
                │ /api/nextflow/execute  (复用 executor)
                ▼
┌─────────────────────────────────────────────────────────────────┐
│  B. 编排 / 执行层  (★ 复用现有，零新增)                          │
│     nextflow_executor → AWS Batch (内存分层 12/36/72/200GB + GPU)│
│     RunStateStore (Redis 跨 worker)  ·  SSE 实时训练指标         │
└───────────────┬─────────────────────────────────────────────────┘
                │ 训练完成回调
                ▼
┌─────────────────────────────────────────────────────────────────┐
│  C. 追踪 / 注册表层                                               │
│     MLflow (自托管) — 指标/超参/版本/血缘 + Model Registry        │
│     artifact store = S3 (biomate-nextflow-work 或独立 ml 桶)     │
└───────────────┬─────────────────────────────────────────────────┘
                │ registry: Staging → Production 提升
                ▼
┌─────────────────────────────────────────────────────────────────┐
│  D. 部署 / 服务层                                                 │
│     BentoML — 从 MLflow registry 拉模型 → 打包 Bento → 容器      │
│     → 部署为推理 API（ECS/EC2/Batch endpoint），无需 K8s        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. 与 biomate 现有架构的集成设计（核对过的接入点）

> 以下接入点均已通过代码核对（见文末「核对来源」）。

### 4.1 训练即 workflow（复用 B 层）

新增 `domain = ml_training` 的 workflow 类别，走现有执行链路：

- **提交**: `POST /api/nextflow/execute`（`nextflow_executor.py:4275`）
  - `nextflow_path`: 训练 pipeline 包装（.nf 或 run_code 包装 Ludwig/DeepChem 调用）
  - `parameters`: `{framework, dataset_s3, target_col, model_type, hyperparams, memory_tier, gpu_count, mlflow_experiment}`
  - `compute_config`: `{executor: "awsbatch", s3_bucket: "biomate-nextflow-work"}`
- **算力分层**: 复用现有内存注入（`nextflow_executor.py:2406-2423`，`process_low/medium/high = 12/36/72GB`，另有 200GB 档 + `process_gpu`）。DL 训练默认落 `process_gpu` 档。
- **状态轮询**: `GET /api/nextflow/status/{run_id}`（`:5623`）→ `log_tail` 里回传训练指标（loss/epoch/val_metric）。
- **持久化**: 复用 `RunStateStore`（`run_state_store.py`，Redis 跨 worker，7 天 TTL，completion lock 防重复完成）——DL 长训练尤其需要，避免 gunicorn worker 回收丢状态。

### 4.2 workflow_ga schema 扩展（低代码参数）

现有 `workflow_ga`（`ai_assistant.py:3240+`）已含 `required_params / optional_params / steps / nextflow_path / domain`。DL 训练**复用同一 schema**：

```python
workflow_ga = {
  'name': 'Train hERG inhibition classifier (Chemprop)',
  'domain': 'ml_training',
  'format': 'nextflow',
  'nextflow_path': 'ml_training/chemprop_classification.nf',
  'required_params': [
     {'name':'dataset_s3','type':'file','label':'训练数据 (CSV/SDF)','required':True},
     {'name':'target_col','type':'string','label':'预测目标列','required':True},
  ],
  'optional_params': [
     {'name':'epochs','type':'number','default':50},
     {'name':'model_type','type':'select','allowed_values':['GNN','MLP'],'default':'GNN'},
  ],
  'execution_engine': 'awsbatch',
}
```

→ 前端 `NextflowWorkflowViewer`（`nextflow-workflow-viewer.tsx:188-267`）**已有** file/boolean/select/number/string 类型渲染 + `autoFilled` LLM 预填徽章。**零前端改动即可展示训练参数表单。**

### 4.3 实时训练指标 → SSE（复用现有 narrator）

- 前端已监听 `EventSource('/api/workflows/{invocationId}/events')`（`:1948`），事件类型含 `chat_progress` / `workflow_event` / `qc_gate_results` / `autoloop_gate_results`。
- 训练进度（epoch/loss/val_metric）通过 `_narrate_chat`（`nextflow_executor.py:257`）注入为 workflow-progress 行。
- **训练的 "QC gate" 天然映射现有 QC gate**: 例如 `val_auc < 0.7` → `qc_gate_results` 事件 → 现有 auto-loop 面板可展示"调超参重训"的 was→now diff。这几乎是免费复用现有自动纠错 UX。

### 4.4 MLflow 接入点（新增 C 层）

- 自托管 MLflow tracking server（EC2，Postgres/SQLite backend + S3 artifact）。
- 训练 job 内 `mlflow.log_params/metrics/model`；完成后写入 Model Registry。
- 新增薄代理路由（Node.js `routes.ts` 或 Galaxy 后端）: `GET /api/ml/models`、`GET /api/ml/runs/{id}` 供前端"模型库"页面读取。
- 复用现有 billing 模式记录训练算力成本（vCPU/GPU-hours 已由 `biomate-batch-billing` Lambda 采集）。

### 4.5 BentoML 部署（新增 D 层）

- 从 MLflow Registry（Production stage）拉模型 → `bentoml build` → 容器镜像。
- 部署目标（无 K8s）: ECS service 或常驻 EC2 推理进程；批量推理可复用 AWS Batch。
- 推理端点注册回 biomate，成为一个可调用的 "tool"（对接现有 tool DB / run_code 路径）。

### 4.6 现状确认

代码核对：**仓库内目前无原生 PyTorch / MLflow / model-registry / 训练循环**。已有的相关点仅：LLM 参数推断、regulatory LoRA adapter 元数据（`feedback.py:14`）、CryoEM 的 TOPAZ 粒子挑选（领域专用，非通用训练）。→ 本方案是**从 0 新增 A/C/D 层**，B 层复用。

---

## 5. 两类用户的落地路径

### 5.1 内部生信团队（产领域模型）
- 入口: chat "训练一个 XX 预测模型" → 路由到 `ml_training` 域的 DeepChem/Chemprop workflow。
- 产出: ADMET / QSAR / DTI / 蛋白功能模型，注册进 MLflow，一键 BentoML 上线。
- 价值: 直接补强现有 ADMET/drug_discovery 域的自研模型能力。

### 5.2 终端用户（低代码自训练）
- 入口: 上传数据集 → YAML/表单声明输入输出（Ludwig）→ "Confirm & Run"。
- 产出: 用户私有模型，隔离在其 project/S3 前缀下（复用现有 project 所有权 + 跨用户隔离机制）。
- 价值: 平台从"跑固定 workflow"升级为"用户可训练私有模型"，是明显的产品差异化。

---

## 6. 为什么不直接上 Kubeflow / KServe（暂缓 K8s 的理由）

- biomate 现在**没有 K8s**，执行底座是 AWS Batch + Galaxy gunicorn。上 Kubeflow 需要一整套 K8s 集群 + Knative + 运维专长，与 CLAUDE.md「根因优先、不做重型 workaround」和现有轻量运维现状冲突。
- 调研共识：Python-first 团队误选 KServe"因为它是 CNCF 标准"，常陷入 InferenceService YAML / Knative 路由调试数周，数据科学家无法维护。
- 本方案全 Python、无 K8s，每层都能接现有 AWS Batch + Galaxy，能更快落地且可测试。

---

## 7. 升级路径（若未来确需 K8s）

分阶段、可逆，不必现在决定：

1. **阶段 1（本方案）**: Ludwig/DeepChem + MLflow + AWS Batch + BentoML on ECS。无 K8s。
2. **阶段 2（编排增强）**: 引入 ZenML 做超参搜索 fan-out / 多步 DL DAG（仍无需 K8s，ZenML 可插拔底层）。
3. **阶段 3（大规模在线推理）**: 若出现高并发、多模型、scale-to-zero 需求 → 引入 **KServe/Ray Serve**（此时才上 K8s，MLflow + BentoML 打包产物可平移）。

每个阶段都独立可用，MLflow 作为贯穿始终的"模型真相源"，保证升级不推倒重来。

---

## 8. 建议的下一步（第一个 PoC）

> 遵循 CLAUDE.md「Review Code Before Testing / 不做投机部署」，先小样例跑通再扩展。

**PoC 目标**: 端到端跑通「Chemprop 训练 ADMET(hERG) 模型 → MLflow 注册 → BentoML 推理」1 条链路。

1. 写 `ml_training/chemprop_classification.nf`（或 run_code 包装），封装 Chemprop 训练 + `mlflow.log_*`。
2. 自托管一个 MLflow server（先 SQLite backend + 现有 S3 artifact，最小化）。
3. 加 `domain=ml_training` 到 workflow DB，一条种子 workflow，验证 `workflow_ga` 能被路由 + 前端表单渲染。
4. 走 `POST /api/nextflow/execute` 提交到 AWS Batch（`process_gpu` 档），验证 SSE 回传 epoch/loss。
5. 训练完成 → MLflow Registry → `bentoml build` → 本地容器起推理 API，验证一次预测。
6. 记录成本（复用 billing）、截图各状态、写复盘 doc。

**验收**: 一个真实 hERG 数据集上 val AUC 达标的模型，从 chat 触发到可调用推理端点全自动完成。

---

## 9. 风险与开放问题

| 风险 / 问题 | 说明 | 缓解 |
|---|---|---|
| Ludwig 维护活跃度 | 原 Predibase/Uber，需确认社区节奏 | 领域侧用 DeepChem/Chemprop 兜底，不单押 Ludwig |
| GPU 成本 | DL 训练比现有 CPU workflow 贵 | 复用 billing + 配额门；默认小档 + 用户确认 |
| 多租户模型隔离 | 用户私有模型的 S3/registry 隔离 | 复用现有 project 所有权 + 跨用户隔离测试 |
| MLflow 自托管运维 | 需一个常驻 tracking server | 先单实例 + S3 artifact，后续再高可用 |
| 领域框架容器 | DeepChem/Chemprop 依赖重 | 预烘焙训练镜像（参考现有 nf-core 镜像做法） |
| 在线推理规模 | 阶段 1 不解决高并发 | 见 §7 升级路径 |

---

## 核对来源（代码接入点，已实读）

- 执行 API / AWS Batch / 内存分层: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`（execute `:4275`、status `:5623`、内存注入 `:2406-2423`、SSE narrator `:257`）
- workflow_ga schema / 路由: `backend/lib/galaxy/ai/.../ai_assistant.py`（`:3240+`, `generate_workflow_unified :3371`）
- 工作流 DB: `backend/database/galaxy_ai_tools.db`（`unified_workflow_search.py:551`）
- 运行状态持久化: `backend/lib/galaxy/ai/runs/run_state_store.py`（InMemory / Redis）
- 前端组件契约: `frontend/client/src/components/nextflow-workflow-viewer.tsx`（props `:24-72`、参数渲染 `:188-267`、SSE `:1948`）
- 现有 ML 相关: 无原生训练/注册代码；仅 LLM 参数推断 + regulatory LoRA 元数据（`feedback.py:14`）+ TOPAZ 领域挑选

## 调研来源（外部）

- AutoML 概览: [mljar 2026](https://mljar.com/blog/open-source-automl-projects-in-2026/) · [DataCamp](https://www.datacamp.com/blog/best-automl-frameworks) · [H2O AutoML](https://h2o.ai/platform/h2o-automl/)
- 低代码建模: [Ludwig (GitHub)](https://github.com/ludwig-ai/ludwig) · [ludwig.ai](https://ludwig.ai/latest/) · [LF AI & Data](https://lfaidata.foundation/projects/ludwig/)
- 编排对比: [ZenML vs Flyte vs Metaflow](https://mlops.community/zenml-vs-flyte-vs-metaflow/) · [Kubeflow vs MLflow (Medium)](https://medium.com/@pratik-rupareliya/kubeflow-vs-mlflow-which-one-to-choose-for-your-mlops-workflow-6a8896b544e4)
- 追踪/注册: [Databricks MLOps guide](https://www.databricks.com/blog/mlops-frameworks-complete-guide-tools-and-platforms-production-ml) · [ZenML MLflow alternatives](https://www.zenml.io/blog/mlflow-alternatives)
- 部署/服务: [KServe vs Seldon vs BentoML (Spheron)](https://www.spheron.network/blog/kserve-vs-seldon-core-vs-bentoml-kubernetes-ml-serving-guide/) · [Ray Serve docs](https://docs.ray.io/en/latest/serve/index.html)
- 领域(药物发现): [DeepChem/awesome-drug-discovery](https://github.com/yboulaamane/awesome-drug-discovery) · [Uni-QSAR (arXiv)](https://arxiv.org/pdf/2304.12239) · [AutoML for ADMET (JCIM)](https://pubs.acs.org/doi/10.1021/acs.jcim.4c02122)
