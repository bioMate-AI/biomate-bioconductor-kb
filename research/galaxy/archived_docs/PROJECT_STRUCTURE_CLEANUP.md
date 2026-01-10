# Galaxy 项目结构整理

## 🎯 整理目标

将根目录中的调试和测试文件整理到合适的目录结构中，提高项目的可维护性。

## 📂 新的目录结构

```
galaxy/
├── debug/                     # 调试脚本 (开发时临时文件)
│   ├── debug_actual_api.py
│   ├── debug_api_server.py
│   ├── debug_authenticated_save.py
│   ├── debug_empty_results.py
│   ├── debug_frontend_logic.py
│   ├── debug_index_mismatch.py
│   ├── debug_rag_components.py
│   ├── debug_real_workflow.py
│   ├── debug_similarity.py
│   ├── debug_step_id_0.py
│   ├── debug_step_id_7.py
│   ├── debug_workflow_connections.py
│   ├── debug_workflow_content.py
│   ├── debug_workflow_loading.py
│   └── debug_workflow_steps.py
│
├── tests/                     # 测试目录
│   ├── ai/                   # AI功能测试
│   │   ├── test_ai_debug.py
│   │   ├── test_ai_server.py
│   │   ├── test_api_endpoints.py
│   │   ├── test_api_fix.py
│   │   ├── test_better_matching.py
│   │   ├── test_claude_api.py
│   │   ├── test_complete_workflow_fix.py
│   │   ├── test_core_functionality.py
│   │   ├── test_detailed_recommendations.py
│   │   ├── test_direct_api_call.py
│   │   ├── test_emergency_fix_validation.py
│   │   ├── test_end_to_end_fix.py
│   │   ├── test_english_interface.py
│   │   ├── test_enhanced_workflow_creation.py
│   │   ├── test_fixed_apis.py
│   │   ├── test_galaxy_save.py
│   │   ├── test_improved_connections.py
│   │   ├── test_rag_data_structure.py
│   │   ├── test_rag_loading.py
│   │   ├── test_simple_connection_clean.py
│   │   ├── test_simplified_end_to_end.py
│   │   ├── test_two_stage_api.py
│   │   ├── test_workflow_creation_fix.py
│   │   ├── test_workflow_fix.py
│   │   ├── final_complete_test.py
│   │   ├── final_verification_test.py
│   │   └── verify_complete_fix.py
│   │
│   ├── unit/                 # 单元测试 (原有)
│   ├── integration/          # 集成测试 (原有)  
│   └── functional/           # 功能测试 (原有)
│
├── scripts/                  # 工具脚本
│   ├── curl_test_ai.sh
│   ├── start_galaxy_debug.sh
│   └── ...
│
├── lib/                      # 核心代码 (保持不变)
├── client/                   # 前端代码 (保持不变)
├── config/                   # 配置文件 (保持不变)
└── ...
```

## 📋 文件分类规则

### 🐛 Debug目录 (`debug/`)
**用途**: 开发过程中的临时调试脚本
**特征**: 
- 文件名以 `debug_` 开头
- 用于排查特定问题
- 通常是临时性的，问题解决后可删除

**规则**:
- ✅ 保留有价值的调试脚本作为参考
- ❌ 不要提交到生产分支
- 🔄 定期清理过时的调试文件

### 🧪 Tests目录 (`tests/`)
**用途**: 正式的测试代码
**子目录**:
- `tests/ai/` - AI功能专项测试
- `tests/unit/` - 单元测试
- `tests/integration/` - 集成测试
- `tests/functional/` - 功能测试

**特征**:
- 可重复运行
- 有明确的断言和验证
- 作为CI/CD流水线的一部分

### 🛠️ Scripts目录 (`scripts/`)
**用途**: 工具脚本和自动化脚本
**特征**:
- 可执行的shell脚本
- 自动化任务
- 部署和维护工具

## 🎯 后续建议

### 1. 建立.gitignore规则
```gitignore
# Debug目录 - 不提交临时调试文件
debug/temp_*.py
debug/scratch_*.py

# 测试输出
tests/*/output/
tests/*/*.log
```

### 2. 创建测试运行脚本
```bash
#!/bin/bash
# scripts/run_ai_tests.sh

echo "🧪 Running AI functionality tests..."

# 运行AI相关测试
python -m pytest tests/ai/ -v

# 运行特定的验证测试
echo "🔍 Running verification tests..."
python tests/ai/final_verification_test.py
```

### 3. 添加README文件
为每个目录添加说明文档：
- `debug/README.md` - 调试脚本使用说明
- `tests/ai/README.md` - AI测试套件说明
- `scripts/README.md` - 工具脚本使用手册

### 4. 建立命名规范
```
调试脚本: debug_{功能}_{问题描述}.py
测试脚本: test_{模块}_{功能}.py
工具脚本: {功能}_{用途}.sh
```

## ✅ 整理完成检查清单

- [x] 创建新的目录结构
- [x] 移动调试脚本到 `debug/` 目录
- [x] 移动测试脚本到 `tests/ai/` 目录  
- [x] 移动工具脚本到 `scripts/` 目录
- [ ] 更新 `.gitignore` 文件
- [ ] 创建各目录的 README 文档
- [ ] 更新CI/CD配置以使用新的测试路径
- [ ] 清理过时的调试文件

## 🚀 使用建议

### 开发新功能时:
1. **调试阶段**: 在 `debug/` 目录创建临时调试脚本
2. **测试阶段**: 在 `tests/ai/` 目录创建正式测试
3. **自动化**: 在 `scripts/` 目录添加部署/维护脚本

### 维护现有代码时:
1. **问题排查**: 使用 `debug/` 目录中的调试工具
2. **回归测试**: 运行 `tests/ai/` 中的相关测试
3. **部署验证**: 使用 `scripts/` 中的验证脚本

这样的结构使项目更加专业和易于维护！