# 仪器教程 —— qPCR → 相对基因表达（ΔΔCt）

> **适合谁读：** 任何使用 qPCR 仪器（Bio-Rad CFX、Applied Biosystems QuantStudio/StepOnePlus、
> Roche LightCycler、QIAGEN Rotor-Gene、BMS MIC）、并希望把仪器给出的数字变成
> **"哪些基因上调或下调了、幅度有多大"** 这样一个答案的人 —— 不需要编程。
> **用时：** 阅读约 10 分钟；运行本身只需一两分钟（这是一个小表格的计算，不是重量级流程）。
> **它在教程中的位置：** 教程六（T6）讲的是如何*连接*一台 qPCR 仪器，让它的文件进入 BioMate。本篇从这里
> 接着往下，讲**这些数据驱动的是什么分析、怎么跑、怎么读。**

---

## 1. 这台仪器产出什么

一次实时荧光定量 PCR（qPCR）会测量样品孔里某个特定 DNA 或 RNA 靶标的含量。它给每个孔报告的核心数字是
**Cq**（定量循环数，也写作 **Ct** —— 阈值循环数）：也就是该孔的荧光越过设定阈值线时所处的 PCR 循环数。
**Cq 越低，说明起始模板越多**（因为它更早越过阈值）；Cq 越高，则模板越少。

不同厂商会把这个结果保存为：

- Bio-Rad CFX Manager → `.pcrd`（一个小型数据库文件）或 `.csv` 导出文件
- Applied Biosystems QuantStudio / StepOnePlus → `.eds` 或 `.txt` 导出文件
- Roche LightCycler → `.ixo` 或 `.xls`
- QIAGEN Rotor-Gene → `.rex`；BioMolecular Systems MIC → `.micpcr`
- 任何仪器 → 一个通用的 `.csv`/`.txt` 表格，含孔位、靶标、样品和 Cq 值

**原始的 Cq 表格并不是你要的答案。** 你的基因 Cq 值为 24，单看这个数字毫无意义 —— 它取决于你上样了多少、
加样手法，以及反应效率。要得到一个有生物学意义的答案，你必须对它做**归一化（normalisation）**。这个归一化，
就是 BioMate 要跑的分析。

---

## 2. 它驱动的 BioMate 分析（以及为什么）

RT-qPCR 实验最常见的问题是：**"在校正了每个孔里样品量的差异之后，我关注的基因在两组之间（例如处理组 vs.
对照组）是否发生了变化？"** 回答这个问题的标准方法，就是 **ΔΔCt 方法**（delta-delta-Ct，结果报告为
**2^−ΔΔCt** = 倍数变化 / fold change）。

用大白话讲，ΔΔCt 做的事分三步：

1. **ΔCt（第一个 delta）—— 校正上样量。** 对每个样品，用你关注基因的 Cq 减去一个**管家基因**（housekeeping
   gene，即一个在你各个条件之间*理应不变*的基因，例如 GAPDH 或 ACTB）的 Cq。这样就抵消掉了"这个孔里到底有
   多少总样品"的影响。*（为什么：不这样做的话，一个 cDNA 量多一倍的孔，即使没有任何生物学变化，也会看起来像
   是表达量高了一倍。）*
2. **ΔΔCt（第二个 delta）—— 与对照组比较。** 用每个样品的 ΔCt 减去你**对照组**的平均 ΔCt。这样一来，0 就
   代表"与对照相同"。
3. **2^−ΔΔCt —— 换算成倍数变化。** 因为每个 PCR 循环大致会让产物翻一倍，把 2 的 −ΔΔCt 次方算出来，就能把
   循环数换算成一个可以直接读的**倍数变化**：2.0 = "是对照的两倍"，0.5 = "是对照的一半"。

**BioMate 会把它路由到的工作流：** `normqpcr_delta_delta_cq_normalization` —— 一个基于 Bioconductor
**NormqPCR** 的流程，它"用 2^−ΔΔCq 方法、配合单个或多个管家基因，对 qPCR 数据做归一化，并计算两组之间的相对
基因表达"。它是 BioMate **transcriptomics（转录组学）** 领域里的一个简短的（3 步）工作流。如果你的实验情况
不同，还有若干相关的 NormqPCR 工作流可选：

| 你的情况 | BioMate 提供的工作流 |
|---|---|
| 处理组 vs. 对照组，且你有可靠的管家基因 | **`normqpcr_delta_delta_cq_normalization`**（主力工作流） |
| 你*不确定*自己的管家基因是否稳定 | `normqpcr_normalized_relative_quantities` / `normqpcr_compute_nrqs`（会把扩增效率考虑进来） |
| 你想先正式地挑出最稳定的参考基因 | `nf-core/stableexpression`（识别最佳的 RT-qPCR 参考基因） |
| 完全没有稳定的管家基因可用 | `unifiedwmwqpcr`（改为向整体表达水平做归一化） |

> **先讲一句实话（请读）：** qPCR *连接器*（在你实验室网络里的那个文件监听器）会给每个新文件打上一个内部路由
> 标签，例如 `rt_qpcr_expression`。这个标签是一个**提示（hint）**，并不是一个确切的工作流名字 —— 当你 Launch
> （启动）这个事件时，BioMate 的聊天会把你的请求路由到上面那个真实的目录工作流
> （`normqpcr_delta_delta_cq_normalization`）。如果你发现分析被解析成了某个不相干的东西（例如跑成了一个参考
> 基因*稳定性*流程，而不是 ΔΔCt），只要在聊天里说一句"run delta-delta-Ct relative quantification"（跑
> delta-delta-Ct 相对定量）来把它扳回来即可。哪些经过验证、哪些没有，见 §6。

---

## 3. 开始前 —— 先把数据弄进来（见 T6）

本篇假定你的 Cq 数据已经能到达 BioMate。如果还没有，就二选一：

- **连接仪器（适合经常跑 qPCR 的实验室）。** 在 **Connectors → Instruments（连接器 → 仪器）** 里注册一台
  **qPCR** 仪器，并让你的管理员把它的文件监听器指向你的 CFX/QuantStudio 软件导出的那个文件夹。之后每次新运行
  都会自动出现为 **New data events（新数据事件）**。完整步骤见**教程六**。
- **手动上传单个文件（一次性的话这就够了）。** 把你的 Cq 值导出成一个 `.csv`，从 Data（数据）区把它带进来。
  完整步骤见**教程四**。

**你的文件至少应包含什么**，才能做 ΔΔCt：一列标识每个**样品**、一列标识每个**靶基因**、一列**Cq 值**，以及
一种能把**对照**样品和处理样品区分开的方式（例如一列条件，或者样品名里带"control"字样）。你还需要知道**哪个
（些）基因是你的管家基因** —— 工作流会按名字来要这个信息。

---

## 4. 一步步操作 —— 把它跑起来

<!-- CAPTURE route=/ ; state=New data events list showing a qPCR event (experiment type "rt qpcr expression", source qPCR watcher) with Launch + Dismiss ; focus=instrument-event ; note=show a qPCR New-data event card: file name, source=qPCR, experiment type badge, Launch button -->
*（待补图：一个 qPCR 的 New-data 事件 —— 导出的文件、"RT-qPCR expression"（RT-qPCR 表达）实验类型徽标，
以及 Launch 按钮。）*

1. **从数据事件开始（或者直接提问）。** 如果仪器已连接，就在 **New data events（新数据事件）** 里找到你的
   运行并点击 **Launch（启动）** —— BioMate 会打开一个带**预填草稿**的聊天（此时还什么都不会跑）。如果你是手动
   上传的，就直接用大白话说出你的目标，例如 *"Run delta-delta-Ct relative expression on this qPCR Cq table,
   treated vs. control, housekeeping genes GAPDH and ACTB."*（对这个 qPCR Cq 表格做 delta-delta-Ct 相对表达，
   处理组 vs. 对照组，管家基因为 GAPDH 和 ACTB。）
2. **确认 BioMate 选对了工作流。** 右侧面板应打开
   **normqpcr_delta_delta_cq_normalization**（标题不应是"undefined"）。如果它打开的是另一个 qPCR 工作流，
   参见 §2 的表格换种说法，或者直接点名你要的工作流。
3. **填好两个关键设置**（工作流会按名字来要这两项）：
   - **管家基因（`qpcr_hkg`）** —— 例如 `GAPDH,ACTB`。*从哪里获取：* 就是你设计了引物的那个（些）参考基因；
     把它们全部列出，用逗号分隔。
   - **对照标签（`qpcr_control_label`）** —— 表格里用来标记对照样品的那个文本（默认是 `control`）。*从哪里
     获取：* 看你自己的样品名 / 条件列。
4. **把你的 Cq 表格接到文件输入上**，如果它还没有从事件里自动链接过来的话。
5. **确认并运行。** 点击 **Confirm & Run（确认并运行）**。因为这是一个小表格的计算，很快就会跑完。

<!-- CAPTURE route=/ ; state=Workflow panel pre-run for normqpcr_delta_delta_cq_normalization, param strip showing qpcr_hkg + qpcr_control_label filled, Confirm & Run footer ; focus=workflow-panel ; note=show pre-run panel: workflow name, the two required params filled, Confirm & Run button -->
*（待补图：运行前的工作流面板 —— 工作流名称、已填好的 `qpcr_hkg` 和 `qpcr_control_label` 两个字段，以及
Confirm & Run 按钮。）*

---

## 5. 读懂结果 / 报告

运行结束后，打开 **After run（运行后）** 这一节（就是**教程三**里讲过的那份三标签页报告）：

- **Summary（摘要）** —— 大白话的发现：哪些基因上调或下调了、幅度有多大，以**倍数变化（2^−ΔΔCt）**的形式给出。
  这样读它：
  - **倍数变化 > 1** → 该基因在处理组里比对照组**更高**（例如 3.0 = 上调三倍）。
  - **倍数变化 < 1** → 该基因**更低**（例如 0.25 = 下调四倍）。
  - **≈ 1** → 基本没有变化。
  - ΔΔCt 相差约**1 个循环 ≈ 两倍的变化**；这也正是为什么单个循环的 Cq 差异就很重要。
- **Outputs（输出）** —— 归一化后的表格：每个样品的 ΔCt、ΔΔCt 和 2^−ΔΔCt 值，归在产生它们的那个步骤之下，
  可作为文件下载，用于你的图表或补充材料。
- **Reproducibility record（可复现记录）** —— 审计记录：你用的确切管家基因和对照标签、软件版本，以及带校验和
  （按需生成）的各个输出。正是这些，让你的结果在论文里站得住脚。

> **一个好结果长什么样，以及什么时候该小心。** 一个可信的 RT-qPCR 结果里，你的*管家*基因在各条件之间应当看起来
> 是平的（如果 GAPDH 自己都在剧烈波动，你的归一化就不牢靠 —— 请改用 §2 里考虑扩增效率的工作流，或
> `stableexpression`）。倍数变化在有**生物学重复**（理想情况下每组 ≥3 个）时最可信；一个来自单孔的"5 倍变化"
> 只是个线索，算不上一个结果。

---

## 6. 如实说明的局限 —— 该抱有什么预期

- **状态：可用，但尚未在真实数据上做过端到端验证。** `normqpcr_delta_delta_cq_normalization` 是一个真实的、
  已建索引的 BioMate 工作流（已在目录中确认），构建在已发表的 Bioconductor **NormqPCR** 包之上。但 BioMate
  在开发站点上**还没有**一次已记录在案的、能端到端证明它的真实 qPCR 运行。把它当作*可用但未经测试*来对待：方法
  是标准的、工作流也确实存在，但第一次运行时，请准备好用你手算出来的数值去核对它一遍。
- **连接器的标签只是一个路由提示，不是一个确切的工作流。** qPCR 监听器的内部标签（`rt_qpcr_expression` → 一个
  内部的 `qpcr_differential_expression` 标签）并**不会**原样对应到某个目录工作流。BioMate 是通过匹配你的请求，
  把你的 Launch 路由到真实的 NormqPCR 工作流的。如果路由落错了地方，就明确点名你要的分析（§2）。
- **绝对定量 / 标准曲线定量是一个空白。** 如果你的目标是从标准曲线得到**绝对**拷贝数（而不是相对倍数变化），
  那么目前目录里**还没有一个专门的、已确认的标准曲线 qPCR 工作流**。连接器虽然有一个内部的
  `absolute_quantification` 标签，但它并不对应到一个已验证的工作流。目前请先在你仪器自带的软件里做标准曲线
  拟合，或者让 BioMate 临时帮你拟合一条曲线 —— 并把后者当作实验性的来看待。**这是一个真实存在的覆盖空白，我们
  如实说明，而不是把它糊弄过去。**
- **熔解曲线 / 引物特异性的质控不属于本工作流。** 请在仪器软件里检查你的熔解曲线；ΔΔCt 工作流假定你的 Cq 值
  已经来自特异的、单一产物的反应。
- **其他类型的 qPCR 实验会走别的路。** CRISPR 筛选 qPCR 和 ChIP-qPCR 分别由不同的流程处理（前者是一个
  MAGeCK 式的筛选工作流，后者是一个 ChIP-seq 分析）；本篇只讲相对表达。

---

## 7. 下一步去哪儿

| 你想… | 去哪儿 |
|---|---|
| 连接 qPCR 仪器，让运行自动到达 | **教程六** |
| 手动带进单个 Cq 文件 | **教程四** |
| 深入理解那份三标签页报告 | **教程三** |
| 做全基因组范围的表达测量，而不只是几个基因 | **BaseSpace → RNA-seq 教程**（`basespace-sequencing.md`） |
| 先挑出最稳定的参考基因 | 向它要 `nf-core/stableexpression` |

习惯是：**Launch（启动）这个 qPCR 事件 → 确认它打开的是 ΔΔCt 工作流 → 设好管家基因 + 对照标签 → 运行 → 读
倍数变化。**

---

## 8. 关键术语

| 术语 | 含义 —— 以及你为什么要在意 |
|---|---|
| **Cq / Ct** | 一个孔的信号越过阈值时所处的 PCR 循环数。**越低 = 起始模板越多。** 每个孔的原始数字。 |
| **管家 / 参考基因（Housekeeping / reference gene）** | 一个被假定在你各条件之间不发生变化的基因（如 GAPDH、ACTB）；用来抵消上样量的差异。如果它其实并不稳定，你的结果就不可靠。 |
| **ΔCt（delta-Ct）** | 每个样品里，关注基因的 Cq 减去管家基因的 Cq —— 校正上样量的差异。 |
| **ΔΔCt（delta-delta-Ct）** | 你样品的 ΔCt 减去对照组的平均 ΔCt —— 与对照做比较。 |
| **2^−ΔΔCt / 倍数变化** | 把 ΔΔCt 换算成一个可读的倍数：2 = 对照的两倍，0.5 = 一半。约 1 个循环 ≈ 2 倍。 |
| **NormqPCR** | BioMate ΔΔCt 工作流背后那个已发表的 Bioconductor 包。 |
| **绝对定量（Absolute quantification）** | 从标准曲线得到拷贝数（而非相对值）。**目前还没有专门的、经过验证的工作流 —— 一个已知的空白。** |

---

_依据：`biomate-connector/lab_instruments/qpcr_connector.py`（实验类型 → 工作流路由）以及 BioMate 工作流目录
条目 `normqpcr_delta_delta_cq_normalization`（Bioconductor NormqPCR，已通过工作流搜索确认）。配套：教程三、
四、六。_
