# Workflow UUID 修复说明

## 问题

导入 `enhanced_cloud_workflow.ga` 时出现错误：
```
Invalid step UUID4 'input-sample1' in request.
```

## 原因

Galaxy要求workflow和每个步骤都必须使用**标准的UUID4格式**（36个字符，包含连字符）。

错误的UUID格式示例：
- ❌ `"input-sample1"` - 不是有效的UUID4
- ❌ `"step2-fastqc-s1"` - 不是有效的UUID4
- ❌ `"enhanced-cloud-workflow-v1"` - 不是有效的UUID4

正确的UUID4格式示例：
- ✅ `"113efdf2-8e73-45d1-b8fd-06ad9c0c9a94"`
- ✅ `"9f38ae83-57cb-4331-abe9-9f68c0d636fc"`

## 解决方案

已使用Python的 `uuid.uuid4()` 为所有步骤生成了有效的UUID：

```python
import uuid

# 为每个步骤生成唯一的UUID
step_uuid = str(uuid.uuid4())
# 例如: "113efdf2-8e73-45d1-b8fd-06ad9c0c9a94"
```

## 修复后的UUID

### Workflow UUID
```
9f38ae83-57cb-4331-abe9-9f68c0d636fc
```

### 步骤UUID
```
Step 0 (Sample 1 Input):         113efdf2-8e73-45d1-b8fd-06ad9c0c9a94
Step 1 (Sample 2 Input):         953e9957-fa50-4114-8b2e-667bdd5054da
Step 2 (Sample 1 - Initial QC):  f3e1dc95-55eb-4e09-a2ea-4e859f393683
Step 3 (Sample 2 - Initial QC):  80a4e715-425c-4c2e-960a-cf4e0a88b58e
Step 4 (Sample 1 - Trimming):    97359eea-e14a-4ff2-ad52-a707cdef9b95
Step 5 (Sample 2 - Trimming):    7729142e-fa8e-48a9-861b-8269134e7b7d
Step 6 (Sample 1 - Post-trim QC): b0a02958-c580-4414-b3f7-172e7a4526c5
Step 7 (Sample 2 - Post-trim QC): 328f026d-1a2b-4212-93f1-8b554db9ad7f
```

## 验证

现在可以成功导入workflow：

```bash
# 方法1: 使用Python测试脚本
python3 test_enhanced_cloud_workflow.py

# 方法2: 使用一键测试脚本
./quick_test.sh

# 方法3: 在Galaxy UI中手动导入
# 访问 http://localhost:8080
# Workflow -> Import -> 选择 enhanced_cloud_workflow.ga
```

## 注意事项

如果你需要手动创建或修改workflow文件：

1. **始终使用UUID4格式**
   ```python
   import uuid
   my_uuid = str(uuid.uuid4())
   ```

2. **不要使用描述性字符串作为UUID**
   - 虽然看起来更易读，但Galaxy不接受

3. **每个UUID必须唯一**
   - Workflow本身有一个UUID
   - 每个步骤都有独立的UUID

4. **UUID格式规范**
   - 必须是36个字符
   - 包含4个连字符
   - 使用十六进制字符（0-9, a-f）
   - 格式：`xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`
     - 第13位必须是 `4`（表示UUID v4）
     - 第17位必须是 `8`, `9`, `a`, 或 `b`

## 已修复

✅ `enhanced_cloud_workflow.ga` 现在使用正确的UUID4格式
✅ 可以成功导入到Galaxy
✅ 所有8个步骤都有有效的UUID
✅ Workflow本身也有有效的UUID
