# 🤖 Galaxy AI助手 - 多模型配置指南

## 🌟 支持的AI模型提供商

Galaxy AI助手现已支持8个主流AI提供商，包括国内外优秀的大语言模型：

| 提供商 | 推荐模型 | 优势 | 获取地址 |
|--------|----------|------|----------|
| 🇨🇳 **通义千问** | qwen-max | 中文理解优秀，阿里云技术 | [DashScope控制台](https://dashscope.console.aliyun.com/) |
| 🇨🇳 **智谱AI** | glm-4 | 中英文双语强，清华系技术 | [智谱AI开放平台](https://open.bigmodel.cn/) |
| 🇨🇳 **月之暗面** | moonshot-v1-128k | 长文本处理强，上下文理解好 | [Kimi开放平台](https://platform.moonshot.cn/) |
| 🇨🇳 **深度求索** | deepseek-chat | 推理能力强，多任务处理 | [DeepSeek平台](https://platform.deepseek.com/) |
| 🇨🇳 **百川智能** | baichuan2-turbo | 中文NLP技术领先 | [百川智能平台](https://platform.baichuan-ai.com/) |
| 🇺🇸 **OpenAI** | gpt-4o | 国际领先，功能全面 | [OpenAI平台](https://platform.openai.com/) |
| 🇺🇸 **Anthropic** | claude-3-5-sonnet | 安全可靠，理解能力强 | [Anthropic控制台](https://console.anthropic.com/) |
| 🖥️ **本地模型** | llama3.1 | 数据安全，无网络依赖 | [Ollama](https://ollama.ai/) |

## 🚀 快速配置

### 步骤1：选择AI提供商

**推荐选择通义千问** (性价比最高，中文支持最好):

```yaml
# config/galaxy.yml
galaxy:
  enable_ai_assistant: true
  ai_llm_provider: "qwen"
  ai_llm_model: "qwen-max"
  ai_llm_api_key: "sk-your-qwen-api-key"
```

### 步骤2：获取API密钥

#### 通义千问 (推荐) 🌟
1. 访问 [DashScope控制台](https://dashscope.console.aliyun.com/)
2. 登录阿里云账号
3. 开通DashScope服务
4. 在"API-KEY管理"中创建新密钥

#### 智谱AI GLM
1. 访问 [智谱AI开放平台](https://open.bigmodel.cn/)  
2. 注册并实名认证
3. 在API Keys页面生成密钥

#### 月之暗面 Kimi
1. 访问 [Kimi开放平台](https://platform.moonshot.cn/)
2. 注册账号并完成认证
3. 获取API Key

### 步骤3：配置Galaxy

**方法A：修改现有配置**
```bash
vim config/galaxy.yml
```

**方法B：使用模板**
```bash
# 使用通义千问模板
cp config/galaxy_qwen_example.yml config/galaxy.yml
```

## 📋 详细配置选项

### 通义千问配置
```yaml
galaxy:
  enable_ai_assistant: true
  ai_llm_provider: "qwen"
  ai_llm_model: "qwen-max"        # 或 qwen-plus, qwen-turbo
  ai_llm_api_key: "sk-your-qwen-api-key"
```

### 智谱AI配置
```yaml
galaxy:
  enable_ai_assistant: true
  ai_llm_provider: "zhipu"
  ai_llm_model: "glm-4"           # 或 glm-4-plus, glm-4-air
  ai_llm_api_key: "your-zhipu-api-key"
```

### 月之暗面配置
```yaml
galaxy:
  enable_ai_assistant: true
  ai_llm_provider: "moonshot"
  ai_llm_model: "moonshot-v1-128k"  # 或 moonshot-v1-32k
  ai_llm_api_key: "sk-your-moonshot-api-key"
```

### DeepSeek配置
```yaml
galaxy:
  enable_ai_assistant: true
  ai_llm_provider: "deepseek"
  ai_llm_model: "deepseek-chat"   # 或 deepseek-coder
  ai_llm_api_key: "sk-your-deepseek-api-key"
```

### OpenAI配置
```yaml
galaxy:
  enable_ai_assistant: true
  ai_llm_provider: "openai"
  ai_llm_model: "gpt-4o"          # 或 gpt-4, gpt-3.5-turbo
  ai_llm_api_key: "sk-your-openai-api-key"
```

### 本地模型配置
```yaml
galaxy:
  enable_ai_assistant: true
  ai_llm_provider: "local"
  ai_llm_model: "llama3.1"
  ai_llm_base_url: "http://localhost:11434/v1"  # Ollama默认地址
  # 本地模型通常不需要API密钥
```

## 🔧 高级配置

### 性能调优
```yaml
galaxy:
  # AI基础配置
  enable_ai_assistant: true
  ai_llm_provider: "qwen"
  ai_llm_model: "qwen-max"
  ai_llm_api_key: "your-api-key"
  
  # 高级参数
  ai_max_tools_per_task: 5              # 工具推荐数量
  ai_similarity_threshold: 0.7          # 相似度阈值
  ai_enable_tool_caching: true          # 缓存优化
  ai_max_workflow_steps: 20             # 工作流最大步数
  ai_enable_parallel_execution: true    # 并行执行
  ai_auto_parameter_inference: true     # 自动参数推断
  ai_intent_confidence_threshold: 0.8   # 意图置信度
  ai_max_decomposition_depth: 3         # 任务分解深度
```

### 自定义端点
```yaml
galaxy:
  enable_ai_assistant: true
  ai_llm_provider: "qwen"
  ai_llm_model: "qwen-max"
  ai_llm_api_key: "your-api-key"
  ai_llm_base_url: "https://your-custom-endpoint.com/v1"  # 自定义地址
```

## 🧪 测试配置

### 测试所有支持的提供商
```bash
.venv/bin/python test_multi_llm.py
```

### 测试特定提供商连接
```bash
# 测试通义千问
.venv/bin/python test_multi_llm.py qwen sk-your-qwen-api-key

# 测试智谱AI
.venv/bin/python test_multi_llm.py zhipu your-zhipu-api-key
```

### 测试完整AI组件
```bash
.venv/bin/python test_ai_api_direct.py
```

## 🚀 启动Galaxy

```bash
# 使用AI助手启动
sh start_galaxy_with_ai.sh

# 或使用标准方法
./run.sh
```

## 💡 模型选择建议

### 根据使用场景选择

**🎯 日常科研使用 (推荐)**
- **通义千问 qwen-max**: 中文理解好，性价比高
- **智谱AI glm-4**: 双语能力强，技术先进

**⚡ 快速响应需求**
- **通义千问 qwen-turbo**: 响应速度快
- **智谱AI glm-4-flash**: 闪电响应
- **Claude haiku**: 国际选择

**📚 长文本处理**
- **月之暗面 moonshot-v1-128k**: 128K上下文
- **通义千问 qwen-long**: 长文本专用

**🔬 复杂分析任务**
- **通义千问 qwen-max**: 最强版本
- **智谱AI glm-4-plus**: 增强版本
- **Claude opus**: 国际最强

**🏠 本地部署**
- **Llama 3.1**: 开源强大
- **通义千问 qwen2**: 本地版本
- **ChatGLM3**: 清华开源

### 成本对比

| 提供商 | 成本等级 | 特点 |
|--------|----------|------|
| 通义千问 | 💰 低 | 性价比最高，中文优秀 |
| 智谱AI | 💰💰 中低 | 技术先进，价格合理 |
| 月之暗面 | 💰💰 中 | 长文本处理强 |
| DeepSeek | 💰 低 | 推理能力强，价格便宜 |
| 百川智能 | 💰💰 中 | 中等价位，功能全面 |
| OpenAI | 💰💰💰 高 | 功能最强，价格较高 |
| Claude | 💰💰💰 高 | 安全可靠，价格较高 |
| 本地模型 | 🆓 免费 | 一次性部署，长期免费 |

## 🔍 故障排除

### 常见问题

**1. API密钥错误**
```
❌ API error: 401 Unauthorized
```
- 检查API密钥格式是否正确
- 确认密钥未过期且有足够余额
- 验证提供商设置是否匹配

**2. 网络连接问题**
```
❌ Connection timeout
```
- 检查网络连接
- 确认API端点地址正确
- 检查防火墙设置

**3. 模型不存在**
```
❌ Model not found
```
- 确认模型名称拼写正确
- 检查提供商是否支持该模型
- 使用推荐模型名称

**4. 配置未生效**
- 重启Galaxy服务
- 检查YAML语法格式
- 确认配置文件路径正确

### 调试步骤

1. **检查配置文件**
```bash
cat config/galaxy.yml | grep ai_
```

2. **测试模型连接**
```bash
.venv/bin/python test_multi_llm.py qwen your-api-key
```

3. **查看Galaxy日志**
```bash
tail -f galaxy.log | grep -i ai
```

4. **验证API密钥**
```bash
curl -H "Authorization: Bearer your-api-key" https://api-endpoint/models
```

## 🎉 使用AI助手

配置完成后：

1. 启动Galaxy: `sh start_galaxy_with_ai.sh`
2. 打开浏览器访问: `http://localhost:8080`
3. 在右下角寻找AI助手悬浮按钮 🤖
4. 点击开始使用AI助手！

### 示例对话

```
👤 用户: "我想分析RNA-seq数据进行差异表达分析"

🤖 AI: "我来帮您设计RNA-seq差异表达分析工作流：

1. 质量控制: 使用FastQC检查数据质量
2. 序列比对: 使用HISAT2比对到参考基因组
3. 定量分析: 使用featureCounts计算基因表达量
4. 差异分析: 使用DESeq2进行差异表达分析
5. 结果可视化: 生成火山图和热图

我可以为您生成完整的Galaxy工作流，需要吗？"
```

**🎊 恭喜！您现在拥有了一个强大的多模型AI生物信息学助手！**