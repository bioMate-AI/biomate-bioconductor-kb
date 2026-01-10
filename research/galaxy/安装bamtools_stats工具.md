# 安装缺失的工具: bamtools_stats

---

## ❌ 问题

Workflow报错：
```
Workflow cannot be executed. Please resolve the following issue:
Following tools missing: toolshed.g2.bx.psu.edu/repos/devteam/bamtools_stats/bamtools_stats/2.5.2+galaxy1
```

---

## ✅ 解决方案：通过Galaxy Web界面安装

### 方式1: 搜索并安装（最简单）⭐

#### 步骤1: 访问Tool Shed管理页面

打开浏览器访问：
```
http://localhost:8080/admin/toolshed
```

或者：
1. 访问 http://localhost:8080
2. 顶部菜单 → **Admin**
3. 左侧菜单 → **Install and Uninstall** → **Search Tool Shed**

#### 步骤2: 搜索工具

1. 在搜索框输入：`bamtools_stats`
2. 按回车搜索

#### 步骤3: 选择正确的工具

找到以下工具：
- **Name**: bamtools_stats
- **Owner**: devteam
- **Description**: Generates statistics for BAM files

点击该工具。

#### 步骤4: 安装

1. 点击 **"Install to Galaxy"** 按钮
2. 在弹出的对话框中：
   - Tool Shed: `https://toolshed.g2.bx.psu.edu` (默认)
   - Select a tool panel section: 选择 **"SAM/BAM"** 或 **"Default"**
   - Install tool dependencies: ✅ 勾选
   - Install repository dependencies: ✅ 勾选
3. 点击 **"Install"**

#### 步骤5: 等待安装

1. 你会看到安装进度页面
2. 等待状态变为 **"Installed"** ✅
3. 通常需要 **5-10分钟**

---

### 方式2: 直接安装链接（更快）⭐⭐

访问以下URL直接安装：

```
http://localhost:8080/admin_toolshed/prepare_for_install?tool_shed_url=https%3A%2F%2Ftoolshed.g2.bx.psu.edu&repository_ids=9c09c09e3cab9ebb&changeset_revisions=77f51726f39b
```

然后点击 **"Install"** 按钮。

---

### 方式3: 监控已有的安装（检查是否正在安装中）

有可能工具正在安装中，但还没完成。检查方法：

1. 访问 http://localhost:8080/admin/toolshed
2. 点击 **"Monitor installing repositories"**
3. 查看是否有 `bamtools_stats` 正在安装

如果正在安装：
- 状态：**Installing dependencies** 或 **Installing**
- 等待完成即可

如果安装失败：
- 状态：**Error**
- 点击查看错误详情
- 可能需要重新安装

---

## ✅ 安装完成后

### 验证安装

1. 访问 http://localhost:8080/admin/toolshed
2. 点击 **"Installed repositories"**
3. 搜索 `bamtools`
4. 应该看到：
   - **bamtools_stats**
   - Status: **Installed** ✅

### 重新运行Workflow

1. 返回 Workflow 页面
2. 刷新页面（F5 或 Cmd+R）
3. 点击 **"Run"** 运行workflow
4. 错误应该消失了 ✅

---

## 🔍 如果仍然报错

### 问题1: 工具安装了但workflow还是报错

**原因**: Galaxy可能缓存了workflow状态

**解决**:
1. 完全退出浏览器
2. 重新打开浏览器
3. 访问 http://localhost:8080
4. 重新尝试运行workflow

或者：
1. 重新导入workflow
2. 删除旧的workflow
3. 导入 `real_complex_workflow.ga`
4. 使用新导入的workflow

### 问题2: 工具安装失败

**原因**: 网络问题或依赖问题

**解决**:
1. 检查Galaxy日志：`tail -50 galaxy_startup.log`
2. 查看具体错误信息
3. 尝试重新安装

### 问题3: 找不到工具

**检查其他已安装的bamtools工具**:

```bash
# 列出所有已安装的工具
curl -s http://localhost:8080/api/tool_shed_repositories \
  -H "x-api-key: $GALAXY_API_KEY" | \
  grep -i bamtools
```

---

## 📊 完整的工具列表

你的workflow需要这些工具：

| 工具 | Owner | 状态 |
|------|-------|------|
| FastQC | devteam | ✅ 已安装 |
| Trimmomatic | pjbriggs | ✅ 已安装 |
| Bowtie2 | devteam | ✅ 已安装 |
| **bamtools_stats** | **devteam** | ❌ **需要安装** |

---

## 🎯 快速安装步骤总结

```
1. 访问 http://localhost:8080/admin/toolshed
2. 搜索 "bamtools_stats"
3. 选择 devteam/bamtools_stats
4. 点击 "Install to Galaxy"
5. 等待安装完成（5-10分钟）
6. 刷新workflow页面
7. 运行workflow ✅
```

---

## ⚠️ 重要提示

### 为什么其他工具安装了但bamtools_stats没有？

之前的安装脚本中**没有包含bamtools_stats**！

检查之前的脚本：
```python
TOOLS = [
    {"name": "fastqc", ...},
    {"name": "trimmomatic", ...},
    {"name": "bowtie2", ...},
    # ❌ 缺少 bamtools_stats!
]
```

**现在补上这个工具即可。**

---

## 📝 下次避免这个问题

如果创建新的workflow，确保：

1. **先检查所有需要的工具**：
   ```bash
   # 从workflow文件中提取所有工具ID
   grep "tool_id" real_complex_workflow.ga
   ```

2. **安装所有工具**：
   - 列出所有唯一的工具ID
   - 逐个安装

3. **验证安装完成**：
   ```bash
   # 检查已安装的工具
   curl -s http://localhost:8080/api/tools \
     -H "x-api-key: $GALAXY_API_KEY"
   ```

---

## 🎊 安装完成后

安装bamtools_stats后，你就可以：

1. ✅ 运行完整的6步workflow
2. ✅ 测试云端执行
3. ✅ 验证所有作业在AWS Batch运行
4. ✅ 获得完整的分析结果

---

**现在就去安装吧！** 访问 http://localhost:8080/admin/toolshed 🚀
