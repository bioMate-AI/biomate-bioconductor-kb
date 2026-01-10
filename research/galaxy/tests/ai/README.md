# AI Functionality Tests

Galaxy AI助手功能的测试套件，包含单元测试、集成测试和端到端验证。

## 📊 测试分类

### 🧪 单元测试
- `test_core_functionality.py` - 核心功能单元测试
- `test_rag_loading.py` - RAG数据加载测试
- `test_similarity.py` - 相似度计算测试

### 🔗 集成测试  
- `test_api_endpoints.py` - API端点集成测试
- `test_english_interface.py` - 英文接口测试
- `test_two_stage_api.py` - 两阶段API测试

### 🎯 端到端测试
- `final_verification_test.py` - 最终功能验证
- `test_end_to_end_fix.py` - 端到端修复验证
- `test_simplified_end_to_end.py` - 简化端到端测试

### 🐛 问题修复验证
- `test_workflow_fix.py` - 工作流修复验证
- `test_emergency_fix_validation.py` - 紧急修复验证
- `test_connection_*.py` - 连接问题修复测试

## 🚀 运行测试

### 运行所有AI测试
```bash
python -m pytest tests/ai/ -v
```

### 运行特定测试文件
```bash
python tests/ai/final_verification_test.py
```

### 运行端到端验证
```bash
# 确保Galaxy服务正在运行
python tests/ai/final_verification_test.py
```

### 运行API测试
```bash
# 需要Galaxy API服务运行在localhost:8080
python tests/ai/test_api_endpoints.py
```

## 📋 测试环境要求

### 环境变量
```bash
export PYTHONPATH=lib
export GALAXY_CONFIG_FILE=config/galaxy.yml
```

### 依赖服务
- Galaxy API服务 (http://localhost:8080)
- 爬虫数据 (lib/galaxy/ai/data/workflows/)
- 配置文件 (config/galaxy.yml)

### Python依赖
```bash
pip install pytest pytest-cov requests fastapi uvicorn
```

## 📈 测试覆盖率

当前测试覆盖的模块：
- ✅ RAG工作流生成器
- ✅ 工作流推荐系统  
- ✅ AI助手API端点
- ✅ 工作流连接修复
- ✅ 两阶段工作流生成
- ⚠️ LLM客户端 (部分覆盖)
- ❌ 前端集成 (待添加)

## 🎯 测试策略

### 快速验证
```bash
# 运行关键功能验证 (< 1分钟)
python tests/ai/test_core_functionality.py
```

### 完整测试套件  
```bash
# 运行所有测试 (5-10分钟)
python -m pytest tests/ai/ --cov=galaxy.ai --cov-report=html
```

### 回归测试
```bash
# 验证修复没有破坏现有功能
python tests/ai/final_verification_test.py
```

## 📝 测试报告

测试结果会生成以下报告：
- 控制台输出: 实时测试状态
- 覆盖率报告: `htmlcov/index.html`
- JUnit报告: `tests/ai/reports/junit.xml` (如果配置)

## 🛠️ 编写新测试

### 测试文件命名规范
```
test_{模块名}_{功能}.py
```

### 测试类模板
```python
import pytest
from galaxy.ai.module import TargetClass

class TestTargetClass:
    def setup_method(self):
        """每个测试方法执行前的设置"""
        self.target = TargetClass()
    
    def test_basic_functionality(self):
        """测试基本功能"""
        result = self.target.basic_method()
        assert result is not None
        assert result.status == 'success'
    
    def test_error_handling(self):
        """测试错误处理"""
        with pytest.raises(ValueError):
            self.target.invalid_method()
```

### 集成测试模板
```python
import requests

def test_api_endpoint():
    """测试API端点"""
    response = requests.post(
        "http://localhost:8080/api/ai_assistant/generate_workflow",
        json={"request_text": "test workflow", "context": {}}
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data['status'] in ['success', 'preview_success']
```

## 🚨 常见问题

### 测试失败排查
1. **服务未启动**: 确保Galaxy服务运行在localhost:8080
2. **数据缺失**: 检查爬虫数据是否存在于lib/galaxy/ai/data/workflows/
3. **环境变量**: 确认PYTHONPATH=lib已设置
4. **权限问题**: 检查文件读写权限

### 性能测试注意事项
- 端到端测试可能需要较长时间
- 并发测试时注意资源限制
- 大数据集测试建议在CI环境运行

这个测试套件确保AI功能的稳定性和可靠性！