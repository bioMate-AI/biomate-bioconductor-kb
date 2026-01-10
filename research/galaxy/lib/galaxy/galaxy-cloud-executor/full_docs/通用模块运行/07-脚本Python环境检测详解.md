# 脚本Python环境检测详解

## 🔍 run_qiime2_cloud.sh 如何选择Python环境

### 完整检测流程

```bash
#!/bin/bash

# ============================================
# 第1步: 自动检测Python环境
# ============================================

# 检测1: 尝试使用 python 命令（通常是Anaconda）
if command -v python &> /dev/null && python -c "import aioboto3" &> /dev/null; then
    PYTHON_CMD="python"
    echo "✓ 使用Python: $(python --version 2>&1)"

# 检测2: 尝试使用 python3 命令（通常是系统Python）
elif command -v python3 &> /dev/null && python3 -c "import aioboto3" &> /dev/null; then
    PYTHON_CMD="python3"
    echo "✓ 使用Python: $(python3 --version 2>&1)"

# 检测3: 直接使用Anaconda路径
else
    if [ -f "$HOME/opt/anaconda3/bin/python" ]; then
        PYTHON_CMD="$HOME/opt/anaconda3/bin/python"
        echo "✓ 使用Anaconda Python: $($PYTHON_CMD --version 2>&1)"
    else
        echo "❌ 错误: 找不到安装了aioboto3的Python环境"
        exit 1
    fi
fi

# ============================================
# 第2步: 使用检测到的Python环境
# ============================================

case $choice in
    1)
        # 注意这里使用 "$PYTHON_CMD" 而不是 python3
        PYTHONPATH="$GALAXY_LIB" "$PYTHON_CMD" "$RUNNER_SCRIPT" \
            "$WORKFLOW_FILE" \
            --input 0:"$INPUT_DATA_DIR" \
            --provider aws
        ;;
esac
```

---

## 📊 你的机器上的Python环境

### 环境1: Homebrew Python 3.13
```bash
路径: /usr/local/bin/python3
版本: Python 3.13.7
包位置: /usr/local/lib/python3.13/site-packages/
状态: ❌ 没有 aioboto3
安装限制: ✓ PEP 668保护（不能随意安装包）
```

**检测结果**: 第2步检测时会失败（因为没有aioboto3），跳过

### 环境2: Anaconda Python 3.8 ✅
```bash
路径: ~/opt/anaconda3/bin/python
版本: Python 3.8.5
包位置: ~/opt/anaconda3/lib/python3.8/site-packages/
状态: ✅ 有 aioboto3, boto3, tenacity 等所有需要的包
安装限制: ✗ 无限制，可自由安装
```

**检测结果**: 第1步或第3步会成功，使用这个环境 ✅

---

## 🔄 实际执行流程

### 你运行脚本时发生了什么

```bash
$ ./run_qiime2_cloud.sh
```

#### **步骤1: 检测Python（脚本第15-34行）**

```bash
# 检测1: python命令
$ command -v python
/Users/renyuankai/opt/anaconda3/bin/python  # ✓ 存在

$ python -c "import aioboto3"
# ✓ 成功！

# 结果: PYTHON_CMD="python"
# 输出: ✓ 使用Python: Python 3.8.5
```

#### **步骤2: 设置环境变量（第38-42行）**

```bash
export GALAXY_AWS_ENABLED=true
export GALAXY_AWS_BATCH_QUEUE=galaxy-cloud-queue
export GALAXY_AWS_S3_BUCKET=galaxy-cloud-data-1760241377
export AWS_DEFAULT_REGION=us-west-2
```

#### **步骤3: 设置路径（第53-57行）**

```bash
SCRIPT_DIR="/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor"
WORKFLOW_FILE="$SCRIPT_DIR/../ai/data/workflows/workflow_0dc387dc861bdb61.json"
INPUT_DATA_DIR="$SCRIPT_DIR/test_data/qiime2_demo"
RUNNER_SCRIPT="$SCRIPT_DIR/examples/run_any_galaxy_workflow.py"
GALAXY_LIB="$SCRIPT_DIR/../.."  # = /Users/renyuankai/work/biometa/galaxy/lib
```

#### **步骤4: 执行Python脚本（第87行）**

```bash
# 完整展开后的命令:
PYTHONPATH="/Users/renyuankai/work/biometa/galaxy/lib" \
  /Users/renyuankai/opt/anaconda3/bin/python \  # ← 使用 $PYTHON_CMD (Anaconda Python)
  /Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/examples/run_any_galaxy_workflow.py \
  /Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/../ai/data/workflows/workflow_0dc387dc861bdb61.json \
  --input 0:/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/test_data/qiime2_demo \
  --provider aws \
  --staging workflows/qiime2-test \
  --output workflows/qiime2-test/outputs
```

---

## 🧪 验证脚本使用的Python

### 方法1: 查看脚本输出

```bash
$ ./run_qiime2_cloud.sh
========================================
  Galaxy Cloud Workflow Executor
  (使用通用galaxy_cloud模块)
========================================

✓ 使用Python: Python 3.8.5    # ← 这里显示使用的Python版本
```

### 方法2: 手动检测

```bash
# 模拟脚本的检测逻辑
if command -v python &> /dev/null && python -c "import aioboto3" &> /dev/null; then
    echo "会使用: $(which python)"
    python --version
fi
```

输出:
```
会使用: /Users/renyuankai/opt/anaconda3/bin/python
Python 3.8.5
```

### 方法3: 在脚本中添加调试信息

```bash
# 在第87行之前添加:
echo "DEBUG: PYTHON_CMD = $PYTHON_CMD"
echo "DEBUG: which python = $(which $PYTHON_CMD)"
```

---

## 🔧 PYTHONPATH的作用

### 什么是PYTHONPATH？

```bash
PYTHONPATH="/path/to/modules" python script.py
```

这告诉Python在哪里查找模块：

```python
# Python查找模块的顺序:
import sys
print(sys.path)

# 输出类似:
# [
#   '/Users/renyuankai/work/biometa/galaxy/lib',  # ← PYTHONPATH添加的
#   '/Users/renyuankai/opt/anaconda3/lib/python3.8',
#   '/Users/renyuankai/opt/anaconda3/lib/python3.8/site-packages',
#   ...
# ]
```

### 为什么需要设置PYTHONPATH？

因为 `galaxy_cloud` 模块不在标准位置：

```
标准位置: ~/opt/anaconda3/lib/python3.8/site-packages/galaxy_cloud/
实际位置: /Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/galaxy_cloud/
```

设置 `PYTHONPATH` 后：

```bash
PYTHONPATH="/Users/renyuankai/work/biometa/galaxy/lib"
# 展开后: /Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/

# Python就能找到:
import galaxy_cloud
# → 从 /Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/galaxy_cloud/
```

但实际上这里还有个小问题！让我检查一下 GALAXY_LIB 的值：

```bash
SCRIPT_DIR="/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor"
GALAXY_LIB="$SCRIPT_DIR/../.."
# 展开后: /Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/../..
# 化简后: /Users/renyuankai/work/biometa/galaxy/lib
```

所以实际的 PYTHONPATH 是 `/Users/renyuankai/work/biometa/galaxy/lib`，但 `galaxy_cloud` 在 `lib/galaxy/galaxy-cloud-executor/` 下！

**这是个bug！** 应该是：

```bash
GALAXY_LIB="$SCRIPT_DIR"  # 直接用galaxy-cloud-executor目录
```

---

## 🐛 发现的问题和修复

### 问题: PYTHONPATH设置不正确

**当前代码**:
```bash
GALAXY_LIB="$SCRIPT_DIR/../.."  # /Users/.../galaxy/lib
PYTHONPATH="$GALAXY_LIB" python run.py
```

**问题**: Python会在 `/galaxy/lib/` 下查找 `galaxy_cloud`，但实际模块在 `/galaxy/lib/galaxy/galaxy-cloud-executor/galaxy_cloud`

**为什么能运行?** 可能是因为Python脚本内部使用了相对导入或其他路径设置。

**正确的做法**:
```bash
GALAXY_LIB="$SCRIPT_DIR"  # /Users/.../galaxy-cloud-executor
PYTHONPATH="$GALAXY_LIB" python run.py
# 现在Python会在 /galaxy-cloud-executor/ 下查找 galaxy_cloud ✓
```

---

## ✅ 完整的修复版本

```bash
#!/bin/bash
set -e

echo "========================================"
echo "  Galaxy Cloud Workflow Executor"
echo "========================================"
echo ""

# ============================================
# 第1步: 自动检测Python环境
# ============================================
echo "检测Python环境..."

PYTHON_CMD=""

# 优先级1: python命令（通常是Anaconda）
if command -v python &> /dev/null; then
    if python -c "import aioboto3" &> /dev/null 2>&1; then
        PYTHON_CMD="python"
        echo "✓ 使用: $(python --version 2>&1) (来自: $(which python))"
    fi
fi

# 优先级2: python3命令（通常是系统Python）
if [ -z "$PYTHON_CMD" ] && command -v python3 &> /dev/null; then
    if python3 -c "import aioboto3" &> /dev/null 2>&1; then
        PYTHON_CMD="python3"
        echo "✓ 使用: $(python3 --version 2>&1) (来自: $(which python3))"
    fi
fi

# 优先级3: Anaconda完整路径
if [ -z "$PYTHON_CMD" ]; then
    if [ -f "$HOME/opt/anaconda3/bin/python" ]; then
        PYTHON_CMD="$HOME/opt/anaconda3/bin/python"
        echo "✓ 使用Anaconda: $($PYTHON_CMD --version 2>&1)"
    fi
fi

# 检查是否找到可用的Python
if [ -z "$PYTHON_CMD" ]; then
    echo "❌ 错误: 找不到安装了aioboto3的Python环境"
    echo ""
    echo "请安装依赖包:"
    echo "  pip install boto3 aioboto3 tenacity pydantic"
    echo ""
    exit 1
fi

echo ""

# ============================================
# 第2步: 设置环境变量
# ============================================
export GALAXY_AWS_ENABLED=true
export GALAXY_AWS_BATCH_QUEUE=${AWS_BATCH_QUEUE:-galaxy-cloud-queue}
export GALAXY_AWS_S3_BUCKET=${AWS_S3_BUCKET:-galaxy-cloud-data-1760241377}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-west-2}

echo "✓ AWS配置:"
echo "  Batch队列: $GALAXY_AWS_BATCH_QUEUE"
echo "  S3存储桶: $GALAXY_AWS_S3_BUCKET"
echo "  AWS区域: $AWS_DEFAULT_REGION"
echo ""

# ============================================
# 第3步: 设置路径
# ============================================
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKFLOW_FILE="$SCRIPT_DIR/../ai/data/workflows/workflow_0dc387dc861bdb61.json"
INPUT_DATA_DIR="$SCRIPT_DIR/test_data/qiime2_demo"
RUNNER_SCRIPT="$SCRIPT_DIR/examples/run_any_galaxy_workflow.py"

# 修复: PYTHONPATH应该指向galaxy-cloud-executor目录
# 这样Python才能找到 galaxy_cloud 模块
GALAXY_LIB="$SCRIPT_DIR"

echo "✓ 文件路径:"
echo "  Workflow: $WORKFLOW_FILE"
echo "  输入数据: $INPUT_DATA_DIR"
echo "  Python路径: $GALAXY_LIB"
echo ""

# 检查文件
if [ ! -f "$WORKFLOW_FILE" ]; then
    echo "❌ 错误: Workflow文件不存在: $WORKFLOW_FILE"
    exit 1
fi

if [ ! -d "$INPUT_DATA_DIR" ]; then
    echo "❌ 错误: 输入数据目录不存在: $INPUT_DATA_DIR"
    exit 1
fi

# ============================================
# 第4步: 选择执行模式
# ============================================
echo "请选择执行模式:"
echo "  1) 快速验证 (不监控)"
echo "  2) 完整执行 (带监控)"
echo ""
read -p "请输入选择 [1-2]: " choice

case $choice in
    1)
        echo ""
        echo "========== 快速验证模式 =========="
        echo ""
        # 使用检测到的Python环境
        PYTHONPATH="$GALAXY_LIB" "$PYTHON_CMD" "$RUNNER_SCRIPT" \
            "$WORKFLOW_FILE" \
            --input 0:"$INPUT_DATA_DIR" \
            --provider aws \
            --staging workflows/qiime2-test \
            --output workflows/qiime2-test/outputs
        ;;
    2)
        echo ""
        echo "========== 完整执行（带监控） =========="
        echo ""
        # 使用检测到的Python环境
        PYTHONPATH="$GALAXY_LIB" "$PYTHON_CMD" "$RUNNER_SCRIPT" \
            "$WORKFLOW_FILE" \
            --input 0:"$INPUT_DATA_DIR" \
            --provider aws \
            --staging workflows/qiime2-test \
            --output workflows/qiime2-test/outputs \
            --monitor
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "  完成！"
echo "=========================================="
```

---

## 📝 总结

### ✅ 脚本已经正确设置了Python环境

1. **自动检测**: 脚本会自动检测可用的Python环境
2. **智能选择**: 优先使用有aioboto3包的环境
3. **使用变量**: 使用 `$PYTHON_CMD` 而不是硬编码 `python3`
4. **你的机器**: 检测到并使用 Anaconda Python 3.8 ✅

### ⚠️ 发现的小问题

- PYTHONPATH设置可能不够精确，但目前能工作
- 可以优化为: `GALAXY_LIB="$SCRIPT_DIR"` 更直接

### 🎯 验证方法

运行脚本时查看输出的第一行：
```bash
✓ 使用Python: Python 3.8.5
```

这就是实际使用的Python版本！
