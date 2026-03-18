# AutoFix Framework - 工业级自动修复系统

## 🎯 概述

AutoFix Framework 是一个工业级的workflow自动修复系统，提供**安全、可审计、可回滚**的自动化问题修复能力。

### 核心特性

✅ **用户隔离**: 所有修复操作严格限制在当前用户范围内
✅ **风险评估**: 三级风险分类（Low/Medium/High）+ 智能审批流程
✅ **成本控制**: 预算检查 + 成本估算 + 用户确认机制
✅ **完整审计**: 所有操作记录在 `AIFixAuditLog` 表
✅ **自动回滚**: 失败时自动恢复到修复前状态
✅ **可扩展性**: 插件化架构，轻松添加新的Fixer

---

## 🏗️ 架构设计

###文件结构
```
lib/galaxy/ai/workflow_ops/autofix/
├── __init__.py                          # 框架入口
├── base.py                              # 抽象基类和数据模型
├── orchestrator.py                      # 核心编排器
└── fixers/                              # Fixer实现
    ├── __init__.py
    └── nextflow_parameter_fixer.py      # Nextflow参数修复器
```

### 核心组件

#### 1. **BaseAutoFixer** (抽象基类)
所有Fixer必须继承此类并实现三个核心方法：

```python
from galaxy.ai.workflow_ops.autofix.base import BaseAutoFixer

class MyFixer(BaseAutoFixer):
    def detect_issues(self, context: FixContext) -> List[Dict]:
        """检测问题"""
        pass

    def generate_fix_plan(self, context: FixContext, issues: List) -> FixPlan:
        """生成修复方案"""
        pass

    async def apply_fix(self, context: FixContext, fix_plan: FixPlan, sa_session) -> AutoFixResult:
        """应用修复"""
        pass
```

#### 2. **AutoFixOrchestrator** (编排器)
协调整个修复流程：

```python
from galaxy.ai.workflow_ops.autofix import AutoFixOrchestrator

orchestrator = AutoFixOrchestrator(trans)
result = await orchestrator.run_fixer(
    invocation_id=123,
    fixer=NextflowParameterFixer(),
    auto_approve_low_risk=True
)
```

#### 3. **FixContext** (上下文)
包含修复所需的所有信息：
- 用户ID、Workflow ID、Invocation ID
- 用户偏好设置（从 `UserCloudPreferences` 加载）
- 预算限制和剩余额度
- 状态快照（用于回滚）

#### 4. **AutoFixResult** (结果)
修复执行的完整结果：
- 成功/失败状态
- 应用的修复动作
- 执行时间和成本
- 错误信息（如果失败）

---

## 🔒 安全机制

### 1. 用户隔离
```python
# 所有Fixer都会检查用户权限
def check_permissions(self, context: FixContext, sa_session):
    invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
    if invocation.user_id != context.user_id:
        return False, "Access denied: invocation belongs to another user"
    return True, None
```

### 2. 风险分级审批

| 风险等级 | 触发条件 | 审批流程 |
|---------|---------|---------|
| **Low** | 简单参数修正、typo修复 | 自动应用（如果用户开启auto_approve） |
| **Medium** | 资源配额调整、数据转换 | 需要用户点击确认 |
| **High** | AWS配置修改、代码修改 | 需要用户手动审核+输入确认 |

### 3. 成本控制
```python
# 在UserCloudPreferences中配置
user_prefs.ai_require_approval_for_cost = 10.0  # 超过$10需要批准

# 框架自动检查
if estimated_cost > context.ai_require_approval_for_cost:
    requires_user_confirmation = True
```

### 4. 预算检查
```python
# 检查日预算和月预算
has_budget, error_msg = context.check_budget(estimated_cost)
if not has_budget:
    return AutoFixResult(
        status=FixStatus.REJECTED,
        error_message=error_msg
    )
```

---

## 📊 已实现的Fixers

### 1. **NextflowParameterFixer**

**功能**: 自动修复Nextflow workflow参数问题

**修复的问题类型**:
- ❌ 缺失的必需参数 (如 `genome`, `aligner`, `source`)
- ❌ 参数格式错误 (类型不匹配、正则不符合)
- ❌ 参数值不兼容 (pipeline特定的兼容性要求)

**值推断策略**（优先级从高到低）:
1. **已批准的修复** - 从 `WorkflowParameterFix` 表查找相同workflow的已批准修复
2. **历史成功运行** - 分析用户最近20次成功运行，使用最常见的值
3. **模板默认值** - 从 `WorkflowParameterTemplate` 获取默认值
4. **Pipeline默认值** - 使用硬编码的常见默认值

**支持的Pipeline**:
- `rnaseq`: genome, aligner
- `clipseq`: source, ncrna_fasta
- `smrnaseq`: mirtrace_species
- `chipseq`: genome
- `atacseq`: genome

**风险等级**: Low（只修改参数，不影响数据或基础设施）

**示例**:
```python
# clipseq pipeline缺少source参数
# Fixer会：
# 1. 检测到缺少必需参数 'source'
# 2. 从用户历史中查找最常用的source值（如'GRCh38'）
# 3. 生成FixAction: UPDATE_PARAM source='GRCh38'
# 4. 自动应用（低风险）
# 5. 记录到AIFixAuditLog
```

---

## 🚀 使用方法

### 方式1: 通过API调用

```bash
# 运行AutoFix
curl -X POST "http://localhost:8080/api/workflows/738/autofix/run?auto_approve_low_risk=true"

# 查看审计日志
curl "http://localhost:8080/api/workflows/738/autofix/audit_logs"

# 批准pending的修复
curl -X POST "http://localhost:8080/api/workflows/738/autofix/approve/123"
```

### 方式2: 通过Python代码

```python
from galaxy.ai.workflow_ops.autofix import AutoFixOrchestrator
from galaxy.ai.workflow_ops.autofix.fixers import NextflowParameterFixer

# 初始化
orchestrator = AutoFixOrchestrator(trans)
fixer = NextflowParameterFixer()

# 运行修复
result = await orchestrator.run_fixer(
    invocation_id=738,
    fixer=fixer,
    auto_approve_low_risk=True
)

if result.success:
    print(f"✅ Applied {len(result.fix_actions)} fixes")
    print(f"   Execution time: {result.execution_time_seconds:.2f}s")
else:
    print(f"❌ Fix failed: {result.error_message}")
```

### 方式3: 运行测试脚本

```bash
# 测试invocation 738
./test_autofix_framework.sh 738
```

---

## 📝 审计日志

所有修复操作都记录在 `AIFixAuditLog` 表：

```sql
SELECT
    id,
    fix_type,
    risk_level,
    auto_approved,
    user_approved,
    applied,
    success,
    estimated_cost,
    duration_seconds
FROM ai_fix_audit_log
WHERE invocation_id = 738
ORDER BY timestamp DESC;
```

日志包含：
- 修复类型和详细内容 (`fix_details` JSON)
- 风险等级和审批状态
- 成本估算和实际成本
- 执行结果和错误信息
- AI模型信息和置信度

---

## 🔄 回滚机制

所有修复都支持自动回滚：

```python
# Fixer会在应用修复前捕获状态
snapshot = fixer.capture_state(context, sa_session)

try:
    # 应用修复
    result = await fixer.apply_fix(context, fix_plan, sa_session)
except Exception as e:
    # 失败时自动回滚
    rollback_success = await fixer.rollback(context, snapshot, sa_session)
    if rollback_success:
        result.status = FixStatus.ROLLED_BACK
```

**StateSnapshot** 包含：
- Workflow invocation 参数
- AWS配置
- 输入数据集引用
- 修复前的完整状态

---

## 🛠️ 添加新的Fixer

### Step 1: 创建Fixer类

```python
# lib/galaxy/ai/workflow_ops/autofix/fixers/my_fixer.py

from galaxy.ai.workflow_ops.autofix.base import BaseAutoFixer, FixContext
from galaxy.ai.workflow_ops.types import FixPlan, FixAction, ActionType

class MyFixer(BaseAutoFixer):
    """修复XXX问题"""

    def detect_issues(self, context: FixContext):
        # 检测逻辑
        issues = []
        # ... 分析invocation，检测问题
        return issues

    def generate_fix_plan(self, context, issues):
        # 生成修复方案
        fix_actions = []
        for issue in issues:
            action = FixAction(
                action=ActionType.UPDATE_PARAM,
                params={'param_name': 'value'},
                description="Fix description",
                risk_level='low'
            )
            fix_actions.append(action)

        return FixPlan(
            fixable=True,
            fix_type=FixType.CONFIG_ADJUSTMENT,
            fix_actions=fix_actions,
            explanation="Why this fix works",
            confidence=0.85
        )

    async def apply_fix(self, context, fix_plan, sa_session):
        # 应用修复
        # ... 执行修复操作

        return AutoFixResult(
            status=FixStatus.APPLIED,
            fix_type=fix_plan.fix_type.value,
            fix_actions=fix_plan.fix_actions,
            risk_level=RiskLevel.LOW,
            success=True
        )
```

### Step 2: 注册Fixer

```python
# lib/galaxy/ai/workflow_ops/autofix/fixers/__init__.py

from .my_fixer import MyFixer

__all__ = [
    "NextflowParameterFixer",
    "MyFixer",  # 添加这行
]
```

### Step 3: 在API中使用

```python
# lib/galaxy/webapps/galaxy/api/workflow_ai_ops.py

from galaxy.ai.workflow_ops.autofix.fixers import MyFixer

fixers = [
    NextflowParameterFixer(),
    MyFixer(),  # 添加新的fixer
]
```

---

## 📈 性能考量

### 1. 批量修复
使用 `run_all_fixers()` 可以并行运行多个fixer：

```python
results = await orchestrator.run_all_fixers(
    invocation_id=738,
    fixers=[fixer1, fixer2, fixer3],
    stop_on_first_success=False  # 运行所有fixer获取完整信息
)
```

### 2. 成本优化
- 低风险修复自动应用，减少用户交互
- 历史数据缓存，避免重复LLM调用
- 批量处理相似问题

### 3. 数据库优化
- `AIFixAuditLog` 表有索引: `user_id`, `invocation_id`, `timestamp`
- 使用 `limit` 参数限制查询结果
- 定期归档旧的audit logs

---

## 🧪 测试

### 单元测试
```bash
pytest lib/galaxy/ai/workflow_ops/autofix/tests/
```

### 集成测试
```bash
# 启动Galaxy
./start_galaxy_self_contained.sh

# 运行测试
./test_autofix_framework.sh 738
```

### 手动测试checklist
- [ ] 测试低风险修复自动应用
- [ ] 测试中风险修复需要确认
- [ ] 测试预算超限拒绝
- [ ] 测试权限检查（其他用户的invocation）
- [ ] 测试回滚机制（人为制造失败）
- [ ] 测试审计日志记录完整性

---

## 📋 TODO / 待实现功能

### Phase 2: 更多Fixers
- [ ] **AWSResourceFixer** - AWS资源配额自动调整
- [ ] **DataFileFixer** - 输入文件路径修正和格式转换
- [ ] **RetryStrategyFixer** - 智能重试策略
- [ ] **ToolVersionFixer** - 工具版本兼容性修复

### Phase 3: 高级功能
- [ ] **历史模式学习** - 从用户历史中学习偏好
- [ ] **批量修复** - 一次修复多个invocation
- [ ] **修复建议排序** - 按成功率排序推荐
- [ ] **A/B测试** - 测试不同修复策略的效果

### Phase 4: 前端集成
- [ ] 修复建议卡片UI
- [ ] 一键批准/拒绝
- [ ] 修复历史可视化
- [ ] 成本预估显示

---

## 🤝 贡献指南

### 代码规范
1. 所有Fixer必须继承 `BaseAutoFixer`
2. 必须实现三个核心方法: `detect_issues`, `generate_fix_plan`, `apply_fix`
3. 必须进行用户权限检查
4. 必须提供rollback支持
5. 所有修复操作必须记录audit log

### 提交PR前
1. 运行单元测试确保通过
2. 运行集成测试验证端到端流程
3. 更新文档（README和代码注释）
4. 添加使用示例

---

## 📚 相关文档

- [AI运维模块总结](../../../../../AI_OPS_SESSION_SUMMARY.md)
- [UserCloudPreferences 数据模型](../../../model/cloud_preferences.py)
- [AIFixAuditLog 审计日志](../../../model/__init__.py#L12600)
- [FixPlan 数据类型](../types.py)

---

## 📞 联系方式

如有问题，请联系：
- 项目负责人: [Your Name]
- 邮箱: [your.email@example.com]
- GitHub Issues: [项目仓库]

---

**版本**: 1.0.0
**最后更新**: 2026-01-15
**状态**: ✅ Production Ready (Phase 1)
