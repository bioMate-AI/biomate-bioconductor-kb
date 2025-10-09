# Claude API 配置指南

## 🚀 快速配置Claude作为Galaxy AI助手

### 1. 获取Claude API密钥

由于您已经购买了Claude Code，您可以：

**选项A：使用Claude Code的API密钥**
1. 在Claude Code中查看您的API设置
2. 复制您的API密钥（通常以 `sk-ant-` 开头）

**选项B：从Anthropic Console获取**
1. 访问 [Anthropic Console](https://console.anthropic.com/)
2. 登录您的账户
3. 在API Keys页面生成新的API密钥

### 2. 配置Galaxy

**方法1：修改主配置文件**

编辑 `config/galaxy.yml`:

```yaml
galaxy:
  # AI Assistant Configuration - CLAUDE ENABLED!
  enable_ai_assistant: true
  ai_llm_provider: "anthropic"
  ai_llm_model: "claude-3-5-sonnet-20241022"
  ai_llm_api_key: "sk-ant-your-real-api-key-here"  # 替换为您的真实密钥
```

**方法2：使用Claude专用模板**

复制Claude配置模板：
```bash
cp config/galaxy_claude_example.yml config/galaxy.yml
```

然后编辑 `config/galaxy.yml` 中的API密钥。

**方法3：环境变量**

设置环境变量：
```bash
export GALAXY_AI_API_KEY="sk-ant-your-real-api-key-here"
```

### 3. 选择Claude模型

推荐的Claude模型选择：

```yaml
# 最强大且最新 (推荐)
ai_llm_model: "claude-3-5-sonnet-20241022"

# 最快速
ai_llm_model: "claude-3-5-haiku-20241022"

# 最智能但较慢
ai_llm_model: "claude-3-opus-20240229"

# 平衡性能和成本
ai_llm_model: "claude-3-sonnet-20240229"
```

### 4. 高级配置选项

```yaml
galaxy:
  # 基本Claude配置
  enable_ai_assistant: true
  ai_llm_provider: "anthropic"
  ai_llm_model: "claude-3-5-sonnet-20241022"
  ai_llm_api_key: "your-api-key"
  
  # 高级AI参数调优
  ai_max_tools_per_task: 5              # 每个任务推荐的最大工具数
  ai_similarity_threshold: 0.7          # 工具匹配相似度阈值
  ai_enable_tool_caching: true          # 启用工具推荐缓存
  ai_max_workflow_steps: 20             # 生成工作流的最大步骤数
  ai_enable_parallel_execution: true    # 启用并行执行优化
  ai_auto_parameter_inference: true     # 启用自动参数推断
  ai_intent_confidence_threshold: 0.8   # 意图分类置信度阈值
  ai_max_decomposition_depth: 3         # 任务分解最大深度
```

### 5. 测试配置

运行测试脚本验证Claude API集成：

```bash
# 测试Claude API连接
.venv/bin/python test_claude_api.py

# 测试完整AI组件集成
.venv/bin/python test_ai_api_direct.py
```

### 6. 启动Galaxy

```bash
# 使用AI助手启动脚本
sh start_galaxy_with_ai.sh

# 或使用标准启动方法
./run.sh
```

### 7. 使用AI助手

1. 在Galaxy界面右下角寻找悬浮的AI助手按钮 🤖
2. 点击打开AI助手面板
3. 尝试自然语言请求，例如：
   - "我想分析RNA-seq数据进行差异表达分析"
   - "帮我设计一个基因组变异检测的工作流"
   - "比较两个转录组数据集"

### 8. 故障排除

**常见问题：**

1. **API密钥错误**
   - 确保密钥以 `sk-ant-` 开头
   - 检查密钥是否有效且未过期

2. **配置未生效**
   - 重启Galaxy服务
   - 检查配置文件YAML语法

3. **网络连接问题**
   - 确保能访问 `https://api.anthropic.com`
   - 检查防火墙设置

4. **前端组件不显示**
   - 刷新浏览器页面 (Ctrl+F5)
   - 检查浏览器控制台错误信息

### 9. 性能优化建议

**模型选择建议：**
- **研究用途**：claude-3-5-sonnet-20241022 (最佳平衡)
- **快速原型**：claude-3-5-haiku-20241022 (最快)
- **复杂分析**：claude-3-opus-20240229 (最强但慢)

**参数调优：**
```yaml
# 对于大型工作流
ai_max_workflow_steps: 30

# 对于高精度要求
ai_intent_confidence_threshold: 0.9
ai_similarity_threshold: 0.8

# 对于快速响应
ai_max_tools_per_task: 3
ai_max_decomposition_depth: 2
```

### 10. Claude特有优势

使用Claude作为AI助手的优势：
- 🧠 **更强理解能力**: 对复杂生物信息学概念理解更深
- 📚 **丰富知识**: 对最新研究方法和工具了解更全面  
- 🔍 **细致分析**: 能提供更详细的工作流解释和建议
- 🛡️ **安全可靠**: Anthropic在AI安全方面领先
- ⚡ **高效处理**: Claude 3.5在处理科学问题上表现优异

## 🎉 配置完成！

配置完成后，您就拥有了一个由Claude驱动的智能生物信息学工作流助手！🚀