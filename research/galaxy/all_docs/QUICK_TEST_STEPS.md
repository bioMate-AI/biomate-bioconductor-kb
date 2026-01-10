# 快速测试云执行 - 5分钟完成

## 你的配置
- Galaxy URL: http://localhost:8080
- 管理员邮箱: 635248762@qq.com
- Batch Queue: galaxy-cloud-queue
- S3 Bucket: galaxy-cloud-data-1760241377

## 🚀 测试步骤

### 1. 登录Galaxy（1分钟）
```
1. 打开浏览器访问: http://localhost:8080
2. 使用 635248762@qq.com 登录
   （如果还没注册，先注册这个邮箱的账户）
3. 登录后，顶部应该显示 "Admin" 菜单
```

### 2. 安装测试工具（2分钟）
```
方式A - 通过UI（推荐）:
1. 点击顶部 "Admin" → "Install and Uninstall"
2. 搜索: collection_element_identifiers
3. 找到 owner=iuc 的版本
4. 点击 "Install to Galaxy"
5. 勾选 "Install tool dependencies"
6. 点击 "Install"
7. 等待安装完成（状态变为 "Installed"）

方式B - 使用命令行:
# 如果UI安装太慢，可以用这个快速命令
ephemeris-galaxy-tool-install \
  --toolshed https://toolshed.g2.bx.psu.edu \
  --name collection_element_identifiers \
  --owner iuc \
  --galaxy http://localhost:8080 \
  --api-key YOUR_API_KEY
```

### 3. 创建测试workflow（1分钟）
```
1. 点击 "Workflow" → "Create new workflow"
2. 拖拽:
   - "Inputs" → "Collection Input"
   - "Tools" → 搜索 "Extract element identifiers" → 拖到画布
3. 连接: Collection Input → Extract element identifiers
4. 保存: 命名为 "Cloud Test"
```

### 4. 运行测试（1分钟）
```
1. 点击 "Upload Data"
2. 上传几个小文件（或用内置测试数据）
3. 创建一个Collection: 选择文件 → "Build Dataset List"
4. 点击 "Workflow" → "Cloud Test" → "Run"
5. 选择刚创建的Collection作为输入
6. 点击 "Run Workflow"
```

### 5. 验证云执行
```
查看Galaxy UI:
- 历史记录中应该看到作业运行
- 点击作业详情 → 应该显示 destination: cloud_small

查看AWS:
$ aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING
$ aws s3 ls s3://galaxy-cloud-data-1760241377/

查看日志:
$ tail -f galaxy_startup.log | grep -i "batch\|cloud"
```

---

## 🎉 成功标志

如果看到以下内容，说明云执行成功：

✅ Galaxy历史记录显示作业完成
✅ AWS Batch有作业记录
✅ S3桶中有上传的数据
✅ 作业destination显示为cloud_small/cloud_medium
✅ 结果正确返回到Galaxy

---

## 📝 备用方案：无需安装工具的测试

如果安装工具遇到问题，可以直接测试云执行底层功能：

```bash
cd lib/galaxy/galaxy-cloud-executor/examples

# 创建一个简单的测试workflow
cat > test_workflow.ga << 'EOF'
{
  "name": "Simple Test",
  "steps": {
    "0": {
      "tool_id": "cat1",
      "inputs": {"input1": {"src": "hda", "id": 1}}
    }
  }
}
EOF

# 使用独立模式测试云执行
python3 run_any_galaxy_workflow.py \
  --workflow test_workflow.ga \
  --provider aws \
  --queue galaxy-cloud-queue \
  --bucket galaxy-cloud-data-1760241377 \
  --inputs input1=/path/to/test/file.txt

# 这会直接提交作业到AWS Batch，不依赖Galaxy工具安装
```

---

## ⚡ 最快方案：使用已有的QIIME2测试

如果你只想快速验证云执行能工作：

```bash
cd lib/galaxy/galaxy-cloud-executor/test_data/qiime2_demo

# 这里有现成的测试数据和脚本
ls -la

# 查看快速测试脚本
cat 快速测试.sh

# 运行测试（这个可能需要QIIME2工具安装）
bash 快速测试.sh
```

---

## 🆘 遇到问题？

**工具安装失败**
→ 检查网络连接和Tool Shed可用性
→ 查看 Galaxy日志: tail -f galaxy_startup.log

**作业一直pending**
→ 检查AWS Batch compute environment状态
→ 运行: aws batch describe-compute-environments

**找不到Admin菜单**
→ 确认用635248762@qq.com注册并登录
→ 重启Galaxy确保配置生效

---

**推荐：先用UI安装一个简单工具测试，成功后再安装更多工具！**
