# Galaxy Scripts

自动化脚本和工具集合，用于开发、测试、部署和维护Galaxy项目。

## 📁 脚本分类

### 🧪 测试脚本
- `curl_test_ai.sh` - AI API端点curl测试脚本
- `run_ai_tests.sh` - AI功能测试运行脚本

### 🚀 开发脚本  
- `start_galaxy_debug.sh` - Galaxy调试模式启动脚本

### 🔧 维护脚本
- `cleanup_debug_files.sh` - 清理临时调试文件
- `backup_config.sh` - 配置文件备份脚本

## 🚀 使用方法

### AI API测试
```bash
# 测试AI助手API端点
./scripts/curl_test_ai.sh

# 运行完整AI测试套件
./scripts/run_ai_tests.sh
```

### Galaxy开发
```bash
# 以调试模式启动Galaxy
./scripts/start_galaxy_debug.sh

# 正常启动Galaxy
./run.sh
```

### 项目维护
```bash
# 清理调试文件
./scripts/cleanup_debug_files.sh

# 备份配置
./scripts/backup_config.sh
```

## 📋 脚本详情

### curl_test_ai.sh
测试AI助手的各个API端点：
- 工作流生成API
- 两阶段工作流API
- 工作流推荐API

**使用示例**:
```bash
./scripts/curl_test_ai.sh
# 输出: API端点测试结果
```

### start_galaxy_debug.sh
以调试模式启动Galaxy，包含：
- 详细日志输出
- 开发者工具启用
- 热重载配置

**使用示例**:
```bash
./scripts/start_galaxy_debug.sh
# Galaxy将以调试模式启动在http://localhost:8080
```

## 🛠️ 自定义脚本

### 创建新脚本的最佳实践

1. **文件命名**: 使用描述性名称，如 `deploy_production.sh`
2. **权限设置**: `chmod +x scripts/your_script.sh`
3. **错误处理**: 添加适当的错误检查
4. **文档**: 在脚本开头添加使用说明

### 脚本模板
```bash
#!/bin/bash
# 脚本描述: 你的脚本功能说明
# 作者: Your Name
# 使用方法: ./scripts/your_script.sh [参数]

set -e  # 遇到错误立即退出

# 配置变量
GALAXY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$GALAXY_ROOT/logs/script.log"

# 功能函数
function log_info() {
    echo "[INFO] $(date): $1" | tee -a "$LOG_FILE"
}

function log_error() {
    echo "[ERROR] $(date): $1" | tee -a "$LOG_FILE" >&2
}

# 主逻辑
function main() {
    log_info "脚本开始执行..."
    
    # 你的脚本逻辑
    
    log_info "脚本执行完成"
}

# 参数检查
if [ $# -eq 0 ]; then
    echo "使用方法: $0 [参数]"
    exit 1
fi

# 执行主函数
main "$@"
```

## 🔧 环境要求

### 基础要求
- Bash 4.0+
- curl (用于API测试)
- jq (用于JSON处理)
- Python 3.8+ (Galaxy要求)

### 可选工具
- `httpie` - 更友好的HTTP客户端
- `watch` - 监控命令输出
- `supervisor` - 进程管理

## 📊 脚本监控

### 日志记录
所有脚本的输出都应该记录到日志文件：
```bash
./scripts/your_script.sh 2>&1 | tee logs/script_$(date +%Y%m%d_%H%M%S).log
```

### 错误通知
关键脚本可以配置错误通知：
```bash
# 在脚本中添加
function notify_error() {
    echo "Script failed: $1" | mail -s "Galaxy Script Error" admin@example.com
}
```

## 🚨 注意事项

### 安全性
- 不要在脚本中硬编码密码或API密钥
- 使用环境变量或配置文件存储敏感信息
- 设置适当的文件权限

### 可维护性
- 添加详细的注释
- 使用函数分解复杂逻辑
- 提供帮助信息和使用示例

### 兼容性
- 测试脚本在不同操作系统上的兼容性
- 检查依赖工具的可用性
- 提供依赖安装说明

## 🎯 常用脚本组合

### 开发工作流
```bash
# 1. 启动Galaxy调试模式
./scripts/start_galaxy_debug.sh &

# 2. 等待服务启动
sleep 30

# 3. 运行AI功能测试
./scripts/run_ai_tests.sh

# 4. 测试API端点
./scripts/curl_test_ai.sh
```

### 部署验证
```bash
# 1. 备份当前配置
./scripts/backup_config.sh

# 2. 部署新版本
./scripts/deploy_update.sh

# 3. 验证功能
./scripts/run_smoke_tests.sh

# 4. 清理临时文件
./scripts/cleanup_debug_files.sh
```

这些脚本帮助自动化常见的开发和维护任务，提高工作效率！