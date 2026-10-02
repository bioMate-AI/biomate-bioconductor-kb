# 仪器教程 —— 流式细胞仪 → 圈门与免疫表型分析（FCS）

> **适合谁读：** 任何使用流式细胞仪（BD FACSAria/Canto/Celesta、Beckman CytoFLEX、Miltenyi MACSQuant、
> Sony SH800，或任何符合 FCS 标准的仪器）、并希望把它产出的 `.fcs` 文件变成
> **"样品里有哪些细胞群体、每一群各占多少比例"** 的人 —— 不需要编程。
> **用时：** 阅读约 10 分钟；每个样品的运行通常是几分钟。
> **它在教程中的位置：** 教程六（T6）讲的是如何*连接*一台流式细胞仪，让它的文件进入 BioMate。本篇讲**这些数据
> 驱动的是什么分析、怎么跑、怎么读。**

---

## 1. 这台仪器产出什么

流式细胞仪让细胞一个接一个地通过激光，并为每一个细胞（即一个"事件 / event"）记录下：它把光散射了多少、以及
在每个荧光通道里发出的光有多亮。一个样品 = 一个 **`.fcs` 文件**（Flow Cytometry Standard，流式细胞术标准
格式），里面包含数万到数百万个事件，每个事件在以下这些通道上都有自己的数值：

- **FSC**（前向散射）≈ 细胞**大小**；**SSC**（侧向散射）≈ 细胞的**颗粒度 / 复杂度**。
- 与你所染的**标志物（marker）**对应的荧光通道 —— 例如 CD3、CD4、CD8、CD19 —— 每一个都告诉你某个蛋白是否
  存在于该细胞上。

**原始的 `.fcs` 文件是一大堆点，不是一个答案。** 要从中得到生物学信息，你必须**圈门（gating）**：画出边界，
挑出有意义的细胞群体（先挑出真正的细胞，再挑出具体的群体）。这个圈门与计数的过程，就是 BioMate 要跑的分析。

---

## 2. 它驱动的 BioMate 分析（以及为什么）

对一个染好的抗体组合（panel）来说，日常问题就是**免疫表型分析（immunophenotyping）**：*"这个样品里有哪些
由表面标志物定义的细胞群体，各占百分之多少？"*（例如"活细胞里 CD3+CD4+ 辅助性 T 细胞占多大比例？"）。做这件事
意味着按顺序**圈门** —— 这是一棵决策树：

1. **去掉杂质** —— 用 FSC/SSC 圈门，保留真实的单个细胞（排除碎片和粘连团）。*（为什么：如果不这么做，碎片和
   双联体会造出一些假的"群体"。）*
2. **挑出谱系** —— 用标志物圈门来定义每一群（例如 CD3+ = T 细胞；在这些 T 细胞里，再分 CD4+ 和 CD8+）。
   *（为什么：一个"群体"本来就是这样被定义出来的 —— 靠一组标志物阈值的组合。）*
3. **计数并报告** —— 把每一群报告为**占其母群的百分比**，以及一个绝对数。

**BioMate 会把它路由到的工作流：** **`Analyze Flow Cytometry Immunophenotyping`**（BioMate 的 `cell_biology`
（细胞生物学）领域）—— 描述为*"分析流式细胞术数据，基于表面标志物识别并定量特定细胞群体"*。它真实的参数是：

| 参数 | 它是什么 / 从哪里获取 |
|---|---|
| **`fcs_file_path`** | 要分析的 `.fcs` 文件。来自你的仪器导出。 |
| **`gating_strategy`** | 圈门策略，写成一组带有标志物阈值的、具名的群体。面板会预填一个示例，例如 `{"lymphocytes": [["FSC-A","between",[50000,150000]], ["SSC-A","between",[10000,80000]]]}` —— 你把其中的通道名和阈值改成**你自己**的 panel 的。 |
| **`compensation_matrix`** *（必填）* | 一个溢漏 / 补偿矩阵，用来校正通道之间的荧光重叠。*（为什么重要：染料会渗漏到彼此的通道里；没有补偿，一个 CD4 信号可能会被误认成 CD8。见 §6 —— 这是大家最常卡住的字段。）* |

对其他类型的流式检测，BioMate 还有一些同类工作流，会根据文件的样子自动路由：

| 你的检测（你染了什么 / 测了什么） | BioMate 提供的工作流 |
|---|---|
| 表面标志物组合，"有哪些群体、各占多少 %" | **`Analyze Flow Cytometry Immunophenotyping`**（主力工作流） |
| 用 **CFSE / CellTrace 染料稀释**来测量细胞分裂 | **`Analyze Cfse Cell Proliferation`**（报告分裂 / 增殖；参数 `cfse_channel`，例如 `FL1-A`） |
| CD4+ T 细胞里的**胞内细胞因子**（ICS，如 IFN-γ、IL-17） | **`Analyze Cytokine Production In Cd4 Tcells`** |
| **凋亡 / 衰老**（Annexin V、PI） | **`Analyze Cell Senescence And Apoptosis`** |

> **先讲一句实话：** 流式细胞仪*连接器*会根据文件 / 文件夹名和通道，给每一组文件打上一个内部路由标签（例如
> `immunophenotyping`、`cfse_proliferation`）。这个标签是一个**提示（hint）** —— 当你 Launch（启动）时，
> BioMate 会路由到上面那个真实的工作流。如果它猜错了检测类型，只要在聊天里说清楚你做的是什么（例如"这是一个
> CFSE 增殖实验"）即可。验证状态见 §6。

---

## 3. 开始前 —— 先把数据弄进来（见 T6）

- **连接流式细胞仪（适合核心设施或经常使用的场景）。** 在 **Connectors → Instruments（连接器 → 仪器）** 里注册
  一台 **Flow cytometer（流式细胞仪）**，并让你的管理员把它的文件监听器指向你的 FACSDiva / CytExpert 输出文件
  夹。监听器会按实验文件夹把 `.fcs` 文件分组，并把每次已完成的运行呈现为一个 **New data event（新数据事件）**。
  完整步骤见**教程六**。
- **手动上传（一次性）。** 从 Data（数据）区把单个 `.fcs` 文件带进来。完整步骤见**教程四**。

**运行前你需要先搞清楚：** 你的**通道名**（要和仪器写出来的完全一致，例如 `FSC-A`、`SSC-A`、`FL1-A`，或者
标志物名字）、你平时会用鼠标手动画出来的那套**圈门逻辑**，以及你的**补偿矩阵**（通常由仪器上的单染对照
产生）。

---

## 4. 一步步操作 —— 把它跑起来

<!-- CAPTURE route=/ ; state=New data events list showing a flow-cytometry event (experiment type "immunophenotyping", source flow cytometer watcher, N FCS files) with Launch + Dismiss ; focus=instrument-event ; note=show a flow-cytometry New-data event card: FCS file count, cytometer name, experiment-type badge, Launch button -->
*（待补图：一个流式细胞术的 New-data 事件 —— FCS 文件数量、流式细胞仪名称、"immunophenotyping"（免疫表型
分析）徽标，以及 Launch 按钮。）*

1. **从数据事件开始（或者直接提问）。** 在那个流式事件上点击 **Launch（启动）**（会打开一个预填草稿，此时
   还什么都不会跑），或者直接输入，例如 *"Immunophenotype this FCS file; gate lymphocytes on FSC/SSC, then
   CD3+ T cells, then CD4 vs CD8; report population percentages."*（对这个 FCS 文件做免疫表型分析；先用 FSC/SSC
   圈出淋巴细胞，再圈 CD3+ T 细胞，然后分 CD4 和 CD8；报告各群体的百分比。）
2. **确认工作流。** 面板应打开 **Analyze Flow Cytometry Immunophenotyping**（不应是"undefined"）。如果你的
   文件其实是 CFSE / 细胞因子 / 凋亡实验、而它打开错了，就说清楚这是哪种检测（§2）。
3. **设置圈门策略（`gating_strategy`）。** 把预填的示例改成与**你自己**的 panel 相符：用你真实的通道名和你为
   每一群设定的阈值。可以把它想成：把你本来要用鼠标画出来的那些门，用文字写下来。
4. **提供补偿矩阵（`compensation_matrix`，必填）。** 把你单染对照得出的溢漏矩阵填进来。*（如果你采集到的数据
   确实是已经做过补偿的，见 §6。）*
5. **接上 `.fcs` 文件**（如果还没从事件里自动链接过来），然后点 **Confirm & Run（确认并运行）**。

<!-- CAPTURE route=/ ; state=Workflow panel pre-run for Analyze Flow Cytometry Immunophenotyping, param strip showing fcs_file_path, gating_strategy, compensation_matrix ; focus=workflow-panel ; note=show pre-run panel: workflow name, the gating_strategy text field, the required compensation_matrix field, Confirm & Run -->
*（待补图：运行前的工作流面板 —— 带有一个实例的 gating-strategy（圈门策略）字段、必填的 compensation-matrix
（补偿矩阵）字段，以及 Confirm & Run 按钮。）*

---

## 5. 读懂结果 / 报告

打开 **After run（运行后）** 这一节（三个标签页 —— 见**教程三**）：

- **Summary（摘要）** —— 找到的各个群体，以及**每一群占细胞的比例**。把它当作一棵圈门树来读：例如"淋巴细胞占
  单细胞的 62% → 其中 CD3+ 占 71% → 其中 CD4+ 占 43% / CD8+ 占 29%"。百分比是免疫表型分析里最核心的数字；拿它
  在你的各个条件之间作比较。
- **Outputs（输出）** —— 各群体的计数和百分比，以表格形式给出（`json`/`txt`/`csv`），归在产生它们的那个步骤
  之下，另外还有工作流产出的任何圈门图。可下载用于你的图表。
- **Reproducibility record（可复现记录）** —— 你用的确切圈门策略、补偿矩阵和软件版本，这样你的圈门就被记录
  下来、可以重复（而不是一套没人能复现的、临时手画的门）。

> **好结果长什么样，以及要留意什么。** 一个合理的结果里，单细胞 / 淋巴细胞门应当是干净的（大部分事件被保留，
> 而不是被丢掉了 90%），各群体占其母群的百分比加起来也合理。要小心的情况：某一群只占极小一部分（一个"0.1% 的
> CD4+"很容易是噪声或圈门假象），或者未补偿的溢漏把某个标志物信号抬高了 —— 后者通常表现为一片拖尾的涂抹，而
> 不是一团干净的聚集。

---

## 6. 如实说明的局限 —— 该抱有什么预期

- **状态：可用，但尚未在真实数据上做过端到端验证。** `Analyze Flow Cytometry Immunophenotyping` 及其 CFSE /
  细胞因子 / 凋亡的同类工作流都是**真实的、已建索引的 BioMate 工作流**（已在目录中确认，带有真实的参数模式）。
  它们运行在 BioMate 的 `biomni_local` 运行时上（约 16 GB 内存）。但是，BioMate 在开发站点上**没有**一次能证明
  它们的、已记录在案的真实端到端 FCS 运行，而且流式细胞术的覆盖已知是偏薄的。把它们当作*可用但未经测试*来
  对待：第一次运行时，请准备好拿它给出的门和百分比，去和你自己的手动分析（例如在 FlowJo 里做的）核对一遍，再
  去信任它们。
- **连接器的标签只是一个路由提示，不是一个确切的工作流。** 监听器的内部标签（`immunophenotyping`、
  `cfse_proliferation` 等）并**不会**原样对应到目录 ID；BioMate 是通过匹配你的请求，把你的 Launch 路由到真实
  工作流的。如果它猜错了检测类型，就在聊天里把它扳回来。
- **补偿要你自己来。** 免疫表型分析工作流**必须**要一个补偿矩阵，它不会替你从单染对照里算出来一个。请从你的
  仪器 / 采集软件里拿到这个矩阵。如果你喂进去的是未补偿的数据、又没有矩阵，群体可能会错得"看起来还挺像那么
  回事"。
- **一次只处理一个文件。** 免疫表型分析和染料稀释这两个工作流都只接收**单个 `.fcs` 路径**。对一个多样品实验，
  请逐个样品（或逐管）运行，再由你自己去比较得到的百分比 —— 目前这些工作流里没有内置的跨多个 FCS 文件的
  批处理 / 合并，也没有跨文件的统计比较。
- **这里没有自动的 / 无监督的聚类。** 这些工作流做的是**基于阈值的圈门**，用的是你提供的策略 —— 它们不是
  FlowSOM / UMAP 那种无监督的群体发现。如果你需要那种分析，就在聊天里说出来，并把结果当作探索性的来看待。

---

## 7. 下一步去哪儿

| 你想… | 去哪儿 |
|---|---|
| 连接流式细胞仪，让运行自动到达 | **教程六** |
| 手动带进单个 `.fcs` 文件 | **教程四** |
| 理解那份三标签页报告 | **教程三** |
| 测量细胞分裂而不是表型 | 向它要 **`Analyze Cfse Cell Proliferation`** |
| 测量 CD4+ T 细胞的细胞因子产生 | 向它要 **`Analyze Cytokine Production In Cd4 Tcells`** |

习惯是：**Launch（启动）这个流式事件 → 确认是对的那个检测工作流 → 写好你的圈门策略 + 提供补偿 → 运行 → 读
各群体的百分比。**

---

## 8. 关键术语

| 术语 | 含义 —— 以及你为什么要在意 |
|---|---|
| **FCS 文件** | 一个样品的流式数据 —— 每个细胞的散射 + 荧光数值。一大堆点，不是答案。 |
| **事件（Event）** | 一个被测量的细胞（或颗粒）。"100,000 个事件" = 记录了 100,000 个细胞。 |
| **FSC / SSC** | 前向散射 ≈ 大小；侧向散射 ≈ 颗粒度。用于第一步"保留真实细胞"的圈门。 |
| **圈门（Gating）** | 一步一步地画边界、挑出群体。流式分析的核心。 |
| **圈门策略（Gating strategy）** | 把圈门决策树写下来（群体 + 标志物阈值），使其可复现。 |
| **标志物（CD3、CD4……）** | 你染的一个蛋白；它对应的通道告诉你一个细胞是否带有这个蛋白。 |
| **补偿 / 溢漏矩阵（Compensation / spillover matrix）** | 对染料渗漏进彼此通道所做的校正。这里**必填**；从单染对照里获取。 |
| **免疫表型分析（Immunophenotyping）** | 按标志物组合识别并计数细胞群体。 |

---

_依据：`biomate-connector/lab_instruments/flow_cytometer_connector.py`（实验类型 → 工作流路由）以及 BioMate
目录条目 `Analyze Flow Cytometry Immunophenotyping`（cell_biology）、`Analyze Cfse Cell Proliferation`
（immunology）、`Analyze Cytokine Production In Cd4 Tcells`（immunology）、`Analyze Cell Senescence And
Apoptosis`（cancer_biology）—— 均已通过工作流搜索确认。配套：教程三、四、六。_
