# Galaxy AI Assistant 故障排除指南

## 🔧 问题诊断和解决方案

### ✅ 已修复的问题

经过诊断和修复，以下问题已解决：

1. **✅ RAG workflow生成器未被使用** 
   - 已配置API自动加载RAG系统
   - 配置文件已添加`ai_crawler_data_path`参数

2. **✅ AI assistant按钮功能失效**
   - 修复了前端按钮事件处理
   - 添加了workflow editor跳转功能

3. **✅ Workflow editor 404问题**
   - 优化了URL生成和跳转逻辑
   - 提供了备选访问路径

## 🧪 测试步骤

### 1. 测试LLM连接
```bash
python test_llm_connection.py
```

**期望输出**：
- ✅ LLM连接成功
- ✅ RAG系统已加载2241个workflows

### 2. 测试API功能
```bash
# 确保Galaxy服务器运行中
sh run.sh

# 在另一个终端测试API
python test_ai_assistant_api.py
```

**期望输出**：
- ✅ AI Assistant状态正常
- ✅ RAG-based workflow推荐工作正常
- ✅ 完整AI请求处理成功

### 3. 测试前端界面

1. **访问AI Assistant**
   - 打开Galaxy界面
   - 点击AI Assistant图标（机器人图标）
   - 确认面板正常打开

2. **测试基本对话**
   ```
   测试消息: "I want to perform RNA-seq differential expression analysis"
   ```
   
   **期望行为**：
   - AI正常响应
   - 显示推荐的workflow
   - 显示"Create Workflow"按钮

3. **测试Workflow创建**
   - 点击"Create Workflow"按钮
   - 确认显示成功消息
   - 确认显示"Open Workflow Editor"按钮
   - 点击按钮确认能正常跳转

## 🚀 验证RAG系统正常工作

### 检查点1: RAG数据加载
```python
python -c "
from galaxy.ai.rag_assistant_init import create_rag_enabled_assistant
assistant = create_rag_enabled_assistant()
if assistant.rag_workflow_generator:
    stats = assistant.rag_workflow_generator.get_stats()
    print(f'RAG系统状态: {stats}')
else:
    print('RAG系统未加载')
"
```

### 检查点2: 相似度搜索
在AI Assistant中测试以下请求，确认返回相关workflow：

```
1. "RNA-seq analysis"
   期望: 返回RNA测序相关workflows

2. "genome assembly" 
   期望: 返回基因组组装workflows

3. "variant calling"
   期望: 返回变异检测workflows
```

### 检查点3: API响应格式
测试API是否返回正确的RAG标识：
```bash
curl -X POST http://localhost:8080/api/ai_assistant/get_workflow_recommendations \
  -H "Content-Type: application/json" \
  -d '{"request_text": "RNA-seq analysis"}'
```

**期望响应**：
```json
{
  "method": "RAG-based (using crawled workflow data)",
  "recommendations": [...],
  "total_options": 3
}
```

## 🛠️ 常见问题解决

### 问题1: AI Assistant无响应
**症状**: 点击发送消息后无任何反应

**解决方案**:
1. 检查浏览器控制台错误
2. 确认Galaxy服务器运行正常
3. 检查API key配置

### 问题2: Workflow Editor 404
**症状**: 点击"Open Workflow Editor"显示404

**可能原因及解决**:
1. **Workflow未成功创建**
   ```bash
   # 检查Galaxy日志
   tail -f paster.log | grep -i workflow
   ```

2. **URL格式问题**
   - 尝试通过"Workflow → My Workflows"手动访问
   - 确认workflow ID正确编码

3. **权限问题**
   - 确认用户已登录
   - 检查workflow所有权

### 问题3: RAG系统未激活
**症状**: API返回"Template-based"而非"RAG-based"

**解决方案**:
1. **检查数据路径**
   ```yaml
   # config/galaxy.yml
   ai_crawler_data_path: "/Users/renyuankai/work/pywork/normalWork/galaxy_爬虫/galaxy_crawler/galaxy_workflows_crawler/data"
   ```

2. **检查数据文件**
   ```bash
   ls -la "/Users/renyuankai/work/pywork/normalWork/galaxy_爬虫/galaxy_crawler/galaxy_workflows_crawler/data"
   ```

3. **重启Galaxy服务器**
   ```bash
   # 停止服务器
   Ctrl+C
   
   # 重新启动
   sh run.sh
   ```

### 问题4: LLM连接失败
**症状**: "LLM连接失败"或API超时

**解决方案**:
1. **检查API Key**
   ```bash
   # 验证通义千问API Key
   curl -X POST https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions \
     -H "Authorization: Bearer sk-eaa5213d393d4ba98f855141763c6f1a" \
     -H "Content-Type: application/json" \
     -d '{"model":"qwen-plus","messages":[{"role":"user","content":"hello"}]}'
   ```

2. **检查网络连接**
   ```bash
   ping dashscope.aliyuncs.com
   ```

3. **尝试其他模型**
   ```yaml
   # 配置备选模型
   ai_llm_model: "qwen-turbo"  # 更快的模型
   ```

## 📋 配置检查清单

### Galaxy配置 (config/galaxy.yml)
- [ ] `enable_ai_assistant: true`
- [ ] `ai_llm_provider: "qwen"`  
- [ ] `ai_llm_model: "qwen-plus"`
- [ ] `ai_llm_api_key: "sk-xxx"` (已设置有效API key)
- [ ] `ai_llm_base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1"`
- [ ] `ai_crawler_data_path: "/path/to/crawler/data"` (路径正确)

### 数据文件检查
- [ ] 爬虫数据文件存在且可读
- [ ] JSON格式正确
- [ ] 包含workflows数组
- [ ] Workflow对象包含必需字段 (id, name)

### 服务状态检查  
- [ ] Galaxy服务器运行中 (http://localhost:8080)
- [ ] LLM API可访问
- [ ] 网络连接正常
- [ ] API配额充足

## 🎯 性能优化建议

### 1. LLM响应速度优化
```yaml
# 使用更快的模型
ai_llm_model: "qwen-turbo"

# 减少最大tokens
ai_max_tokens: 500
```

### 2. RAG搜索优化
```python
# 调整相似度阈值
ai_similarity_threshold: 0.5  # 降低阈值获得更多结果

# 增加推荐数量
ai_max_similar_workflows: 10
```

### 3. 缓存配置
```yaml
# 启用缓存
ai_enable_tool_caching: true
ai_enable_workflow_caching: true
```

## 📞 获取帮助

如果问题仍未解决：

1. **查看详细日志**
   ```bash
   tail -f paster.log | grep -i ai
   ```

2. **检查浏览器控制台**
   - F12 → Console → 查看JavaScript错误

3. **运行完整诊断**
   ```bash
   python test_llm_connection.py
   python test_ai_assistant_api.py
   ```

4. **提供以下信息**
   - Galaxy版本
   - 配置文件内容 (隐藏API key)
   - 错误日志
   - 浏览器控制台错误

## 🔄 重启流程

如果需要完全重启AI Assistant：

1. **停止Galaxy**
   ```bash
   Ctrl+C
   ```

2. **清除缓存** (可选)
   ```bash
   rm -f workflow_embeddings.pkl
   rm -rf database/tmp/*
   ```

3. **重启Galaxy**
   ```bash
   sh run.sh
   ```

4. **验证功能**
   ```bash
   python test_llm_connection.py
   python test_ai_assistant_api.py
   ```

---

## ⚡ 快速验证命令

```bash
# 一键验证所有功能
echo "🔍 检查配置..."
grep -E "enable_ai_assistant|ai_llm|ai_crawler" config/galaxy.yml

echo "🧪 测试LLM连接..."
python test_llm_connection.py

echo "🌐 测试API..."
python test_ai_assistant_api.py

echo "✅ 完成！请检查上方输出确认所有测试通过"
```

以上指南涵盖了Galaxy AI Assistant的完整故障排除流程。如遇到其他问题，请参照相应章节进行诊断。