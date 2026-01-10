# 🚀 快速创建Collection并运行Workflow - 2分钟完成

## 问题
你说得对，之前的workflow需要collection输入，但创建collection有点麻烦。

## 💡 最快的解决方案（推荐）

### 方式1：一次性上传并创建Collection（30秒）

在Galaxy UI的Upload窗口，有一个快捷选项可以直接创建collection：

```
1. 点击 "Upload Data" (↑ 图标)

2. 点击 "Collection" 标签页（在窗口顶部）

3. 选择 "List" 类型

4. 点击 "Choose local files" 并选择3个文件:
   - sample1.txt
   - sample2.txt
   - sample3.txt

5. 给collection命名: test_collection

6. 点击 "Start"

7. 完成！现在有一个collection可以用了
```

### 方式2：上传后批量操作（1分钟）

```
1. Upload Data → 选择3个txt文件 → Start

2. 在历史记录面板:
   - 点击右上角 ☑️ 图标（批量操作）
   - 选中3个文件
   - "For all selected..." → "Build Dataset List"
   - 命名 → Create

3. 完成！
```

---

## 🎯 更简单的测试方案 - 使用Galaxy内置工具

如果你觉得创建collection麻烦，我可以帮你创建一个**使用内置工具**的workflow测试云执行。

但是有个问题：**内置工具默认不会路由到云端**。

让我检查一下你的job配置...
