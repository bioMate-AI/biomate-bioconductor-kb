# BioMate 低代码深度学习训练平台 — 功能说明

- **日期**: 2026-07-21
- **状态**: 已合并进 `integration/next-phase`(commit `2d512aaf9`),特性开关 `ML_TRAINING_ROUTING` 默认关闭
- **模块位置**: `backend/lib/galaxy/ai/ml_training/`
- **相关文档**: 选型/架构 `docs/20260717_DL_TRAINING_PLATFORM_SELECTION_AND_ARCHITECTURE.md` · 运行手册 `docs/20260717_ML_TRAINING_POC_DEV_RUNBOOK.md`

---

## 1. 一句话概述

用户在 BioMate 里用**一句自然语言**(如 "train a classifier for hERG blockers"),就能训练一个真实的深度学习模型——无需写任何模型代码。系统自动:识别训练意图 → 生成训练工作流卡片 → 在 AWS Batch 上用 **Ludwig** 训练神经网络 → 产出模型 + 评估指标(AUC 等) + 模型文件。

---

## 2. 面向用户的能力

| 能力 | 说明 |
|---|---|
| **自然语言触发训练** | chat 里说"训练一个 XX 分类/回归模型",自动浮出训练卡片,无需上传数据也能用公开数据集 |
| **低代码参数表单** | 卡片里以表单形式展示 7 个参数(数据集、目标列、模型类型、任务类型、epochs、学习率、集成数),填好点"Confirm & Run" |
| **真实 DL 训练** | Ludwig 神经网络(CPU),在 AWS Batch 上真跑,不是模拟 |
| **公开数据集开箱即用** | 识别已知 assay(hERG/BBB/AMES/Caco2/PPBR 等),自动映射到 Therapeutics Data Commons 公开数据集 |
| **实时状态 + 评估指标** | 运行完成后展示 AUC/准确率等指标,QC gate 可按阈值判定通过/拦截 |
| **模型产物落地** | 训练好的模型权重 + 超参 + metadata 自动上传到 S3 |

### 典型用户旅程
1. chat 发:`train a classifier for hERG blockers`
2. 右侧出现卡片:**ML TRAINING · hERG classifier**(模型类型 `ludwig_tabular`,数据集 `tdc:hERG`)
3. (可选)展开"Edit params"调 epochs/学习率等
4. 点 **Confirm & Run**
5. 约 3–4 分钟后:运行完成,展示 **test_auc ≈ 0.80**,S3 里有模型文件
6. 反例:`predict hERG for aspirin` → **不**触发训练卡片,走正常推理/查询路由

---

## 3. 支持的模型类型

| model_type | 引擎 | 任务 | 算力 | 状态 |
|---|---|---|---|---|
| **`ludwig_tabular`**(分子默认) | Ludwig 神经网络(RDKit 2D 描述符 + 全连接网络) | 分子分类/回归 | CPU | ✅ 已实现 + test/Batch 端到端验证(AUC 0.80) |
| **`ludwig_llm`** | Ludwig 原生 LLM 微调(LoRA/QLoRA) | LLM 指令微调 (SFT) | CPU(LoRA)/GPU(QLoRA) | ✅ 已实现 + test/Batch 端到端验证(SmolLM2-135M LoRA) |
| **`trl_dpo`** | TRL `DPOTrainer`(直接偏好优化,LoRA) | LLM 偏好对齐(chosen/rejected) | CPU/GPU | ✅ 已实现(独立 trl-training 镜像) |
| **`trl_grpo`** | TRL `GRPOTrainer`(组相对策略优化,LoRA) | LLM 强化学习(可编程奖励) | CPU/GPU | ✅ 已实现(独立 trl-training 镜像) |
| `sklearn_gbr` | scikit-learn 梯度提升(基线) | 分子分类/回归 | CPU | ✅ 已实现 |
| `chemprop_gnn` | Chemprop 图神经网络(分子图) | 分子分类/回归 | GPU | ⏳ 守卫 stub,待 GPU 落地(说 "chemprop/gnn/graph" 才选它) |

> 分子请求默认 `ludwig_tabular`(CPU);说 "fine-tune an LLM / language model / instruction-tune / llama / gpt" 走 `ludwig_llm`(SFT,默认 SmolLM2-135M + LoRA,CPU 可跑);说 "DPO / preference optimization" 走 `trl_dpo`;说 "GRPO / reinforcement learning / reward" 走 `trl_grpo`。
> **镜像隔离**:TRL 0.24 需要比 Ludwig 0.10.4 更新的 torch/transformers/pyarrow,两者依赖不可共存,故 DPO/GRPO 跑在独立的 `biomate/trl-training` 镜像(executor 按 `model_type` 自动选镜像,`TRL_TRAINING_IMAGE` 可覆盖)。

---

## 4. 支持的数据集

三种来源(声明式配置里三选一):

1. **公开数据集别名**(推荐,零准备):识别到已知 assay 自动映射到 TDC 公开数据集
   - `hERG` → `tdc:hERG`(分类)
   - `BBB`/blood-brain → `tdc:BBB_Martins`
   - `AMES` → `tdc:AMES` · `CYP2D6/3A4` · `Caco2` → `tdc:Caco2_Wang`(回归)
   - `Lipophilicity` · `Solubility` · `PPBR` 等
2. **用户数据(S3)**:`s3://.../data.csv`(SMILES 列 + 标签列)
3. **本地 CSV/SDF 路径**(执行时由 executor staging 到 S3)

离线测试还有一个内置 fixture(`fixture:herg`)。

---

## 4.5 LLM 微调(model_type = ludwig_llm)

用一句话触发 LLM 指令微调,无需写训练代码:

- **触发**:chat 说 "fine-tune an LLM / language model / instruction-tune a chat model / fine-tune llama on my data" 等 → 出 LLM 训练卡片(`ludwig_llm` / `text_generation`)
- **引擎**:Ludwig 原生 LLM 能力(声明式 LoRA/QLoRA 微调)
- **数据**:指令/响应文本
  - 本地 `.jsonl`(每行 `{"instruction": "...", "output": "..."}`)或 `.csv`(instruction/output 两列)
  - `hf:<数据集>`(HuggingFace 指令数据集)
  - `fixture:instruct`(内置 16 行离线样例,开箱即跑)
- **基座模型**:任意 HF 模型 id,默认 `HuggingFaceTB/SmolLM2-135M-Instruct`(小、CPU 可跑)
- **适配器**:`lora`(默认,CPU 可跑,只训 ~0.3% 参数)/ `qlora`(4-bit,需 GPU)/ `none`(全量微调)
- **产物**:训练好的 **LoRA adapter**(`adapter_model.safetensors` + `adapter_config.json`)+ 超参 + metrics(loss/perplexity),上传 S3
- **已验证**:test/AWS Batch 上真跑通——SmolLM2-135M LoRA 微调(460,800 可训参数 = 0.34%),run succeeded

LLM 卡片参数:`dataset`、`base_model`(必填)+ `adapter`/`instruction_col`/`output_col`/`max_sequence_length`/`epochs`/`learning_rate`。

---

## 4.6 偏好对齐 / 强化学习(model_type = trl_dpo / trl_grpo)

在 SFT 之上,补齐 LLM 的偏好对齐与强化学习,一句话触发、无需写训练代码。引擎是 HuggingFace **TRL**(工业标准),用 LoRA 适配器,跑在独立的 `trl-training` 镜像。

**DPO —— 直接偏好优化(`trl_dpo`)**
- **触发**:chat 说 "fine-tune an LLM with DPO / direct preference optimization / preference tuning / align on chosen-rejected pairs / RLHF" → 出 DPO 卡片
- **引擎**:TRL `DPOTrainer` + `DPOConfig`(reward-model-free 的离线偏好优化)
- **数据**:偏好三元组
  - 本地 `.jsonl`(每行 `{"prompt": "...", "chosen": "...", "rejected": "..."}`)或 `.csv`(prompt/chosen/rejected 三列)
  - `hf:<数据集>` / `fixture:preference`(内置 8 条离线样例)
- **关键超参**:`beta`(KL 正则强度,默认 0.1)
- **产物**:对齐后的 LoRA adapter + metrics(train_loss)

**GRPO —— 组相对策略优化(`trl_grpo`)**
- **触发**:chat 说 "train a language model with GRPO / reinforcement learning / reward function" → 出 GRPO 卡片
- **引擎**:TRL `GRPOTrainer` + `GRPOConfig`(在线 RL,DeepSeek 同款算法,无需单独的 value/critic 网络)
- **数据**:仅提示词 `{"prompt": "..."}`(`.jsonl`/`.csv`/`hf:` / `fixture:prompts` 内置 8 条)
- **奖励函数**(可编程,`reward` 选):
  - `length` —— 奖励简洁、非空的回答(默认)
  - `keyword` —— 命中 `reward_keyword` 得分
  - `numeric_answer` —— 回答含数字得分
- **关键超参**:`num_generations`(每个提示采样的候选数 / 组大小,默认 4)、`reward`
- **产物**:RL 优化后的 LoRA adapter + metrics(train_loss)

> 基座模型、`adapter`、`max_sequence_length`、`epochs`、`learning_rate` 与 SFT 共用;默认基座同样是 `HuggingFaceTB/SmolLM2-135M-Instruct`,CPU 可跑小样例。至此 LLM 侧覆盖 **SFT → DPO → GRPO(RL)** 三段完整链路。

---

## 5. 参数(声明式配置)

卡片渲染的 7 个参数,对应 `TrainingConfig`:

| 参数 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `dataset` | ✅ | 由别名解析(如 tdc:hERG) | 数据来源 |
| `target_col` | ✅ | `Y` | 标签列名 |
| `model_type` | — | `ludwig_tabular` | 见 §3 |
| `task_type` | — | `classification` | classification / regression |
| `epochs` | — | 50 | 训练轮数 |
| `learning_rate` | — | 0.001 | 学习率 |
| `ensemble_size` | — | 1 | 集成模型数 |

还支持(非卡片显性):`gate_threshold`(QC 门阈值)、`metric`(auc/mae)、`val_frac`/`test_frac`(划分比例)、`hidden_size`/`depth`/`dropout`/`batch_size`/`seed` 等超参。

---

## 6. 端到端流程(架构)

```
用户 chat: "train a classifier for hERG blockers"
      │
      ▼  ① 意图识别(Node 层 galaxy-assistant.ts,开关门控)
   规则命中"train + classifier" → 强制 workflow_generation
      │
      ▼  ② 路由(后端 ai_assistant.generate_workflow_unified,开关门控)
   route_ml_training_result() → 返回 ml_training 训练卡片(workflow_ga)
      │
      ▼  ③ 前端渲染(NextflowWorkflowViewer,零改动)
   卡片:名称/domain/7 参数表单 + Confirm & Run
      │
      ▼  ④ 提交(/api/workflows/execute → /api/nextflow/execute)
   executor 识别 ml_training 工作流 → 自动选 biomate/ml-training 容器
      │
      ▼  ⑤ 执行(Nextflow → AWS Batch,process_low = 12GB CPU)
   容器内 `python -m ml_training.cli` → Ludwig 训练
      │
      ▼  ⑥ 产出
   test_auc/val_auc 指标(→ SSE/Findings) + 模型文件上传 S3
```

### 关键代码组件

| 文件 | 作用 |
|---|---|
| `config.py` | 声明式 `TrainingConfig`(dataclass)+ 映射成 workflow_ga 参数契约 |
| `routing.py` | 规则优先意图识别 + 数据集别名 + `route_ml_training_result()`(开关门控) |
| `ludwig_adapter.py` | `TrainingConfig → Ludwig config` + RDKit 描述符特征化 |
| `ludwig_trainer.py` | 真实 `LudwigModel` 训练/评估/保存 |
| `chemprop_trainer.py` | 训练器派发(ludwig/sklearn/chemprop) |
| `training_job.py` | 编排:加载数据 → 训练 → QC gate → MLflow 追踪 → 注册 |
| `executor_payload.py` | `TrainingConfig → /api/nextflow/execute` 载荷(含容器选择) |
| `cli.py` | 容器内入口 `python -m ml_training.cli`(argparse → 训练) |
| `chemprop_train.nf` | Nextflow 进程包装(process_low CPU 档) |
| `chemprop_wrapper.py` | 训练产物 → `BaseModelWrapper` 桥接(复用现有 registry) |
| `bento_service.py` | BentoML 服务脚手架(部署用) |

---

## 7. 复用的现有能力(不重复造轮子)

- `drug_discovery.BaseModelWrapper` — 模型统一接口
- `drug_discovery.CustomModelRegistry` — 模型注册表
- `drug_discovery.model_validation` — 评估指标
- 现有 Nextflow 执行器 + AWS Batch + RunStateStore + SSE 状态回传 + billing
- 前端 `NextflowWorkflowViewer` 工作流卡片(参数表单/QC gate/状态,**零改动**复用)

---

## 8. 部署与运维

| 项 | 值 |
|---|---|
| **特性开关** | `ML_TRAINING_ROUTING=1` 启用(默认关,关闭时整条路由惰性、零影响) |
| **训练镜像** | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ml-training:latest`(ludwig+rdkit+aws cli+procps,无 ENTRYPOINT,PYTHONPATH=/app) |
| **镜像构建** | `.github/workflows/ml-training-image.yml`(打 `ml-training-v*` tag 触发) |
| **算力档位** | `process_low`(12GB/2vCPU,适配 CE 上限 64GB);GPU 路径待 chemprop 落地 |
| **执行队列** | `biomate-nextflow-queue`(AWS Batch) |
| **模型输出** | `s3://biomate-nextflow-work/nextflow/outputs/<user>/<run>/results/` |

---

## 9. 已验证 & 测试覆盖

- **端到端(test/AWS Batch)**:chat → 卡片 → Batch → 真实 Ludwig NN(655 个 hERG 分子,50 epochs)→ 运行成功,**test_auc 0.80 / val_auc 0.86**,模型权重(4.3MB)入 S3
- **单元/集成测试**:11 个 pytest 文件,**78 项全绿**(配置校验、数据集加载、Ludwig 适配、路由意图、执行器载荷、CLI、orchestrator、真实 sklearn/Ludwig E2E 等)
- 重依赖惰性守卫,纯 Python 层无 ML 栈也能跑测试

---

## 10. 当前限制与待办(正式上线前)

1. **`.nf` 靠宿主机 bind-mount 解析** — 训练包装文件目前放在 `/opt/biomate/data/nextflow_nfcore/ml_training/`(镜像里被 dockerignore),需纳入填充该数据目录的正式流程,或让执行器从镜像解析
2. **开关配置** — `ML_TRAINING_ROUTING` 目前写在 test 主机 `.env`,应移到 Secrets Manager 正式配置
3. **chemprop GPU 路径** — 仍是守卫 stub,需 GPU 训练镜像 + 具体 fit/inference 落地(参考代码在运行手册)
4. **MLflow tracking server** — 目前 tracking 是惰性 no-op,正式追踪需自托管 MLflow server
5. **BentoML 部署** — 服务脚手架已备,推理端点上线是后续
6. **无关的构建阻塞** — `paper-qa>=5.0.0` 在 py3.9 镜像上装不了(main 上本来就有),需单独修

---

## 11. 未来扩展方向

- 终端用户上传私有数据训练私有模型(project 级隔离,复用现有所有权机制)
- chemprop GPU 分子图模型上线
- 训练完成 → 自动注册进 CustomModelRegistry → BentoML 一键上线为可调用推理工具
- 超参搜索 / AutoML(可接 ZenML fan-out)
- 更多领域框架(DeepChem/DeepPurpose)接入同一 workflow 契约
