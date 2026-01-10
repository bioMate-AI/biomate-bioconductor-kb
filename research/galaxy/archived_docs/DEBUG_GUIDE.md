# Galaxy AI Assistant 调试指南

这个指南说明了如何在VSCode中调试Galaxy AI助手功能的新增特性。

## 🛠️ 调试环境设置

### 1. VSCode扩展安装
确保安装了以下VSCode扩展：
- Python
- Python Debugger
- Pylance

### 2. 工作区配置
项目已经包含了以下配置文件：
- `.vscode/launch.json` - 调试配置
- `.vscode/tasks.json` - 任务配置  
- `.vscode/settings.json` - 工作区设置
- `.env` - 环境变量

## 🎯 调试方法

### 方法1: 单元测试调试（推荐）

1. **打开调试脚本**：`test_ai_debug.py`
2. **设置断点**：在要调试的函数中点击行号左侧设置断点
3. **启动调试**：
   - 按 `F5` 或选择"Debug AI Assistant"配置
   - 或者按 `Ctrl+Shift+P` → "Tasks: Run Task" → "Debug AI Assistant Components"

**调试重点**：
```python
def test_rag_workflow_generation():
    # 在这里设置断点
    result = rag_generator.generate_workflow(user_request)
    # 检查result的内容
```

### 方法2: 独立API服务器调试

1. **启动调试API服务器**：
   ```bash
   python debug_api_server.py
   ```
   或使用VSCode任务："Start Debug API Server"

2. **访问API文档**：http://localhost:8081/docs

3. **测试端点**：
   ```bash
   curl -X POST "http://localhost:8081/debug/rag_generation" \
   -H "Content-Type: application/json" \
   -d '{"request_text": "Create RNA-seq workflow", "context": {}}'
   ```

4. **在VSCode中调试**：选择"Debug AI API Endpoint"配置

### 方法3: RAG组件深度调试

1. **运行组件调试脚本**：`debug_rag_components.py`
2. **逐个调试各组件**：
   - 爬虫数据加载
   - 工作流相似度计算
   - LLM集成
   - 工作流导出

## 🔍 关键调试点

### 1. RAG工作流生成器初始化
```python
# 在这里设置断点查看初始化过程
rag_generator = RAGWorkflowGenerator(DEFAULT_AI_CONFIG, crawler_data_path)
```

### 2. 工作流相似度搜索
```python
# 调试相似度计算
results = recommender.get_workflow_recommendations(query, max_recommendations=3)
```

### 3. LLM调用
```python
# 调试LLM集成
response = llm_client.generate_text(test_prompt, max_tokens=150)
```

### 4. 工作流导出
```python
# 检查workflow_input_标记是否正确处理
galaxy_format = generator.export_to_galaxy_format(test_workflow)
```

## 🎨 VSCode调试技巧

### 1. 设置条件断点
- 右键点击断点 → 编辑断点
- 添加条件：`len(results) > 0`

### 2. 监视变量
- 在"监视"面板添加变量名
- 实时查看变量值变化

### 3. 调试控制台
- 在断点暂停时，使用调试控制台执行代码
- 例如：`print(workflow_data.workflows[0])`

### 4. 调用堆栈查看
- 查看函数调用链
- 定位问题源头

## 🚀 快速开始

### 开始调试新功能：

1. **克隆或确认文件存在**：
   - `test_ai_debug.py`
   - `debug_api_server.py` 
   - `debug_rag_components.py`

2. **在VSCode中打开Galaxy项目**

3. **选择Python解释器**：`.venv/bin/python`

4. **运行基础测试**：
   ```bash
   python test_ai_debug.py
   ```

5. **设置断点开始调试**：
   - 在关键函数中设置断点
   - 按F5启动调试
   - 使用调试控制台查看变量

## 📝 常见调试场景

### 场景1: 新增AI功能不工作
1. 在`test_ai_assistant_initialization()`设置断点
2. 检查AI助手是否正确初始化
3. 确认RAG生成器是否可用

### 场景2: 工作流生成错误
1. 在`test_rag_workflow_generation()`设置断点
2. 检查用户请求处理
3. 查看LLM响应内容

### 场景3: API端点问题
1. 启动调试API服务器
2. 在相应的端点函数设置断点
3. 发送测试请求触发断点

## 🔧 自定义调试

### 添加新的调试脚本：
1. 创建新的Python文件
2. 添加到`.vscode/launch.json`中的配置
3. 设置合适的环境变量和路径

### 调试Galaxy集成：
1. 使用远程调试连接到运行中的Galaxy实例
2. 在AI助手代码中设置断点
3. 通过Galaxy UI触发功能

## ⚡ 性能调试

### 使用性能分析器：
```python
import cProfile
import pstats

pr = cProfile.Profile()
pr.enable()
# 你的代码
pr.disable()
stats = pstats.Stats(pr)
stats.sort_stats('cumulative').print_stats(10)
```

## 📊 日志调试

在代码中添加详细日志：
```python
import logging
logging.basicConfig(level=logging.DEBUG)
log = logging.getLogger(__name__)

log.debug(f"Processing request: {request.request_text}")
```

这样你就可以独立调试Galaxy AI助手的任何新功能，而不需要启动整个Galaxy服务器！