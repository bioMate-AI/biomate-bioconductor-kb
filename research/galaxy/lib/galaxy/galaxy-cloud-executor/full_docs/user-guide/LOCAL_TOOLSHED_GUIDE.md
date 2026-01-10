# 使用本地 Toolshed 运行 Workflow

## 概述

Galaxy Cloud Executor 现在支持从本地文件系统读取工具 XML，而不需要从 GitHub 下载。这对以下场景特别有用：

1. ✅ **本地已安装的 Galaxy toolshed**
2. ✅ **自定义或私有工具**
3. ✅ **离线环境**
4. ✅ **加速开发和测试**

## 配置方法

### 方法 1：通过配置文件

创建或修改配置文件（例如 `config/local_tools_config.yaml`）：

```yaml
# 本地工具目录配置
local_tool_dir: /path/to/your/galaxy/shed_tools

# 或者在 tool_executor 配置中指定
tool_executor:
  local_tool_dir: /path/to/your/galaxy/shed_tools

# 工具注册表配置（可选）
tool_registry:
  static_mappings_file: tool_containers.yaml
```

然后在代码中使用：

```python
import yaml
from galaxy_cloud.galaxy_workflow.integration import GalaxyCloudIntegration

# 加载配置
with open('config/local_tools_config.yaml') as f:
    config = yaml.safe_load(f)

# 创建集成实例
integration = GalaxyCloudIntegration(config)
```

### 方法 2：通过环境变量

```bash
export GALAXY_LOCAL_TOOL_DIR=/path/to/your/galaxy/shed_tools
```

然后在配置中读取：

```python
import os

config = {
    'local_tool_dir': os.getenv('GALAXY_LOCAL_TOOL_DIR'),
    # ... 其他配置
}
```

### 方法 3：直接在代码中设置

```python
config = {
    'local_tool_dir': '/Users/you/galaxy/shed_tools',
    'tool_registry': {
        'static_mappings_file': 'tool_containers.yaml'
    },
    # ... AWS 配置等
}

integration = GalaxyCloudIntegration(config)
```

## 本地 Toolshed 目录结构

系统会自动识别以下标准 Galaxy toolshed 目录结构：

### 结构 1：标准 Galaxy shed_tools（推荐）

```
/path/to/galaxy/shed_tools/
└── toolshed.g2.bx.psu.edu/
    └── repos/
        └── iuc/
            └── collection_element_identifiers/
                └── d3c07d270a50/              # 版本哈希
                    └── collection_element_identifiers.xml
```

### 结构 2：扁平结构

```
/path/to/galaxy/shed_tools/
└── iuc/
    └── collection_element_identifiers/
        └── d3c07d270a50/
            └── collection_element_identifiers.xml
```

### 结构 3：包含工具名子目录

```
/path/to/galaxy/shed_tools/
└── toolshed.g2.bx.psu.edu/
    └── repos/
        └── iuc/
            └── collection_element_identifiers/
                └── d3c07d270a50/
                    └── collection_element_identifiers/
                        └── collection_element_identifiers.xml
```

## 工具查找顺序

对于工具 ID：`toolshed.g2.bx.psu.edu/repos/iuc/collection_element_identifiers/collection_element_identifiers/0.0.2`

1. **本地文件系统**（如果配置了 `local_tool_dir`）
   - 搜索匹配的 XML 文件
   - 如果找到多个版本，使用最新的

2. **GitHub**（如果本地未找到）
   - 尝试从 tools-iuc、tools-galaxyp 等标准仓库下载

3. **静态映射**（如果前两者都失败）
   - 使用 `tool_containers.yaml` 中的容器配置
   - 但没有工具 XML，命令生成会失败

## 示例：完整的本地工具配置

### 1. 找到你的 Galaxy toolshed 目录

```bash
# 在 Galaxy 安装目录下
ls -la database/shed_tools/
# 或
ls -la shed_tools/
```

### 2. 创建配置文件

`config/local_galaxy_config.yaml`:

```yaml
# 本地工具目录
local_tool_dir: /Users/you/galaxy/database/shed_tools

# 工具容器映射（用于没有 XML 的工具）
tool_registry:
  static_mappings_file: tool_containers.yaml

# AWS 配置
aws:
  enabled: true
  region: us-west-2
  batch:
    job_queue: galaxy-cloud-queue
  s3:
    bucket: galaxy-cloud-data-1760241377
```

### 3. 运行 workflow

```bash
export AWS_PROFILE=AdministratorAccess-399683337364

python examples/run_any_galaxy_workflow.py \
  /path/to/workflow.ga \
  --input 0:test_data/input \
  --provider aws \
  --config config/local_galaxy_config.yaml \
  --staging s3://mybucket/staging \
  --output s3://mybucket/output
```

## Docker 化的 Toolshed（场景 2）

如果你的工具已经封装成 Docker 镜像：

### 选项 A：工具 XML + 自定义容器镜像

1. **保持本地工具 XML**（用于命令生成）
2. **在 `tool_containers.yaml` 中指定自定义镜像**

```yaml
# tool_containers.yaml
tools:
  "toolshed.g2.bx.psu.edu/repos/iuc/collection_element_identifiers/collection_element_identifiers/0.0.2":
    image: "your-registry/galaxy-tools"
    tag: "collection_element_identifiers-0.0.2"
    registry: "quay.io"
```

配置：

```yaml
local_tool_dir: /path/to/local/shed_tools  # 用于读取 XML
tool_registry:
  static_mappings_file: tool_containers.yaml  # 用于容器镜像
```

**工作流程**：
1. 从本地读取工具 XML → 解析命令模板
2. 从 tool_containers.yaml 读取容器镜像
3. 在自定义容器中执行生成的命令

### 选项 B：完全自定义的 Docker 镜像（包含所有工具）

如果你有一个包含所有工具的 Docker 镜像：

```yaml
# tool_containers.yaml
tools:
  # 所有工具使用同一个镜像
  "toolshed.g2.bx.psu.edu/repos/iuc/collection_element_identifiers/collection_element_identifiers/0.0.2":
    image: "your-registry/galaxy-all-tools"
    tag: "v1.0"

  "toolshed.g2.bx.psu.edu/repos/q2d2/qiime2_core__tools__import/qiime2_core__tools__import/2023.5.0":
    image: "your-registry/galaxy-all-tools"
    tag: "v1.0"
```

**限制**：仍然需要工具 XML 来生成命令。可以：
1. 在 Docker 镜像中包含工具 XML
2. 挂载本地工具目录到容器
3. 使用 Galaxy 集成模式（galaxy_job_runner.py）

## 验证配置

测试工具 XML 是否能正确加载：

```python
from galaxy_cloud.galaxy_workflow.tool_executor import GalaxyToolExecutor

# 创建执行器
executor = GalaxyToolExecutor(local_tool_dir="/path/to/shed_tools")

# 测试加载工具 XML
tool_id = "toolshed.g2.bx.psu.edu/repos/iuc/collection_element_identifiers/collection_element_identifiers/0.0.2"
xml_content = await executor.get_tool_xml(tool_id)

if xml_content:
    print("✓ Tool XML loaded successfully from local filesystem")
    print(f"  Length: {len(xml_content)} characters")
else:
    print("✗ Failed to load tool XML")
```

## 常见问题

### Q: 如何知道我的 Galaxy toolshed 在哪里？

A: 检查 Galaxy 的 `galaxy.yml` 配置文件：

```bash
grep tool_dependency_dir galaxy.yml
grep shed_tool_data_path galaxy.yml
```

或查看 Galaxy 安装目录下的标准位置：
- `database/shed_tools/`
- `shed_tools/`

### Q: 工具版本不匹配怎么办？

A: 系统会使用找到的最新版本。如果需要特定版本：
1. 确保该版本的 XML 存在
2. 或修改 workflow JSON 中的工具版本

### Q: Docker 镜像中的工具能直接执行吗？

A: **需要工具 XML**。即使工具在 Docker 镜像中，我们也需要 XML 来：
1. 解析工具的输入/输出
2. 生成正确的命令行
3. 处理 Cheetah 模板

**最佳实践**：
- Docker 镜像包含工具可执行文件
- 本地或镜像中保留工具 XML
- 使用本配置读取 XML，使用容器执行命令

### Q: 离线环境如何使用？

A: 完全支持！只要：
1. 本地有完整的 toolshed（包含所有需要的工具 XML）
2. 容器镜像已经推送到私有 registry
3. 配置 `local_tool_dir` 和 `tool_containers.yaml`

## 对比：三种模式的 Toolshed 使用

| 特性 | GitHub 模式 | 本地 Toolshed 模式 | Docker 模式 |
|------|------------|-------------------|------------|
| **工具 XML 来源** | GitHub | 本地文件系统 | 本地/镜像内 |
| **容器镜像** | 手动配置 | 手动配置 | 预构建 |
| **网络要求** | 需要 | 不需要 | 不需要 |
| **自定义工具** | ❌ | ✅ | ✅ |
| **Galaxy 版本匹配** | 可能不匹配 | 完全匹配 | 完全匹配 |
| **配置复杂度** | 简单 | 中等 | 中等 |
| **启动速度** | 慢（下载） | 快 | 最快 |

## 总结

**使用本地 Toolshed 的好处**：

1. ✅ **完全离线**：不需要网络访问 GitHub
2. ✅ **版本一致**：使用与你的 Galaxy 实例完全相同的工具版本
3. ✅ **支持自定义工具**：包括私有和修改过的工具
4. ✅ **更快的启动**：不需要下载 XML
5. ✅ **与 Docker 结合**：XML 解析 + 容器执行

**配置只需三步**：

```python
config = {
    'local_tool_dir': '/path/to/galaxy/shed_tools',  # 1. 指定工具目录
    'tool_registry': {
        'static_mappings_file': 'tool_containers.yaml'  # 2. 容器映射
    },
    'aws': { ... }  # 3. 云提供商配置
}
```

**支持的场景**：

✅ 本地 Galaxy toolshed
✅ 自定义工具目录
✅ Docker 镜像 + 本地 XML
✅ 离线环境
✅ 企业内网部署

---

**创建时间**: 2025-10-17
**版本**: 1.0
