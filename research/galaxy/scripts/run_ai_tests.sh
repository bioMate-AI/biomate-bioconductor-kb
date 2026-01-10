#!/bin/bash
# AI功能测试运行脚本
# 使用方法: ./scripts/run_ai_tests.sh [test_type]
# test_type: all|unit|integration|e2e

set -e

# 配置变量
GALAXY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHONPATH="$GALAXY_ROOT/lib"
TEST_DIR="$GALAXY_ROOT/tests/ai"
LOG_DIR="$GALAXY_ROOT/logs"

# 创建日志目录
mkdir -p "$LOG_DIR"

# 日志函数
function log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S'): $1"
}

function log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S'): $1" >&2
}

# 检查Galaxy服务状态
function check_galaxy_service() {
    log_info "检查Galaxy服务状态..."
    
    if curl -s http://localhost:8080/api/version > /dev/null 2>&1; then
        log_info "✅ Galaxy服务正在运行"
        return 0
    else
        log_error "❌ Galaxy服务未运行，请先启动Galaxy"
        echo "提示: 运行 ./run.sh 启动Galaxy服务"
        return 1
    fi
}

# 运行单元测试
function run_unit_tests() {
    log_info "🧪 运行AI单元测试..."
    
    cd "$GALAXY_ROOT"
    export PYTHONPATH="$PYTHONPATH"
    
    # 运行核心功能测试
    python "$TEST_DIR/test_core_functionality.py"
    python "$TEST_DIR/test_rag_loading.py"
    
    log_info "✅ 单元测试完成"
}

# 运行集成测试
function run_integration_tests() {
    log_info "🔗 运行AI集成测试..."
    
    # 检查服务状态
    if ! check_galaxy_service; then
        return 1
    fi
    
    cd "$GALAXY_ROOT"
    export PYTHONPATH="$PYTHONPATH"
    
    # 运行API集成测试
    python "$TEST_DIR/test_api_endpoints.py"
    python "$TEST_DIR/test_two_stage_api.py"
    python "$TEST_DIR/test_english_interface.py"
    
    log_info "✅ 集成测试完成"
}

# 运行端到端测试
function run_e2e_tests() {
    log_info "🎯 运行端到端测试..."
    
    # 检查服务状态
    if ! check_galaxy_service; then
        return 1
    fi
    
    cd "$GALAXY_ROOT"
    export PYTHONPATH="$PYTHONPATH"
    
    # 运行最终验证测试
    python "$TEST_DIR/final_verification_test.py"
    python "$TEST_DIR/test_end_to_end_fix.py"
    
    log_info "✅ 端到端测试完成"
}

# 运行所有测试
function run_all_tests() {
    log_info "🚀 运行所有AI测试..."
    
    local start_time=$(date +%s)
    
    # 按顺序运行测试
    run_unit_tests
    run_integration_tests  
    run_e2e_tests
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_info "🎉 所有测试完成！总耗时: ${duration}秒"
}

# 生成测试报告
function generate_report() {
    log_info "📊 生成测试报告..."
    
    local report_file="$LOG_DIR/ai_test_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
Galaxy AI功能测试报告
========================

测试时间: $(date)
测试环境: $(uname -a)
Python版本: $(python --version 2>&1)

测试结果:
- 单元测试: ✅ 通过
- 集成测试: ✅ 通过  
- 端到端测试: ✅ 通过

详细日志请查看控制台输出。
EOF

    log_info "📋 测试报告已生成: $report_file"
}

# 主函数
function main() {
    local test_type="${1:-all}"
    
    log_info "开始AI功能测试 (类型: $test_type)"
    
    case "$test_type" in
        "unit")
            run_unit_tests
            ;;
        "integration")
            run_integration_tests
            ;;
        "e2e")
            run_e2e_tests
            ;;
        "all")
            run_all_tests
            generate_report
            ;;
        *)
            echo "使用方法: $0 [test_type]"
            echo "test_type选项:"
            echo "  unit        - 只运行单元测试"
            echo "  integration - 只运行集成测试"
            echo "  e2e         - 只运行端到端测试"
            echo "  all         - 运行所有测试 (默认)"
            exit 1
            ;;
    esac
    
    log_info "测试完成！"
}

# 错误处理
trap 'log_error "测试过程中发生错误，退出码: $?"' ERR

# 执行主函数
main "$@"