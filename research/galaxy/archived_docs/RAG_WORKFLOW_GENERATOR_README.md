# RAG-Based Workflow Generator for Galaxy AI Assistant

## 概述

这是一个基于检索增强生成（RAG）的Galaxy workflow生成系统，它使用真实的Galaxy workflow数据来生成更准确和实用的workflow建议。与传统的基于规则或模板的方法不同，RAG方法能够：

- 基于真实的Galaxy社区workflow数据进行推荐
- 找到与用户需求最相似的已有workflow
- 根据相似度自适应生成workflow
- 提供更高的准确性和实用性

## 系统架构

```
用户请求
    ↓
意图解析 → 任务分解 → 工具推荐
    ↓
RAG Workflow Generator (优先)
    ↓
1. 查找相似workflows (爬虫数据)
2. 计算相似度得分
3. 选择最佳模板
4. 自适应生成workflow
    ↓
Enhanced Workflow Generator (备选)
    ↓
生成的Workflow
```

## 核心组件

### 1. RAGWorkflowGenerator
- 主要的RAG-based workflow生成器
- 管理workflow embeddings和相似度搜索
- 基于模板自适应生成新workflow

### 2. CrawledWorkflowData
- 管理从爬虫收集的workflow数据
- 提供搜索和过滤功能
- 自动分类workflow

### 3. WorkflowEmbedding
- Workflow的向量表示
- 支持相似度计算
- 缓存机制提升性能

## 数据格式要求

爬虫数据应该是JSON格式，包含workflow列表：

```json
{
  "workflows": [
    {
      "id": "workflow_id",
      "name": "Workflow Name", 
      "annotations": ["Description text"],
      "tags": ["tag1", "tag2"],
      "number_of_steps": 10,
      "owner": "username",
      "steps": {...}  // optional detailed steps
    }
  ]
}
```

## 安装和设置

### 1. 使用设置脚本 (推荐)

```bash
# 在Galaxy目录下运行
python setup_rag_workflow_generator.py --crawler-data /path/to/crawler/data

# 验证数据格式
python setup_rag_workflow_generator.py --crawler-data /path/to/crawler/data --verify-only
```

### 2. 手动设置

1. 将爬虫数据放在合适的目录
2. 修改AI Assistant初始化代码：

```python
from galaxy.ai.ai_assistant import AIAssistant

# 创建RAG-enabled AI Assistant
assistant = AIAssistant(
    config=ai_config,
    galaxy_app=app,
    crawler_data_path="/path/to/crawler/data"
)
```

## 使用方法

### 基本使用

```python
from galaxy.ai.rag_assistant_init import create_rag_enabled_assistant
from galaxy.ai.types import UserRequest

# 初始化
assistant = create_rag_enabled_assistant(galaxy_app=app)

# 创建请求
request = UserRequest(request_text="I need RNA-seq differential expression analysis")

# 生成workflow
response = assistant.process_request(request)

if response.workflow_template:
    print(f"Generated: {response.workflow_template.name}")
    print(f"Steps: {len(response.workflow_template.steps)}")
    print(f"Confidence: {response.confidence:.1%}")
```

### 获取相似workflow建议

```python
# 直接使用RAG generator
if assistant.rag_workflow_generator:
    recommendations = assistant.rag_workflow_generator.get_workflow_recommendations(
        request, limit=5
    )
    
    for rec in recommendations:
        print(f"- {rec['name']} (similarity: {rec['similarity_score']:.3f})")
```

### 系统状态检查

```python
# 获取RAG系统统计
if assistant.rag_workflow_generator:
    stats = assistant.rag_workflow_generator.get_stats()
    print(f"Loaded workflows: {stats['total_workflows']}")
    print(f"Categories: {stats['categories']}")
```

## 与现有系统的集成

RAG系统设计为与现有Galaxy AI Assistant无缝集成：

1. **优先级系统**: RAG generator有更高优先级，失败时自动回退到enhanced generator
2. **兼容性**: 保持现有API接口不变
3. **渐进式部署**: 可以逐步启用RAG功能

## 特性与优势

### 🎯 基于真实数据
- 使用Galaxy社区的真实workflow数据
- 反映实际使用模式和最佳实践

### 🔍 智能相似度匹配
- 基于workflow名称、描述、标签进行匹配
- 考虑步骤数量和复杂度

### 🚀 自适应生成
- 根据用户请求调整workflow名称和描述
- 保持原有workflow的核心结构

### 📊 可观测性
- 提供详细的相似度得分
- 展示基于的模板数量
- 系统状态和统计信息

### ⚡ 性能优化
- Embedding缓存机制
- 增量索引更新
- 并行相似度计算

## 配置选项

在`rag_config.json`中可以调整以下参数：

```json
{
  "ai_assistant": {
    "enable_rag_workflow_generator": true,
    "crawler_data_path": "/path/to/data",
    "rag_settings": {
      "max_similar_workflows": 5,
      "similarity_threshold": 0.1,
      "enable_workflow_adaptation": true,
      "cache_embeddings": true
    }
  }
}
```

## 数据更新

当有新的爬虫数据时：

1. **自动检测**: 系统会检测数据文件的变化
2. **增量更新**: 只处理新增或修改的workflow
3. **重建索引**: 必要时重建embedding索引

```bash
# 手动更新数据
python -c "
from galaxy.ai.rag_assistant_init import create_rag_enabled_assistant
assistant = create_rag_enabled_assistant()
if assistant.rag_workflow_generator:
    assistant.rag_workflow_generator.workflow_data.load_crawler_data()
"
```

## 故障排除

### 常见问题

1. **数据格式错误**
   ```bash
   # 验证数据格式
   python setup_rag_workflow_generator.py --crawler-data /path/to/data --verify-only
   ```

2. **内存使用过高**
   - 减少max_similar_workflows参数
   - 启用embedding缓存
   - 过滤掉过小或过大的workflow

3. **相似度得分偏低**
   - 降低similarity_threshold
   - 检查workflow描述和标签质量
   - 考虑扩展关键词映射

### 日志调试

```python
import logging
logging.getLogger('galaxy.ai.rag_workflow_generator').setLevel(logging.DEBUG)
```

## 性能指标

| 指标 | 典型值 | 说明 |
|------|--------|------|
| 数据加载时间 | < 30秒 | 10,000 workflows |
| Embedding生成 | < 5分钟 | 10,000 workflows |
| 查询响应时间 | < 100ms | 相似度搜索 |
| 内存使用 | < 500MB | 包含embedding |

## 扩展开发

### 自定义相似度算法

```python
class CustomRAGWorkflowGenerator(RAGWorkflowGenerator):
    def _simple_text_embedding(self, text: str) -> np.ndarray:
        # 实现自定义embedding算法
        # 可以集成sentence-transformers, OpenAI等
        pass
```

### 添加新的分类规则

```python
def _auto_categorize(self, workflow: Dict) -> List[str]:
    # 扩展自动分类逻辑
    categories = super()._auto_categorize(workflow)
    
    # 添加自定义分类
    if 'proteomics' in workflow_text:
        categories.append('proteomics')
    
    return categories
```

## 未来改进

- [ ] 集成更强大的embedding模型 (sentence-transformers)
- [ ] 支持workflow步骤级别的相似度匹配
- [ ] 添加用户反馈学习机制
- [ ] 工具依赖关系分析
- [ ] 执行历史和成功率统计
- [ ] 多语言支持

## 许可证和贡献

本项目遵循Galaxy项目的开源许可证。欢迎贡献代码、报告问题或提出改进建议。

---

更多信息请参考：
- Galaxy AI Assistant 文档
- workflow爬虫项目文档
- Galaxy开发者指南