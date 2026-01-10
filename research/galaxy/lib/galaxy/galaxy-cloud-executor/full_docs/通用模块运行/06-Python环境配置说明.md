# Python环境配置说明

## 📋 问题：为什么会有多个Python环境？

你的机器上有多个Python安装：

### 1. **Homebrew Python 3.13**
```bash
/usr/local/bin/python3 → Python 3.13.7
```
- 系统级安装
- 由macOS Homebrew管理
- **受PEP 668保护** - 不能随意安装第三方包
- 需要使用虚拟环境或 `--break-system-packages` 标志

### 2. **Anaconda Python 3.8**
```bash
~/opt/anaconda3/bin/python → Python 3.8.5
```
- 用户级安装
- 科学计算环境
- **已经安装了所有需要的包**：boto3, aioboto3, aiohttp等
- 可以自由安装包

---

## 🔍 之前的问题

### **问题1：包安装到了错误的环境**

```bash
# 你运行了:
pip install aioboto3

# 这个pip属于Python 3.8 (Anaconda)
# 包被安装到: ~/opt/anaconda3/lib/python3.8/site-packages/

# 但是脚本使用的是:
python3  # 这是Python 3.13 (Homebrew)

# 结果: Python 3.13找不到aioboto3！
```

### **问题2：AWS凭证过期**

```bash
# 你使用的是AWS SSO临时凭证
# 这些凭证通常12小时后过期
# 需要定期刷新
```

---

## ✅ 解决方案：自动检测Python环境

我已经修改了 `run_qiime2_cloud.sh`，现在它会：

### **1. 自动检测可用的Python环境**

```bash
# 优先级1: python命令（通常是Anaconda）
if python -c "import aioboto3" &> /dev/null; then
    使用 python
fi

# 优先级2: python3命令（通常是系统Python）
if python3 -c "import aioboto3" &> /dev/null; then
    使用 python3
fi

# 优先级3: 直接使用Anaconda路径
if [ -f "$HOME/opt/anaconda3/bin/python" ]; then
    使用 ~/opt/anaconda3/bin/python
fi
```

### **2. 显示使用的Python版本**

运行脚本时会显示：
```
✓ 使用Anaconda Python: Python 3.8.5
```

---

## 🎯 当前配置

### **✅ 推荐配置（已实现）**

使用Anaconda Python 3.8环境，因为：
- ✅ 已安装所有需要的包
- ✅ 可以自由安装新包
- ✅ 不受系统限制
- ✅ 适合科学计算和数据分析

### **脚本自动选择：**

```bash
./run_qiime2_cloud.sh
# 输出:
# ✓ 使用Anaconda Python: Python 3.8.5
```

---

## 📦 所需的Python包

### **核心依赖**

```bash
# AWS SDK
boto3>=1.37.0          # AWS Python SDK
aioboto3>=14.0.0       # 异步版AWS SDK
botocore>=1.37.0       # AWS核心库

# 异步IO
aiohttp>=3.9.0         # 异步HTTP客户端
aiofiles>=23.0.0       # 异步文件操作
aioitertools>=0.5.0    # 异步迭代工具

# 其他
pydantic>=2.0.0        # 数据验证
tenacity>=8.0.0        # 重试机制
```

### **检查已安装的包**

```bash
# 使用Anaconda Python
python -c "
import boto3; print(f'✓ boto3 {boto3.__version__}')
import aioboto3; print(f'✓ aioboto3 {aioboto3.__version__}')
import aiohttp; print(f'✓ aiohttp {aiohttp.__version__}')
"
```

---

## 🔧 不同场景的配置方法

### **场景1：使用Anaconda（推荐，当前配置）**

```bash
# 1. 激活conda环境
conda activate base  # 或你的环境名

# 2. 安装缺失的包
pip install boto3 aioboto3

# 3. 验证
python -c "import aioboto3; print('✓ 成功')"

# 4. 运行脚本（自动使用conda python）
./run_qiime2_cloud.sh
```

### **场景2：使用Homebrew Python 3.13**

```bash
# 1. 创建虚拟环境
cd /path/to/galaxy-cloud-executor
python3 -m venv .venv

# 2. 激活虚拟环境
source .venv/bin/activate

# 3. 安装依赖
pip install boto3 aioboto3 aiohttp aiofiles pydantic tenacity

# 4. 修改脚本使用虚拟环境
# 在run_qiime2_cloud.sh开头添加:
source /path/to/.venv/bin/activate

# 5. 运行脚本
./run_qiime2_cloud.sh
```

### **场景3：系统级安装（不推荐）**

```bash
# 使用--break-system-packages标志（有风险）
python3 -m pip install --break-system-packages boto3 aioboto3

# 或者使用--user标志（安装到用户目录）
python3 -m pip install --user boto3 aioboto3
```

---

## 🐍 Python环境最佳实践

### **✅ 推荐做法**

1. **为每个项目使用虚拟环境**
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

2. **或使用Anaconda管理环境**
   ```bash
   conda create -n galaxy-cloud python=3.8
   conda activate galaxy-cloud
   pip install boto3 aioboto3
   ```

3. **明确指定Python版本**
   ```bash
   # 不要用:
   python script.py

   # 而是用:
   /path/to/specific/python script.py
   ```

### **❌ 避免的做法**

1. **不要混用pip和conda**
   ```bash
   # 不好:
   conda install numpy
   pip install pandas  # 可能导致依赖冲突

   # 好:
   conda install numpy pandas
   # 或全部用pip
   ```

2. **不要修改系统Python**
   ```bash
   # 危险:
   sudo pip install package
   pip install --break-system-packages package
   ```

3. **不要假设python命令存在**
   ```bash
   # 不好:
   python script.py  # 有些系统没有python命令

   # 好:
   python3 script.py
   # 或使用shebang: #!/usr/bin/env python3
   ```

---

## 🔄 PYTHONPATH环境变量

### **作用**

```bash
PYTHONPATH="$GALAXY_LIB" python script.py
```

这会告诉Python在哪里查找模块：

```python
# 没有PYTHONPATH:
import galaxy_cloud  # ModuleNotFoundError

# 有PYTHONPATH=/path/to/galaxy/lib:
import galaxy_cloud  # ✓ 从/path/to/galaxy/lib/galaxy_cloud导入
```

### **脚本中的设置**

```bash
GALAXY_LIB="$SCRIPT_DIR/../.."
# 展开后: /Users/renyuankai/work/biometa/galaxy/lib

PYTHONPATH="$GALAXY_LIB" python script.py
# Python会在这个目录查找galaxy_cloud模块
```

---

## 🧪 环境验证脚本

创建一个快速验证脚本：

```bash
#!/bin/bash
# verify_python_env.sh

echo "=== Python环境检查 ==="
echo ""

# 检查Python版本
echo "1. Python版本:"
python --version 2>&1 || echo "  python命令不存在"
python3 --version 2>&1 || echo "  python3命令不存在"
echo ""

# 检查包
echo "2. 检查必需的包:"
for pkg in boto3 aioboto3 aiohttp pydantic tenacity; do
    if python -c "import $pkg" 2>/dev/null; then
        version=$(python -c "import $pkg; print($pkg.__version__)" 2>/dev/null)
        echo "  ✓ $pkg $version"
    else
        echo "  ❌ $pkg (未安装)"
    fi
done
echo ""

# 检查PYTHONPATH
echo "3. PYTHONPATH:"
python -c "import sys; print('\n'.join(sys.path))"
echo ""

# 检查galaxy_cloud模块
echo "4. galaxy_cloud模块:"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GALAXY_LIB="$SCRIPT_DIR/../.."
if PYTHONPATH="$GALAXY_LIB" python -c "import galaxy_cloud" 2>/dev/null; then
    echo "  ✓ galaxy_cloud可以导入"
else
    echo "  ❌ galaxy_cloud无法导入"
fi
```

---

## 📝 总结

### **当前配置**

- ✅ 脚本自动检测并使用Anaconda Python 3.8
- ✅ 所有需要的包已安装
- ✅ PYTHONPATH正确设置
- ⚠️ 需要刷新AWS凭证

### **运行前检查**

```bash
# 1. 验证Python环境
python -c "import aioboto3; print('✓ Python环境正常')"

# 2. 验证AWS凭证
aws sts get-caller-identity

# 3. 运行workflow
./run_qiime2_cloud.sh
```

### **如果遇到问题**

1. **ModuleNotFoundError: No module named 'aioboto3'**
   ```bash
   # 安装到正确的Python环境
   python -m pip install aioboto3
   ```

2. **The security token is invalid**
   ```bash
   # 刷新AWS凭证
   ./refresh_aws_credentials.sh
   ```

3. **PYTHONPATH问题**
   ```bash
   # 手动设置
   export PYTHONPATH=/Users/renyuankai/work/biometa/galaxy/lib
   ```
