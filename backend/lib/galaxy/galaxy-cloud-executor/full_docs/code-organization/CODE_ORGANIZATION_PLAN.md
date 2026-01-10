# Galaxy Cloud Executor 代码整理计划

## 当前代码结构分析

### 📁 目录结构概览

```
galaxy-cloud-executor/
├── galaxy_cloud/              # 核心模块
│   ├── __init__.py
│   ├── cli.py                 # 命令行接口
│   ├── config.py              # 配置管理
│   ├── factory.py             # 工厂模式
│   ├── registry.py            # 注册表
│   ├── core/                  # 核心功能
│   ├── providers/             # 云提供商（AWS, GCP等）
│   └── galaxy_workflow/       # Galaxy workflow 集成
│
├── examples/                  # 示例脚本
├── docs/                      # 文档
├── full_docs/                 # 完整文档
├── tests/                     # 单元测试
├── testing/                   # 集成测试
├── scripts/                   # 辅助脚本
├── config/                    # 配置文件
└── test_data/                 # 测试数据
```

### 📊 代码统计

执行命令查看：
```bash
find galaxy_cloud -name "*.py" | wc -l    # Python 文件数
find galaxy_cloud -name "*.py" | xargs wc -l | tail -1  # 总行数
```

---

## 发现的问题

### 1. 文档混乱 ⚠️

**问题**：根目录有多个文档，内容重复或过时

```
- ARCHITECTURE_CLARIFICATION.md
- DOCUMENTATION_STRUCTURE.md
- FILE_ORGANIZATION.md
- FINAL_STATUS.md
- LOCAL_TOOLSHED_GUIDE.md
- PRODUCTION_DEPLOYMENT_GUIDE.md
- README.md
- UNIVERSAL_SUPPORT_ACTION_PLAN.md
- UNIVERSAL_WORKFLOW_SUPPORT_PLAN.md
- WORKFLOW_FIXES_SUMMARY.md
```

**解决方案**：
1. 保留核心文档：README.md
2. 移动详细文档到 docs/ 或 full_docs/
3. 合并重复内容
4. 删除过时文档

### 2. 测试目录重复 ⚠️

**问题**：
- `tests/` - 单元测试？
- `testing/` - 集成测试？
- 根目录还有 `test_tool_executor.py`

**解决方案**：
1. 统一测试目录结构：
```
tests/
├── unit/           # 单元测试
├── integration/    # 集成测试
└── fixtures/       # 测试数据和fixture
```

### 3. 示例脚本组织 ⚠️

**问题**：
- `examples/` 目录
- 根目录有 `run_qiime2_cloud.sh`
- `scripts/` 目录

**解决方案**：明确分类
- `examples/` - 用户示例
- `scripts/` - 开发/维护脚本

### 4. 配置文件散落 ⚠️

**问题**：
- `config/` 目录
- 根目录有 `tool_containers.yaml`
- 根目录有 `pyproject.toml`, `requirements.txt`

**解决方案**：
- 保持 `config/` 作为配置目录
- 项目配置留在根目录

### 5. 临时/调试文件 ⚠️

**问题**：
- `job_detail.json`
- `check_aws_logs.sh`
- `check_batch_job.sh`

**解决方案**：
- 移到 `scripts/debug/`
- 或添加到 `.gitignore`

---

## 整理计划

### 阶段 1：文档整理 📚

#### 步骤 1.1：创建统一的文档结构

```
docs/
├── README.md                    # 文档索引
├── getting-started/
│   ├── quick-start.md          # 快速开始
│   ├── installation.md         # 安装指南
│   └── configuration.md        # 配置说明
├── user-guide/
│   ├── independent-mode.md     # 独立模式使用
│   ├── galaxy-integration.md   # Galaxy集成
│   ├── local-toolshed.md       # 本地toolshed
│   └── workflows.md            # Workflow支持
├── architecture/
│   ├── overview.md             # 架构概览
│   ├── core-modules.md         # 核心模块
│   ├── providers.md            # 云提供商
│   └── workflow-system.md      # Workflow系统
├── development/
│   ├── contributing.md         # 贡献指南
│   ├── testing.md              # 测试指南
│   └── debugging.md            # 调试技巧
└── deployment/
    ├── aws-setup.md            # AWS配置
    ├── production.md           # 生产部署
    └── troubleshooting.md      # 故障排查
```

#### 步骤 1.2：合并现有文档

**操作**：
1. 提取各文档的核心内容
2. 按新结构重新组织
3. 删除重复和过时内容

**映射关系**：
```
当前文档 → 新位置
─────────────────────────────────────
README.md → README.md (更新)
LOCAL_TOOLSHED_GUIDE.md → docs/user-guide/local-toolshed.md
PRODUCTION_DEPLOYMENT_GUIDE.md → docs/deployment/production.md
ARCHITECTURE_CLARIFICATION.md → docs/architecture/overview.md
UNIVERSAL_SUPPORT_ACTION_PLAN.md → docs/user-guide/workflows.md
... (其他文档类似)
```

### 阶段 2：测试代码整理 🧪

#### 步骤 2.1：重组测试目录

```
tests/
├── __init__.py
├── conftest.py                 # pytest配置
├── unit/                       # 单元测试
│   ├── test_config.py
│   ├── test_factory.py
│   ├── test_registry.py
│   ├── core/
│   │   ├── test_job.py
│   │   └── test_executor.py
│   ├── providers/
│   │   └── aws/
│   │       ├── test_auth.py
│   │       └── test_executor.py
│   └── galaxy_workflow/
│       ├── test_converter.py
│       ├── test_tool_executor.py
│       └── test_tool_registry.py
│
├── integration/                # 集成测试
│   ├── test_aws_batch.py
│   ├── test_workflow_execution.py
│   └── test_galaxy_integration.py
│
└── fixtures/                   # 测试数据
    ├── workflows/
    ├── tools/
    └── data/
```

#### 步骤 2.2：移动现有测试

```bash
# 移动 test_tool_executor.py
mv test_tool_executor.py tests/unit/galaxy_workflow/

# 整合 testing/ 目录
mv testing/* tests/integration/

# 移动测试数据
mv test_data tests/fixtures/
```

### 阶段 3：示例和脚本整理 📝

#### 步骤 3.1：examples/ 目录

```
examples/
├── README.md                   # 示例索引
├── quick_start.py              # 最简单示例
├── run_any_galaxy_workflow.py # 通用workflow运行
├── run_qiime2_workflow.py      # QIIME2特定示例
└── advanced/
    ├── custom_executor.py      # 自定义执行器
    └── batch_processing.py     # 批量处理
```

#### 步骤 3.2：scripts/ 目录

```
scripts/
├── setup/
│   ├── install_dependencies.sh
│   └── configure_aws.sh
├── debug/
│   ├── check_aws_logs.sh
│   ├── check_batch_job.sh
│   └── inspect_workflow.py
└── maintenance/
    ├── cleanup_s3.sh
    └── update_tool_cache.py
```

### 阶段 4：核心代码优化 ⚙️

#### 步骤 4.1：galaxy_cloud/ 模块

**当前结构**：
```
galaxy_cloud/
├── __init__.py
├── cli.py
├── config.py
├── factory.py
├── registry.py
├── core/
├── providers/
└── galaxy_workflow/
```

**优化点**：

1. **__init__.py** - 导出主要接口
```python
from .factory import CloudExecutorFactory
from .galaxy_workflow.integration import GalaxyCloudIntegration
from .config import Config

__version__ = "0.1.0"
__all__ = ['CloudExecutorFactory', 'GalaxyCloudIntegration', 'Config']
```

2. **添加类型注解** - 所有公共API添加类型提示

3. **添加文档字符串** - 所有模块、类、函数添加docstring

4. **错误处理** - 统一异常类

#### 步骤 4.2：galaxy_workflow/ 子模块

**当前文件**：
```bash
ls galaxy_cloud/galaxy_workflow/
converter.py
dag_executor.py
data_manager.py
galaxy_job_runner.py
integration.py
job_config_parser.py
models.py
tool_executor.py         # 新增 - 今天实现
tool_registry.py
```

**优化**：

1. **tool_executor.py** - 完善实现
   - 增强 Cheetah 模板支持
   - 添加更多 toolshed 支持
   - 完善错误处理

2. **converter.py** - 代码清理
   - 移除注释掉的代码
   - 优化长函数

3. **models.py** - 完善数据模型
   - 添加验证
   - 添加文档

### 阶段 5：配置文件整理 ⚙️

#### 步骤 5.1：config/ 目录

```
config/
├── README.md                   # 配置文档
├── aws_cloud_config.yaml       # AWS配置示例
├── tool_containers.yaml        # 工具容器映射
└── examples/
    ├── development.yaml        # 开发环境
    ├── production.yaml         # 生产环境
    └── local.yaml              # 本地测试
```

#### 步骤 5.2：移动配置文件

```bash
# 移动 tool_containers.yaml
mv tool_containers.yaml config/

# 更新引用
find . -name "*.py" -exec sed -i '' 's/tool_containers.yaml/config\/tool_containers.yaml/g' {} \;
```

---

## 实施顺序

### 第1周：基础整理

- [ ] Day 1: 文档整理（移动、合并）
- [ ] Day 2: 测试代码整理
- [ ] Day 3: 示例和脚本整理

### 第2周：代码优化

- [ ] Day 4-5: 核心模块优化
- [ ] Day 6-7: galaxy_workflow 子模块优化

### 第3周：完善和测试

- [ ] Day 8: 配置文件整理
- [ ] Day 9: 完整测试
- [ ] Day 10: 文档更新

---

## 预期结果

### 整理后的目录结构

```
galaxy-cloud-executor/
├── README.md                   # 项目README
├── pyproject.toml              # Python项目配置
├── requirements.txt            # 依赖列表
│
├── galaxy_cloud/               # 核心模块（清晰、有文档）
│   ├── __init__.py
│   ├── core/
│   ├── providers/
│   └── galaxy_workflow/
│
├── config/                     # 所有配置文件
│   ├── aws_cloud_config.yaml
│   ├── tool_containers.yaml
│   └── examples/
│
├── docs/                       # 完整文档
│   ├── getting-started/
│   ├── user-guide/
│   ├── architecture/
│   ├── development/
│   └── deployment/
│
├── examples/                   # 用户示例
│   ├── README.md
│   ├── quick_start.py
│   └── advanced/
│
├── scripts/                    # 开发脚本
│   ├── setup/
│   ├── debug/
│   └── maintenance/
│
└── tests/                      # 测试代码
    ├── unit/
    ├── integration/
    └── fixtures/
```

### 代码质量提升

- ✅ 清晰的模块组织
- ✅ 完整的类型注解
- ✅ 全面的文档字符串
- ✅ 统一的错误处理
- ✅ 完善的测试覆盖

### 用户体验提升

- ✅ 清晰的文档结构
- ✅ 丰富的示例代码
- ✅ 简单的入门指南
- ✅ 详细的故障排查

---

## 下一步行动

**立即开始**：

1. 创建新的文档结构
2. 移动和合并现有文档
3. 重组测试目录
4. 清理根目录

**需要确认**：

1. 是否保留 `full_docs/` 目录？
2. `testing/` 目录的内容是否还需要？
3. 哪些文档需要优先整理？

---

**创建时间**: 2025-10-17
**状态**: 计划中
**预计完成**: 1-2周
