# Workflow AI Operations Module

LLM驱动的智能workflow运维系统核心模块

## 文件结构

```
workflow_ops/
├── __init__.py                 # 模块导出
├── types.py                    # 数据类型定义
├── llm_client.py              # 统一LLM客户端（支持多提供商）
├── log_analyzer.py            # 智能日志分析器
├── auto_healer.py             # 自动错误修复系统
├── query_agent.py             # 交互式查询Agent
└── README.md                  # 本文件
```

## 核心组件

### 1. UnifiedLLMClient

**文件**: `llm_client.py`

**功能**: 统一的LLM接口，支持多个提供商

**支持的提供商**:
- Anthropic Claude (claude-3-5-sonnet, claude-3-haiku)
- OpenAI GPT (gpt-4o, gpt-4o-mini)
- Ollama (本地模型)

**特性**:
- 自动成本计算
- 预算控制
- 重试逻辑
- 使用统计

**示例**:

```python
from galaxy.ai.workflow_ops import UnifiedLLMClient

client = UnifiedLLMClient(daily_budget=10.0)

result = client.call(
    messages=[{"role": "user", "content": "Analyze this log"}],
    model='claude-3-5-sonnet-20241022'
)

print(result['content'])
print(f"Cost: ${result['usage_stats'].cost:.4f}")
```

### 2. WorkflowLogAnalyzer

**文件**: `log_analyzer.py`

**功能**: 智能日志分析，提取错误、警告、进度

**分级处理策略**:
1. **轻量级**: 正则匹配（INFO、进度）- 免费
2. **中量级**: 小模型分析（WARNING）- 低成本
3. **重量级**: 大模型分析（ERROR）- 高准确性

**示例**:

```python
from galaxy.ai.workflow_ops import WorkflowLogAnalyzer

analyzer = WorkflowLogAnalyzer()

logs = {
    'nextflow_log': ["[ERROR] Invalid parameter 'genome'"],
    'stderr': ["Out of memory"],
}

result = analyzer.analyze_logs_stream(logs, context={})

print(f"Status: {result.status}")
print(f"Issues found: {len(result.issues)}")
print(f"AI Insights: {result.insights}")
```

### 3. WorkflowAutoHealer

**文件**: `auto_healer.py`

**功能**: 自动检测和修复workflow错误

**支持的修复类型**:
- **参数配置错误**: 自动修正参数值
- **数据格式转换**: 转换文件格式
- **资源扩容**: 增加内存/磁盘
- **简单重试**: 处理临时性错误

**修复模式**:
- `safe`: 仅低风险操作（推荐生产）
- `moderate`: 低/中风险操作
- `aggressive`: 所有操作（慎用）
- `manual`: 需用户确认

**示例**:

```python
from galaxy.ai.workflow_ops import WorkflowAutoHealer
from galaxy.ai.workflow_ops.types import Issue, IssueSeverity, IssueType

healer = WorkflowAutoHealer(auto_fix_mode='safe')

# 模拟错误
issue = Issue(
    severity=IssueSeverity.ERROR,
    type=IssueType.INVALID_PARAM,
    message="Parameter 'genome' value 'hg19' not found",
    suggestion="Use 'hg38'",
    auto_fixable=True
)

error_context = {
    'invocation_id': 123,
    'issues': [issue],
    'error_logs': [...],
    'app': app,
}

result = healer.analyze_and_fix(error_context)

print(f"Fixable: {result['fixable']}")
print(f"Applied fixes: {len(result['applied_fixes'])}")
```

### 4. WorkflowQueryAgent

**文件**: `query_agent.py`

**功能**: 自然语言查询workflow状态

**支持的查询类型**:
- 错误原因分析
- 性能对比
- 预计完成时间
- 历史运行对比

**示例**:

```python
from galaxy.ai.workflow_ops import WorkflowQueryAgent

agent = WorkflowQueryAgent(app=app)

response = agent.query(
    user_question="为什么第3步失败了？",
    invocation_id=123
)

print(response.answer)
print(f"Confidence: {response.confidence}")
```

## 数据类型 (types.py)

### Issue

```python
@dataclass
class Issue:
    severity: IssueSeverity  # info|warning|error|critical
    type: IssueType          # data_format|invalid_param|resource_limit...
    message: str
    suggestion: str
    auto_fixable: bool
    confidence: float
```

### FixPlan

```python
@dataclass
class FixPlan:
    fixable: bool
    fix_type: FixType       # config_adjustment|data_conversion|...
    fix_actions: List[FixAction]
    explanation: str
    confidence: float
    requires_user_confirmation: bool
```

### LogAnalysisResult

```python
@dataclass
class LogAnalysisResult:
    status: WorkflowStatus  # running|warning|error|completed
    progress: ProgressInfo
    issues: List[Issue]
    insights: str          # LLM生成的自然语言洞察
    llm_cost: float
```

## 集成到NextflowMonitor

在 `nextflow_monitor.py` 中已集成：

```python
class NextflowMonitor:
    def __init__(self, ..., enable_ai_ops=True):
        if enable_ai_ops:
            self.log_analyzer = WorkflowLogAnalyzer(...)
            self.auto_healer = WorkflowAutoHealer(...)

    def monitor_once(self):
        # 收集日志
        logs = self.collect_logs()

        # AI分析
        if self.log_analyzer:
            result = self.log_analyzer.analyze_logs_stream(logs)

            # 自动修复
            if result.issues:
                self.auto_healer.analyze_and_fix(...)
```

## 环境变量配置

参见 `config/workflow_ai_ops.env.example`

必需:
```bash
ANTHROPIC_API_KEY=sk-ant-...   # 或 OPENAI_API_KEY
```

可选:
```bash
NEXTFLOW_AI_DAILY_BUDGET=10.0
NEXTFLOW_AUTO_FIX_MODE=safe
```

## 成本估算

典型使用（每天10个workflows）:

| 场景 | 模型 | 成本/次 | 每天总成本 |
|-----|------|---------|----------|
| 正常运行（无错误） | Haiku | $0.003 | $0.30 |
| 有警告 | Haiku | $0.006 | $0.60 |
| 有错误（含修复） | Sonnet | $0.025 | $2.50 |

**推荐预算**: $5-10/天（中等负载）

## 测试

运行测试:

```bash
pytest tests/integration/test_workflow_ai_ops.py -v
```

## 扩展指南

### 添加自定义修复策略

```python
# 在 auto_healer.py 中

class MyCustomFixStrategy(FixStrategy):
    def can_fix(self, issue, context):
        return issue.type == IssueType.MY_CUSTOM_TYPE

    def generate_fix(self, issue, context):
        # 生成修复方案
        return FixPlan(...)

    def apply_fix(self, fix_plan, context):
        # 执行修复
        return True

# 注册策略
auto_healer.strategies.append(MyCustomFixStrategy())
```

### 添加新的Issue类型

```python
# 在 types.py 中

class IssueType(str, Enum):
    # ... 现有类型 ...
    MY_NEW_TYPE = "my_new_type"
```

### 自定义日志模式

```python
# 在 log_analyzer.py 的 LogPatternMatcher 中

ERROR_PATTERNS = [
    # ... 现有模式 ...
    (r'my_custom_error_pattern', IssueType.MY_NEW_TYPE),
]
```

## API文档

RESTful API端点定义在:
- `lib/galaxy/webapps/galaxy/api/workflow_ai_ops.py`

端点:
- `POST /api/workflows/{id}/ai/analyze` - 分析workflow
- `POST /api/workflows/{id}/ai/query` - 自然语言查询
- `POST /api/workflows/{id}/ai/auto_fix` - 触发自动修复
- `GET /api/workflows/{id}/ai/budget` - 预算统计

## 文档

- 设计文档: `docs/LLM_WORKFLOW_ORCHESTRATION_DESIGN.md`
- 快速开始: `docs/WORKFLOW_AI_OPS_QUICKSTART.md`

## 贡献

欢迎贡献！特别需要:
- 新的修复策略
- 改进的日志模式匹配
- 前端Chat UI实现
- 多语言支持

## 许可证

与Galaxy项目相同 (Academic Free License 3.0)
