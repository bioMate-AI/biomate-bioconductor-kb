# BioMate 测试数据工作流测试报告

**日期**: 2026-11-10  
**测试环境**: https://dev-public.biomate.ai  
**测试账户**: trial1-5@biomate.ai (professional tier, 半年试用)

---

## 测试概览

| TC | 场景 | 路由 | 执行 | 关键问题 |
|----|------|------|------|---------|
| TC-01 | RNA-seq DEG (nf-core/differentialabundance) | ✅ | ❌ failed | QueuePool 耗尽导致 11s 内失败 |
| TC-02 | 批次效应 QC | ✅ | ⚠️ 未执行 | LLM 未可靠识别 batch confound 和 N6 深度异常 |
| TC-03 | ML 亚型预测 | ❌ | ❌ | 路由到 Vbmp 而非 Ludwig/RF (capability gap) |
| TC-04 | 空间转录组 | ⚠️ 部分 | ⚠️ 未自动触发 | workflow card 返回但路由不匹配空间组学 |
| TC-05 | GWAS (37MB TSV) | ❌ | - | 文件上传超时 (upload write timeout) |
| TC-06a | qPCR Cq 分析 | ✅ | ⚠️ | IL6 ~8x 未从响应中确认 |
| TC-06b | IC50 拟合 | ✅ | ✅ | 提到 IC50/4-param logistic |
| TC-06c | 质谱蛋白 LFQ | ✅ | ⚠️ | 返回 workflow 但未识别 0/13 差异蛋白 |

---

## 根本原因分析

### RC-1: QueuePool 连接池耗尽（已修复）

**症状**: 所有 Nextflow 执行在 ~11 秒内失败，`status=failed`，错误信息仅为 DEBUG 级别消息。

**根本原因**:  
`backend/lib/galaxy/ai/memory/agentic_memory.py` 在模块级创建了 SQLAlchemy 引擎（默认 `pool_size=5, max_overflow=10`）。Galaxy gunicorn 使用 `--preload` 启动，master 进程 import 模块时创建连接池，每个 fork 出的 worker 继承同一个连接池对象。在 4+ workers 并发下，15 个连接很快被耗尽。

Galaxy logs 中每 2-3 分钟出现：
```
CRITICAL/MainProcess: Unrecoverable error: TimeoutError('QueuePool limit of size 5 overflow 10 reached, connection timed out, timeout 30.00')
```

**修复** (commit `bae6ea22f6`, branch `feat/aliyun-demo-deploy`):
1. `agentic_memory.py`: `pool_size=10, max_overflow=20, pool_recycle=300`
2. `gunicorn_config.py` `post_fork` hook: `engine.dispose()` → 每个 worker fork 后获取独立的连接池

**临时处置**: Galaxy 容器重启已清理卡住的连接，当前无新 CRITICAL 错误。**待部署**: 需要在 dev 上执行 `sync_to_dev.sh` 将上述 commit 部署到容器。

### RC-2: GWAS 大文件上传超时

**症状**: 37MB TSV 文件上传时 write timeout。

**根本原因**: HK 代理→AWS 经过 `/etc/nginx/sites-available/biomate` 中间层，`proxy_send_timeout 3600s` 已设置，但文件上传通过大文件可能受限于客户端本地网络。

**建议**: 
- 测试脚本中对 GWAS 上传超时设为 `timeout=300`（已是 120s，需增大）
- 或建议用户通过 BioMate 的项目文件功能直接在浏览器上传

### RC-3: ML 路由不正确

**症状**: 基因表达矩阵 + "亚型预测" → 路由到 `Vbmp High Dimensional Cross Validation`（贝叶斯方法）而非 Ludwig/随机森林等现代 ML 工作流。

**根本原因**: DB 中没有足够的"亚型预测 + 现代 ML"匹配工作流，或路由 embedding 相似度偏向 Vbmp（因关键词 "cross validation" 匹配度高）。

**建议**: 
- 检查 `galaxy_ai_tools.db` 中 `ML_TRAINING` 类型工作流（`ml_training` domain tag）
- Ludwig 工作流已在 `integration/next-phase` 合并（commit `2d512aaf9`），但该分支可能未在 dev 部署

---

## 功能评估

### TC-02 批次效应：LLM 识别能力差距

实测中 LLM（2次运行，1次识别到批次效应，0次识别到 N6 测序深度异常）：
- 批次效应提示：**部分通过**（1/2 次运行）
- N6 深度异常（仅 0.4% 正常深度）：**未通过**（0/2 次运行）
- 建议中止分析：**未通过**（0/2 次运行）

**根因**: LLM 仅读取 CSV 内容描述，未对样本数据进行深度统计分析。需要在 workflow_selection 阶段加入预检查步骤（读取 `samples.csv` 判断 batch 分组）。

### TC-06a qPCR：结果未量化

Chat 返回了工作流/计算结果，但 IL6 ~8x 上调的具体数值未在响应中明确给出。这是提取结果的问题，不是执行问题。

---

## 下一步行动

1. **[即刻]** 在 dev 执行 `scripts/sync_to_dev.sh` 部署 DB pool fix（commit `bae6ea22f6`）
2. **[短期]** 增大 GWAS 上传超时（`test_data_workflows.py` GWAS 测试 `timeout=300`）
3. **[中期]** 确认 Ludwig ML 工作流在 dev 可路由（`integration/next-phase` → dev 合并）
4. **[中期]** TC-02 批次效应：在系统 prompt 中加入"上传 CSV 时检查样本元数据 batch 分组"的引导

---

## 账户清单

| 账户 | 密码 | 层级 | 到期 |
|------|------|------|------|
| demo1@biomate.ai | BioMate2026! | free | - |
| demo2@biomate.ai | BioMate2026! | free | - |
| demo3@biomate.ai | BioMate2026! | free | - |
| trial1@biomate.ai | BioMate2026!Trial | professional | 2027-05-09 |
| trial2@biomate.ai | BioMate2026!Trial | professional | 2027-05-09 |
| trial3@biomate.ai | BioMate2026!Trial | professional | 2027-05-09 |
| trial4@biomate.ai | BioMate2026!Trial | professional | 2027-05-09 |
| trial5@biomate.ai | BioMate2026!Trial | professional | 2027-05-09 |

**HK 代理**: http://47.242.215.11 → https://dev-public.biomate.ai (52.42.49.175)
