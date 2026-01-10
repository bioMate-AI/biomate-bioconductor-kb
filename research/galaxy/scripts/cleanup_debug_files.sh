#!/bin/bash
# 清理调试文件脚本
# 用于清理开发过程中产生的临时文件和过时的调试脚本

set -e

GALAXY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

function log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S'): $1"
}

function log_warning() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S'): $1"
}

function cleanup_debug_files() {
    log_info "🧹 开始清理调试文件..."
    
    cd "$GALAXY_ROOT"
    
    # 清理debug目录中的临时文件
    if [ -d "debug" ]; then
        log_info "清理debug目录中的临时文件..."
        find debug/ -name "temp_*.py" -delete 2>/dev/null || true
        find debug/ -name "scratch_*.py" -delete 2>/dev/null || true
        find debug/ -name "*.tmp" -delete 2>/dev/null || true
        find debug/ -name "*.log" -delete 2>/dev/null || true
    fi
    
    # 清理Python缓存文件
    log_info "清理Python缓存文件..."
    find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name "*.pyc" -delete 2>/dev/null || true
    find . -name "*.pyo" -delete 2>/dev/null || true
    
    # 清理测试输出文件
    log_info "清理测试输出文件..."
    if [ -d "tests" ]; then
        find tests/ -name "*.log" -delete 2>/dev/null || true
        find tests/ -name "output_*" -delete 2>/dev/null || true
        rm -rf tests/*/htmlcov/ 2>/dev/null || true
        rm -f tests/*/.coverage 2>/dev/null || true
    fi
    
    # 清理根目录中可能残留的临时文件
    log_info "清理根目录临时文件..."
    rm -f *.tmp 2>/dev/null || true
    rm -f *.log 2>/dev/null || true
    rm -f debug_*.txt 2>/dev/null || true
    rm -f test_output_*.json 2>/dev/null || true
    
    # 清理旧的日志文件 (保留最近7天)
    if [ -d "logs" ]; then
        log_info "清理7天前的日志文件..."
        find logs/ -name "*.log" -mtime +7 -delete 2>/dev/null || true
    fi
    
    # 清理前端构建缓存
    if [ -d "client/node_modules/.cache" ]; then
        log_info "清理前端构建缓存..."
        rm -rf client/node_modules/.cache/ 2>/dev/null || true
    fi
    
    log_info "✅ 清理完成！"
}

function show_cleanup_stats() {
    log_info "📊 清理统计信息:"
    
    # 显示各目录大小
    if [ -d "debug" ]; then
        local debug_size=$(du -sh debug/ 2>/dev/null | cut -f1)
        echo "  Debug目录: $debug_size"
    fi
    
    if [ -d "tests" ]; then
        local tests_size=$(du -sh tests/ 2>/dev/null | cut -f1)
        echo "  Tests目录: $tests_size"
    fi
    
    if [ -d "logs" ]; then
        local logs_size=$(du -sh logs/ 2>/dev/null | cut -f1)
        local logs_count=$(find logs/ -name "*.log" 2>/dev/null | wc -l)
        echo "  Logs目录: $logs_size ($logs_count 个日志文件)"
    fi
    
    # 显示Python缓存情况
    local pycache_count=$(find . -name "__pycache__" -type d 2>/dev/null | wc -l)
    echo "  Python缓存目录: $pycache_count 个"
}

function interactive_cleanup() {
    echo "🧹 Galaxy项目清理工具"
    echo "====================="
    echo
    echo "将要清理以下内容:"
    echo "- debug/目录中的临时文件"
    echo "- Python缓存文件 (__pycache__, *.pyc)"
    echo "- 测试输出文件"
    echo "- 7天前的日志文件"
    echo "- 前端构建缓存"
    echo
    
    read -p "是否继续清理? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup_debug_files
        echo
        show_cleanup_stats
    else
        log_info "清理已取消"
    fi
}

function force_cleanup() {
    log_info "强制清理模式启动..."
    cleanup_debug_files
    show_cleanup_stats
}

# 主函数
function main() {
    case "${1:-interactive}" in
        "--force"|"-f")
            force_cleanup
            ;;
        "--help"|"-h")
            echo "Galaxy调试文件清理工具"
            echo
            echo "使用方法:"
            echo "  $0              - 交互式清理"
            echo "  $0 --force      - 强制清理"
            echo "  $0 --help       - 显示帮助"
            echo
            echo "清理内容:"
            echo "  - debug/目录中的临时文件"
            echo "  - Python缓存文件"
            echo "  - 测试输出文件"
            echo "  - 旧日志文件"
            echo "  - 前端构建缓存"
            ;;
        *)
            interactive_cleanup
            ;;
    esac
}

# 执行主函数
main "$@"