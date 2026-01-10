# Galaxy 云执行数据流程详解

## 回答：数据何时上传到S3？

**答案：在workflow运行时，每个任务执行前自动上传到S3**

不是先把所有数据上传到S3，而是**按需上传**。

## 完整流程图

```
┌─────────────────────────────────────────────────────────────────┐
│ 阶段1: 用户上传数据到Galaxy（本地存储）                          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
    用户在Galaxy UI上传FASTQ文件
                              ↓
    数据存储在本地Galaxy数据库:
    /Users/.../galaxy/database/objects/abc.dat
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 阶段2: 用户运行Workflow                                          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
    Galaxy创建多个任务（FastQC, Trimmomatic等）
    每个任务都有本地文件路径
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 阶段3: GalaxyCloudJobRunner处理任务（这里才上传S3！）            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
    对于每个任务:

    3.1 获取命令行（包含本地路径）
        原始命令:
        fastqc /Users/.../database/objects/abc.dat

    3.2 FileTransferManager.prepare_job() 被调用
        ↓
        ┌─────────────────────────────────────┐
        │ 解析命令，识别输入/输出文件          │
        │ - 输入: abc.dat                      │
        │ - 输出: output.html, output.txt      │
        └─────────────────────────────────────┘
                    ↓
        ┌─────────────────────────────────────┐
        │ 上传输入文件到S3 ⬆️                  │
        │                                      │
        │ 本地: /Users/.../abc.dat             │
        │   ↓                                  │
        │ S3: s3://bucket/workflows/           │
        │     job-123/inputs/input_0.dat       │
        └─────────────────────────────────────┘
                    ↓
        ┌─────────────────────────────────────┐
        │ 重写命令路径                         │
        │                                      │
        │ 本地路径 → 容器路径                  │
        │ /Users/.../abc.dat                   │
        │   ↓                                  │
        │ /galaxy/work/inputs/input.fastq      │
        └─────────────────────────────────────┘
                    ↓
        ┌─────────────────────────────────────┐
        │ 生成完整命令                         │
        │                                      │
        │ mkdir -p /galaxy/work/inputs &&      │
        │ aws s3 cp s3://.../input_0.dat       │
        │           /galaxy/work/inputs/ &&    │
        │ fastqc /galaxy/work/inputs/input &&  │
        │ aws s3 cp output.html                │
        │           s3://.../outputs/          │
        └─────────────────────────────────────┘

    3.3 提交任务到AWS Batch
        ↓
┌─────────────────────────────────────────────────────────────────┐
│ 阶段4: AWS Batch容器执行                                         │
└─────────────────────────────────────────────────────────────────┘
                    ↓
    容器启动后执行:

    4.1 从S3下载输入 ⬇️
        aws s3 cp s3://.../inputs/input_0.dat /galaxy/work/inputs/

    4.2 运行工具
        fastqc /galaxy/work/inputs/input.fastq

    4.3 上传输出到S3 ⬆️
        aws s3 cp output.html s3://.../outputs/output_0.html
        aws s3 cp output.txt s3://.../outputs/output_1.txt

    4.4 容器结束
                    ↓
┌─────────────────────────────────────────────────────────────────┐
│ 阶段5: FileTransferManager下载结果                               │
└─────────────────────────────────────────────────────────────────┘
                    ↓
    5.1 检测任务完成

    5.2 从S3下载输出 ⬇️
        S3: s3://.../outputs/output_0.html
          ↓
        本地: /Users/.../database/objects/def.dat

    5.3 更新Galaxy数据库
        标记任务完成，文件可用

    5.4 清理S3临时文件（可选）
        删除 s3://.../workflows/job-123/
                    ↓
┌─────────────────────────────────────────────────────────────────┐
│ 阶段6: 用户查看结果                                              │
└─────────────────────────────────────────────────────────────────┘

    Galaxy UI显示绿色结果
    用户可以下载HTML报告
```

## 关键时间点

| 时间点 | 事件 | 数据位置 |
|-------|------|---------|
| T0 | 用户上传文件 | 本地Galaxy |
| T1 | 用户启动workflow | 本地Galaxy |
| **T2** | **任务开始处理** | **此时上传到S3** ⬆️ |
| T3 | AWS容器启动 | S3 |
| T4 | 容器下载数据 | 容器内存 + S3 |
| T5 | 工具执行 | 容器内存 |
| T6 | 容器上传结果 | S3 ⬆️ |
| **T7** | **任务监控检测完成** | **从S3下载** ⬇️ |
| T8 | 结果显示 | 本地Galaxy |

## 为什么不是预先上传？

### 当前设计（按需上传）的优点：

1. **节省存储成本**
   - 只有实际执行的任务才上传
   - 中间文件不需要重复上传

2. **自动化**
   - 用户无需关心S3
   - 完全透明的云执行

3. **灵活性**
   - 可以混合本地和云端执行
   - 相同数据可用于多个任务

4. **数据一致性**
   - 始终使用最新的本地数据
   - 避免同步问题

### 预先上传的问题：

❌ 用户需要手动管理S3
❌ 数据重复（本地 + S3）
❌ 同步复杂
❌ 成本高（长期存储）

## 实际例子

### Enhanced Cloud Workflow（8个步骤）

```
Step 0: 用户上传 sample1.fastq.gz
        → 存储: /Users/.../database/objects/aaa.dat

Step 1: 用户上传 sample2.fastq.gz
        → 存储: /Users/.../database/objects/bbb.dat

------ 用户点击"运行workflow" ------

Step 2: FastQC分析sample1
        FileTransferManager:
          ⬆️  上传 aaa.dat → s3://.../job-110/inputs/input_0.dat
          🔄 重写命令
          ▶️  提交到AWS Batch
          ⏱️  等待完成
          ⬇️  下载 output.html → ccc.dat

Step 3: FastQC分析sample2
        FileTransferManager:
          ⬆️  上传 bbb.dat → s3://.../job-111/inputs/input_0.dat
          🔄 重写命令
          ▶️  提交到AWS Batch
          ⏱️  等待完成
          ⬇️  下载 output.html → ddd.dat

Step 4: Trimmomatic处理sample1
        FileTransferManager:
          ⬆️  上传 aaa.dat → s3://.../job-112/inputs/input_0.dat
          🔄 重写命令
          ▶️  提交到AWS Batch
          ⏱️  等待完成
          ⬇️  下载 trimmed.fastq → eee.dat

... （以此类推）
```

## 验证当前流程

查看日志中的数据流：

```bash
tail -f database/gravity/log/gunicorn.log | grep -E "(prepared with file transfers|Uploaded|Downloaded|aws s3 cp)"
```

**应该看到（按顺序）：**
```
INFO Job 120 prepared with file transfers
INFO Uploaded 1 input files                    # ⬆️ 此时上传到S3
INFO Expecting 2 output files
INFO Submitted Galaxy job 120 as cloud job...
INFO Downloading output files for job abc...   # ⬇️ 此时从S3下载
INFO Downloaded 2 output files
```

## S3中的数据结构

```
s3://galaxy-cloud-data-1760241377/
└── workflows/
    ├── job-110/                    # FastQC任务1
    │   ├── inputs/
    │   │   └── input_0_aaa.dat    # ⬆️ 步骤3.2上传
    │   └── outputs/
    │       ├── output_0.html       # ⬆️ 步骤4.3上传
    │       └── output_1.txt        # ⬆️ 步骤4.3上传
    │
    ├── job-111/                    # FastQC任务2
    │   ├── inputs/
    │   │   └── input_0_bbb.dat
    │   └── outputs/
    │       └── ...
    │
    └── job-112/                    # Trimmomatic任务
        ├── inputs/
        │   └── input_0_aaa.dat    # 注意：相同文件重新上传
        └── outputs/
            └── ...
```

## 总结

**回答你的问题：**

❌ **不是**先上传数据到S3，然后运行workflow
✅ **而是**运行workflow时，每个任务自动按需上传所需数据

**数据上传时机**：
- 任务被GalaxyCloudJobRunner处理时
- 在FileTransferManager.prepare_job()中
- AWS容器启动之前

**这样做的好处**：
- 用户体验和本地执行完全一样
- 自动化，无需手动管理S3
- 只上传需要的数据
- 任务结束后可以自动清理
