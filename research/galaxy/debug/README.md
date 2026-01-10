# Debug Scripts

这个目录包含开发过程中的调试脚本，用于排查和解决特定问题。

## 📁 文件说明

### AI工作流相关调试
- `debug_rag_components.py` - RAG组件深度调试
- `debug_workflow_*.py` - 工作流生成和处理调试  
- `debug_step_id_*.py` - 工作流步骤ID问题调试

### API相关调试
- `debug_api_server.py` - 独立API调试服务器
- `debug_actual_api.py` - 实际API端点调试
- `debug_authenticated_save.py` - 认证保存功能调试

### 数据处理调试
- `debug_similarity.py` - 相似度计算调试
- `debug_empty_results.py` - 空结果问题调试
- `debug_frontend_logic.py` - 前端逻辑问题调试

## 🚀 使用方法

```bash
# 运行RAG组件调试
python debug/debug_rag_components.py

# 启动API调试服务器
python debug/debug_api_server.py
# 然后访问 http://localhost:8081/docs

# 调试工作流生成
python debug/debug_workflow_steps.py
```

## ⚠️ 注意事项

1. **临时性质**: 这些脚本主要用于开发调试，不应提交到生产分支
2. **环境要求**: 运行前确保设置了 `PYTHONPATH=lib`
3. **清理**: 问题解决后，及时清理不再需要的调试脚本
4. **安全**: 不要在调试脚本中硬编码敏感信息

## 🛠️ 开发建议

创建新的调试脚本时：
- 使用描述性的文件名: `debug_{模块}_{问题}.py`
- 添加详细的注释说明调试目的
- 包含必要的错误处理
- 设置适当的日志级别便于分析