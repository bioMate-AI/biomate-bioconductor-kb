# 5 分钟完成你的第一次分析 > 一句话说明：读完这一页，你已经完整走过一遍闭环——目标 → 工作流 → 结果——手册的其余部分都只是细节。适合所有人。 你不需要安装任何东西，也不需要记住工作流名称。下面就是完整的闭环，走一遍。 ## 1. 打开一个新对话，描述你的目标
在[起始页](../modules/I01-getting-started-cold-start.md)上，用日常语言输入你想做的事： > "在这个计数矩阵上比较处理组与对照组的差异表达，然后做 GO 富集分析。" 在你输入时，路由器会把它听到的内容复述为一条**通道**（Instant 或 Cloud）和一个**领域**。这个请求属于 **Cloud** 工作流（一条经过验证的流水线）。参见[两条通道](00-what-is-biomate.md)。 ## 2. 附上你的数据
在[消息框](../modules/I02-composer-talking-to-biomate.md)里附上你的文件（拖放、数据库浏览器，或者一个公开登录号，例如 `GSE49712`）。BioMate 会在导入时分析它，并给出[质量判断](../modules/I05-files-and-dataset-object.md)——Good / Watch / Blocked——在任何东西运行*之前*，让你尽早发现问题。 ## 3. 检查工作流卡片，然后点击 Confirm & Run
BioMate 会提出一张工作流卡片；[运行面板](../modules/I06-running-an-analysis.md)会在对话旁边打开，参数已根据你的请求预先填好。需要的话可以调整某个参数（或者直接在对话里告诉 BioMate）。点击 **Confirm & run workflow**，它就会在云端启动。 ## 4. 看着它运行
面板会实时更新：整体状态变为 `running`，每张阶段卡片依次从 `pending → running → completed` 切换。如果某个 [QC 关卡](../appendix/C-qc-gate-reference.md)被触发，你会看到它（在部分领域，还会有自动循环进行补救并重新运行）。 ## 5. 阅读结果
完成后，面板会变成[运行后报告](../modules/I09-reports-and-reproducibility.md)：
- **Summary（摘要）**——主要发现；每个数字都链接到它所出自的[输出](../modules/I08-outputs-viewers-interactive.md)。
- **Outputs（输出）**——每个文件，都在应用内查看器中打开（表格、火山图/热图……）。
- **Reproducibility record（可复现记录）**——参数、软件、引用和校验和；可以整份下载。 这就是完整的闭环。这次运行会一直保留在这个对话里——随时可以重新打开。 ## 接下来去哪里
- 你所在领域的章节（例如[转录组学](../domains/transcriptomics.md)），了解用例以及如何解读每个输出。
- [对象模型](01-object-model.md)，理解数据集、运行、输出和报告之间如何关联。
- [附录 D](../appendix/D-troubleshooting-routing.md)，了解那些"结果正确但出人意料"的常见情况。 > **提示。** 不确定这是不是一次大规模运行？先问一个 Instant 问题（"关于 X 有哪些证据？"）——几秒钟内就能在同一个对话里得到带引用的回答，然后再决定是否进行云端运行。
