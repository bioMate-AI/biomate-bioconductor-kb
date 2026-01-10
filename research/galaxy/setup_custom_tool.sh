#!/bin/bash
# Galaxy自定义工具配置脚本

echo "=== Galaxy自定义工具配置向导 ==="

# 1. 验证目录结构
echo "1. 检查Galaxy目录结构..."
if [ ! -d "tools" ]; then
    echo "错误：当前不在Galaxy根目录"
    exit 1
fi

# 2. 创建工具目录
echo "2. 创建工具目录..."
mkdir -p tools/my_custom_tools
mkdir -p tools/custom

# 3. 设置可执行权限
echo "3. 设置脚本权限..."
chmod +x tools/my_custom_tools/text_analyzer.py
chmod +x tools/custom/sentiment_api_wrapper.py

# 4. 创建测试数据
echo "4. 创建测试数据..."
cat > tools/my_custom_tools/sample.txt << EOF
This is a sample text file for testing.
It contains multiple sentences with different sentiments.
Some are positive, some are negative, and some are neutral.
EOF

# 5. 验证配置文件
echo "5. 验证配置文件..."
if [ -f "config/tool_conf.xml.sample" ]; then
    echo "✓ 工具配置文件存在"
else
    echo "✗ 工具配置文件不存在"
fi

# 6. 更新Galaxy配置
echo "6. 更新Galaxy配置..."
if ! grep -q "tool_config_file" config/galaxy.yml; then
    echo "添加工具配置到galaxy.yml..."
    cat >> config/galaxy.yml << EOF

# Tool configuration
tool_config_file: config/tool_conf.xml.sample
EOF
fi

echo "=== 配置完成 ==="
echo "下一步："
echo "1. 重启Galaxy服务: ./run.sh --reload"  
echo "2. 在Web界面中查看'Custom Tools'分类"
echo "3. 测试您的自定义工具"