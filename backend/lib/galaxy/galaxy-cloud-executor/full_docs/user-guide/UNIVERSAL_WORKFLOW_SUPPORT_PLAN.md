# Galaxy Cloud 通用 Workflow 支持计划

## 目标

让 `galaxy_cloud` 模块成为一个**完全通用的云执行引擎**，能够执行**任何** Galaxy workflow，无论工具来源、复杂度如何。

## 当前限制分析

### 1. 工具 XML 获取限制 ⚠️

**当前实现**：
```python
# tool_executor.py
async def get_tool_xml(tool_id: str):
    # 仅支持：
    # 1. 本地 toolshed (✓ 已实现)
    # 2. GitHub tools-iuc (✓ 已实现)
    # 3. 其他 toolshed 仓库 (✗ 不支持)
```

**问题**：
- ❌ 不支持 `galaxyp`, `devteam`, `bgruening` 等其他 toolshed
- ❌ 不支持私有 toolshed
- ❌ 不支持直接从 toolshed API 下载

### 2. Cheetah 模板限制 ⚠️

**当前实现**：
```python
# 仅支持：
# ✓ #for 循环
# ✓ 变量替换 ${var} $var
# ✗ #if/#else 条件
# ✗ #set 变量赋值
# ✗ 函数调用
# ✗ 过滤器 (filters)
```

**问题**：很多工具使用复杂的 Cheetah 模板。

### 3. 工具特性支持限制 ⚠️

**当前未支持**：
- ❌ `<repeat>` - 重复参数块
- ❌ `<conditional>` - 条件参数
- ❌ `<section>` - 参数分组
- ❌ Dynamic options - 动态选项列表
- ❌ Data column metadata - 列元数据
- ❌ Tool data tables - 工具数据表

### 4. Workflow 特性限制 ⚠️

**当前未支持**：
- ❌ `when` 表达式 - 条件步骤执行
- ❌ Subworkflow - 子工作流
- ❌ 参数连接的复杂映射
- ❌ Runtime parameter inputs

### 5. 数据处理限制 ⚠️

**当前实现**：
- ✓ 简单数据集上传/下载
- ✓ 基本集合 (list) 支持
- ❌ 嵌套集合 (list:paired)
- ❌ 数据集元数据传递
- ❌ 复合数据类型 (composite datatypes)

---

## 实现方案：达到 100% 通用支持

### 方案 A：完全独立实现 (巨大工作量) 🔴

**需要实现**：
1. 完整的 Cheetah 模板引擎
2. 完整的 Galaxy tool XML 解析器
3. 所有 Galaxy 数据类型处理
4. Galaxy API 集成
5. 工具依赖管理
6. 数据库集成

**估计工作量**：3-6 个月
**风险**：高（需要复现 Galaxy 核心功能）

### 方案 B：混合模式 - Galaxy 解析 + 云执行 (推荐) 🟢

**核心思想**：
- Galaxy 负责：工具 XML 解析、命令构建、参数验证
- `galaxy_cloud` 负责：云执行、数据传输、作业管理

**实现方式**：

#### 子方案 B1：使用 Galaxy API 模式 ⭐⭐⭐

```
用户 → Galaxy Server (本地/远程)
         ↓
         解析 workflow
         解析工具 XML
         构建命令
         ↓
      galaxy_cloud 模块
         ↓
      云端执行 (AWS Batch)
```

**实现步骤**：
1. Galaxy 运行在本地（或远程服务器）
2. Galaxy 解析 workflow，生成每个步骤的完整命令
3. `galaxy_cloud` 通过 API 获取命令和参数
4. 在云端执行
5. 结果返回 Galaxy

**优点**：
- ✅ 100% 支持所有 Galaxy 特性
- ✅ 工具 XML 由 Galaxy 处理
- ✅ 利用现有 Galaxy 生态
- ✅ 无需重新实现 Galaxy 核心

**缺点**：
- ⚠️ 需要 Galaxy 实例运行
- ⚠️ 不能完全独立

#### 子方案 B2：嵌入 Galaxy Core Library ⭐⭐

```python
# 直接使用 Galaxy 的库
from galaxy.tools import Tool
from galaxy.jobs.command_factory import build_command

tool = Tool.from_file('tool.xml')
command = tool.build_command_line(params)
# 然后在云端执行 command
```

**优点**：
- ✅ 复用 Galaxy 代码
- ✅ 不需要运行 Galaxy 服务器
- ✅ 支持所有工具特性

**缺点**：
- ⚠️ 依赖 Galaxy 代码库
- ⚠️ 需要 Galaxy 数据库或模拟层

### 方案 C：增强当前实现 (渐进式) 🟡

**逐步添加功能**：
1. ✅ 基本工具支持 (已完成 70%)
2. 🔨 增强 Cheetah 模板
3. 🔨 添加更多 toolshed 支持
4. 🔨 支持常见工具特性
5. 🔨 逐步覆盖更多场景

**优点**：
- ✅ 渐进式，风险低
- ✅ 完全独立

**缺点**：
- ❌ 永远无法 100% 覆盖
- ❌ 需要大量测试和调试

---

## 推荐方案：**B1 + C 混合**

### 架构设计

```
galaxy_cloud 模块
├── 模式 1: 独立模式 (当前实现)
│   ├── 适用：简单 workflow (70% 场景)
│   ├── 工具源：本地 XML / GitHub / 静态映射
│   └── 持续增强 Cheetah 和工具特性支持
│
└── 模式 2: Galaxy 集成模式 (新增)
    ├── 适用：复杂 workflow (100% 场景)
    ├── galaxy_job_runner.py (已实现)
    └── galaxy_api_bridge.py (新增)
```

### 实现优先级

#### 阶段 1：完善独立模式 (1-2 周) 🔨

**目标**：支持 80% 的常见 workflow

1. **增强 Cheetah 模板引擎**
   ```python
   # 添加支持：
   # - #if/#else/#elif
   # - #set 变量
   # - 简单的函数调用 (str(), int(), len())
   # - 基本的过滤器
   ```

2. **扩展工具 XML 源**
   ```python
   # 支持更多 toolshed
   toolshed_repos = {
       'iuc': 'galaxyproject/tools-iuc',
       'galaxyp': 'galaxyproject/tools-galaxyp',
       'devteam': 'galaxyproject/tools-devteam',
       'bgruening': 'bgruening/galaxytools'
   }
   ```

3. **支持常见工具特性**
   ```python
   # - <repeat> 基本支持
   # - <conditional> 基本支持
   # - 数据集元数据读取
   ```

4. **本地 Galaxy 工具缓存**
   ```python
   # 从本地 Galaxy 实例提取工具信息
   # 缓存到本地文件，加速后续执行
   ```

#### 阶段 2：Galaxy API 桥接 (2-3 周) 🔨

**目标**：100% workflow 支持

1. **实现 Galaxy API Bridge**
   ```python
   # galaxy_cloud/galaxy_workflow/galaxy_api_bridge.py
   class GalaxyAPIBridge:
       """Bridge to Galaxy API for tool resolution"""

       async def resolve_tool_command(self, tool_id, tool_state):
           """Let Galaxy resolve tool to command"""
           # 调用 Galaxy API
           # 返回完整的命令行
   ```

2. **可选的 Galaxy 实例**
   ```python
   config = {
       'galaxy_url': 'http://localhost:8080',  # 可选
       'galaxy_api_key': 'xxx',                 # 可选

       # 如果提供，优先使用 Galaxy 解析
       # 否则使用独立模式
   }
   ```

#### 阶段 3：完全自动化 (1 周) 🔨

**目标**：零配置运行

1. **自动检测 Galaxy 安装**
   ```python
   # 自动查找：
   # - 本地 Galaxy 实例
   # - 环境变量 $GALAXY_ROOT
   # - ~/.galaxy/
   # - /usr/local/galaxy/
   ```

2. **智能回退机制**
   ```python
   执行 workflow:
   1. 尝试从本地 XML 解析 → 成功 ✓
   2. 失败 → 尝试 GitHub 下载
   3. 失败 → 尝试 Galaxy API (如果配置)
   4. 失败 → 使用静态映射
   5. 失败 → 报错并建议配置
   ```

---

## 实施计划

### Week 1-2: 增强独立模式

- [x] 本地 toolshed 支持
- [ ] 增强 Cheetah 模板 (#if, #set, #for 嵌套)
- [ ] 支持更多 GitHub toolshed 仓库
- [ ] 工具 XML 缓存机制
- [ ] 测试 20+ 常见工具

### Week 3-4: Galaxy 集成

- [ ] galaxy_api_bridge.py 实现
- [ ] 可选 Galaxy 实例配置
- [ ] 混合模式：独立 + Galaxy API
- [ ] 自动回退机制
- [ ] 测试复杂 workflow

### Week 5: 完善和文档

- [ ] 自动检测 Galaxy 安装
- [ ] 完整的配置选项
- [ ] 性能优化
- [ ] 完善文档
- [ ] 示例和教程

---

## 最终使用体验

### 场景 1：简单 workflow（自动独立模式）

```python
from galaxy_cloud import GalaxyCloudIntegration

# 零配置，自动工作
integration = GalaxyCloudIntegration({
    'aws': {'enabled': True, ...}
})

# 自动从本地/GitHub 获取工具 XML，解析并执行
await integration.run_workflow('simple_workflow.ga')
```

### 场景 2：复杂 workflow（自动 Galaxy 模式）

```python
# 自动检测到本地 Galaxy
integration = GalaxyCloudIntegration({
    'aws': {...},
    # 自动发现: galaxy_url='http://localhost:8080'
})

# 自动使用 Galaxy API 解析复杂工具
await integration.run_workflow('complex_qiime2_workflow.ga')
```

### 场景 3：企业部署（混合模式）

```python
integration = GalaxyCloudIntegration({
    'local_tool_dir': '/data/galaxy/shed_tools',  # 本地工具
    'galaxy_url': 'https://galaxy.company.com',   # 企业 Galaxy
    'toolshed_repos': {                            # 自定义 repo
        'custom': 'company/galaxy-tools'
    },
    'aws': {...}
})

# 智能选择最佳方式执行每个工具
await integration.run_workflow('workflow.ga')
```

---

## 成功指标

- ✅ 支持 95%+ Galaxy toolshed 工具
- ✅ 支持所有 workflow 类型
- ✅ 零配置可运行简单 workflow
- ✅ 可选 Galaxy 集成支持复杂 workflow
- ✅ 完全离线运行（如果有本地 toolshed）
- ✅ 性能：工具解析 < 1秒，workflow 提交 < 5秒

---

## 下一步行动

**立即开始**：

1. 增强 Cheetah 模板引擎（支持 #if/#else）
2. 添加更多 GitHub toolshed 支持
3. 实现工具 XML 缓存
4. 测试你的 QIIME2 workflow

**需要你的输入**：

1. 你有本地 Galaxy 安装吗？路径在哪？
2. 你希望先支持哪些工具/workflow？
3. 是否可以运行一个 Galaxy 实例用于复杂工具解析？

---

**创建时间**: 2025-10-17
**版本**: 1.0
**状态**: 计划中 → 实施中
