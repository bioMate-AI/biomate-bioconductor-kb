# 仪器教程 —— LC-MS → 蛋白质组学（DDA/DIA）与代谢组学特征检测

> **适合谁读：** 任何使用液相色谱-质谱联用仪（Thermo Orbitrap/Q-Exactive/Fusion、Waters、Bruker timsTOF、
> SCIEX）、并希望把原始质谱图变成 **"样品里有哪些蛋白（或代谢物），它们的含量在我的各个条件之间有何差异"** 的
> 人 —— 不需要编程。
> **用时：** 阅读约 12 分钟；一次真实的 LC-MS 流程运行需要几十分钟到数小时（这是重量级计算）。
> **它在教程中的位置：** 教程六（T6）讲的是如何*连接*一台 LC-MS 仪器，让它的文件进入 BioMate。本篇讲**这些
> 数据驱动的是什么分析、怎么跑、怎么读。**

---

## 1. 这台仪器产出什么

一次 LC-MS 运行先用一根色谱柱把一个复杂混合物**分离**开（这样各种分子会在不同的**保留时间 / retention
time** 到达），然后由质谱仪对正在到达的分子逐一**称重**并记录其强度。结果是一大批（质荷比 `m/z`、保留时间、
强度）测量值 —— 而且在大多数实验里，还有**碎片谱（MS/MS）**，帮助鉴定每个峰究竟是什么。

各厂商会把这些保存为各自格式的原始数据：

- Thermo（Xcalibur）→ `.raw` **文件**；Waters（MassLynx）→ `.raw` **文件夹**；Bruker → `.d` 文件夹（里面是
  `.baf`/`.tdf`）；SCIEX → `.wiff`/`.wiff.scan`。
- 大多数流程实际读取的，是一个厂商中立的 `.mzML`（用 ProteoWizard **msconvert** 转换得到）。

**原始质谱图不是一个答案。** 要把数百万个峰变成"蛋白 X 在疾病组里上调两倍"（或"代谢物 Y 只出现在处理样品
里"），需要一条多步流程。这条流程就是 BioMate 要跑的东西 —— 而具体是哪一条，取决于*你测的是什么*、以及*你是
怎么采集的*。

---

## 2. 它驱动的 BioMate 分析（以及为什么）

LC-MS 分成两类很不一样的工作，BioMate 对每一类都有各自的流程。

### 2a. 蛋白质组学 —— "有哪些蛋白、各有多少？"

你把肽段比对到了一个蛋白数据库上。用哪条流程，取决于你的**采集模式**：

- **DDA**（Data-**Dependent** Acquisition，数据依赖型采集）—— 仪器挑出强度最高的前体离子去做碎裂。这是经典的
  非标记定量工作流。
  → **`nf-core/proteomicslfq`**：一个 DDA 非标记定量流程（OpenMS + MSstats），它做蛋白鉴定（Comet / MSGF+
  数据库搜索）、基于特征的定量、质控，以及对差异蛋白丰度做分组统计检验。关键输入：`input`（你的
  `.raw`/`.mzML`）、`database`（一个要去搜索的 **FASTA** 蛋白数据库）、以及 `labeling_reagent`（非标记填
  `none`，或者选 TMT/iTRAQ 之类）。另外还有一个许可证干净的变体（`proteomics_dda_search`）。
- **DIA**（Data-**Independent** Acquisition，数据非依赖型采集 / SWATH）—— 仪器以较宽的窗口对所有东西都做
  碎裂。
  → **`nf-core/dia_proteomics_analysis`**（DIA-NN）：先从你的 FASTA 构建一个谱库，再对肽段和蛋白做定量。输入：
  你的 DIA `.raw`/`.mzML`/`.d`、一个 `fasta` 数据库、可选的 `lib`（谱库）、`qvalue`（FDR，默认 0.01）。
  `nf-core/diaproteomics`（OpenSWATH/PyProphet）是一个备选。

*为什么模式很重要：* 把 DIA 数据喂给一条 DDA 流程（或反过来）会得到错误或空白的结果 —— 这两种采集方式产生的
质谱图从根本上就不同。要清楚你的方法用的是哪种模式。

### 2b. 代谢组学 —— "有哪些小分子特征、各有多少？"

你在做小分子谱分析（而不是蛋白），所以没有蛋白数据库 —— 流程转而是在各样品间检测**特征（feature）**（一个
特征 = 某个保留时间上的一个 m/z），并试着去注释它们。

→ **`xcms_lc_ms_preprocessing`** / **`metaMS`**：基于 XCMS 的峰检测、对齐（校正保留时间，让同一个代谢物在各
样品间对得齐）、对应（把峰归并成特征）、缺口填补，以及导出一张**特征表**。`metaMS` 再加上化合物注释。这些是
标准的非靶向代谢组学的第一步。

| 你测的是什么 / 怎么测的 | BioMate 提供的工作流 |
|---|---|
| 蛋白，DDA 非标记 | **`nf-core/proteomicslfq`**（OpenMS + MSstats） |
| 蛋白，DDA，仅用许可证干净的引擎 | `proteomics_dda_search`（Comet/Sage/mokapot） |
| 蛋白，DIA / SWATH | **`nf-core/dia_proteomics_analysis`**（DIA-NN）或 `nf-core/diaproteomics`（OpenSWATH） |
| 小分子，非靶向 | **`xcms_lc_ms_preprocessing`** → **`metaMS`**（注释） |
| 同一批样品上既有蛋白质组学、又有代谢组学 | `Lc Ms Proteomics Metabolomics`（联合相关 + 共享通路整合 —— 需要两者一起） |

> **先讲一句实话：** LC-MS *连接器*会根据文件夹 / 文件名来猜 `proteomics` vs. `metabolomics` vs.
> `lipidomics`，并给文件打上一个内部路由标签（其默认值对蛋白质组学指向 DIA-NN、对代谢组学指向 XCMS）。这个
> 标签是一个**提示（hint）**。当你 Launch（启动）时，请告诉 BioMate 你的**采集模式**（DDA 还是 DIA）、以及这
> 是蛋白还是代谢物，好让它路由到上面那条对的流程。验证状态见 §6 —— 这是整组仪器里真实运行证据**最少**的一类，
> 请务必读一读。

---

## 3. 开始前 —— 先把数据弄进来（见 T6）

- **连接仪器（适合核心设施）。** 在 **Connectors → Instruments（连接器 → 仪器）** 里注册一台 **LC-MS** 仪器；
  让你的管理员把它的文件监听器指向采集输出文件夹。监听器会等一次运行写完（LC-MS 运行很长），可以选择用
  **msconvert** 把 `.raw` → `.mzML`，然后呈现为一个 **New data event（新数据事件）**。完整步骤见**教程六**。
- **手动上传（一次性）。** 转换成 `.mzML`，从 Data（数据）区把它带进来。完整步骤见**教程四**。

**你必须准备好：**
- **蛋白质组学：** 一个针对你物种的 **FASTA** 蛋白数据库（例如 UniProt 的人类蛋白质组），而且你必须知道你的
  **采集模式（DDA 还是 DIA）**，以及是否做了**标记**（非标记 vs. TMT/iTRAQ）。
- **代谢组学：** 你样品的 `.mzML` 文件，以及记下**极性（polarity）**（正离子 / 负离子模式）。
- **一张样品 / 条件表**（哪个文件属于哪一组），用于任何差异比较。

---

## 4. 一步步操作 —— 把它跑起来

<!-- CAPTURE route=/ ; state=New data events list showing an LC-MS event (experiment type "proteomics", vendor Thermo, source LC-MS watcher) with Launch + Dismiss ; focus=instrument-event ; note=show an LC-MS New-data event card: raw file, vendor badge, proteomics/metabolomics experiment-type badge, Launch -->
*（待补图：一个 LC-MS 的 New-data 事件 —— 原始文件、厂商徽标、proteomics/metabolomics（蛋白质组学 / 代谢
组学）实验类型徽标，以及 Launch 按钮。）*

1. **从数据事件开始（或者直接提问）。** 点击 **Launch（启动）**（会打开一个预填草稿，此时还什么都不会跑），
   或者输入你的目标、**并带上采集模式**，例如 *"DDA label-free proteomics on these Thermo raw files, search
   against the human UniProt FASTA, treated vs. control"*（对这些 Thermo 原始文件做 DDA 非标记蛋白质组学，用
   人类 UniProt FASTA 搜索，处理组 vs. 对照组）或 *"Untargeted metabolomics feature detection with XCMS on
   these mzML files, positive mode."*（用 XCMS 对这些 mzML 文件做非靶向代谢组学特征检测，正离子模式。）
2. **确认工作流。** 确认面板打开的是与你的模式相符的那条流程（§2）—— 例如 DDA 对应 `nf-core/proteomicslfq`、
   DIA 对应 `nf-core/dia_proteomics_analysis`、代谢组学对应 `xcms_lc_ms_preprocessing`。不应是"undefined"；
   如果打开错了，就重新说一遍你的模式。
3. **填好关键输入：**
   - 蛋白质组学：接上你的质谱图（`input`），接上 **FASTA** 的 `database`，设好 `labeling_reagent`（非标记填
     `none`），FDR / 容差之类的除非你有理由，否则就用默认值。
   - 代谢组学：接上 `.mzML` 文件，设好**极性**；峰检测 / 对齐用默认值即可。
4. **接上样品 / 条件表**，好让统计那一步知道哪些文件属于哪一组。
5. **确认并运行。** 点击 **Confirm & Run（确认并运行）**。预计会是一次**漫长**的运行（这是真实的质谱计算 ——
   蛋白质组学 DDA 可能需要约 128 GB 内存）。在 Phases（阶段）标签页里看着各阶段从 *pending → running →
   completed*（等待中 → 运行中 → 已完成）地推进。

<!-- CAPTURE route=/ ; state=Workflow panel running for nf-core/proteomicslfq, phase cards (Input Validation, Database Search, Quantification, Statistical Analysis, QC, Report) with one running ; focus=workflow-panel ; note=show the multi-phase proteomics pipeline mid-run with a phase in the running state -->
*（待补图：蛋白质组学流程运行中 —— Database Search（数据库搜索）/ Quantification（定量）/ MSstats / QC 等
阶段卡片，其中一个阶段处于运行中状态。）*

---

## 5. 读懂结果 / 报告

打开 **After run（运行后）** 这一节（两个标签页 —— 见**教程三**）：

**蛋白质组学（DDA/DIA）：**
- **Summary（摘要）** —— 核心结论：**鉴定到了多少蛋白**，以及其中哪些在你的两组之间是**差异丰度**的。差异表
  要看两个数：**倍数变化**（上调 / 下调了多少倍）加上一个 **FDR / 校正后 p 值**（有多可信 —— 越小越强；常用的
  阈值是 FDR < 0.05）。一个倍数变化大*且* FDR 低的蛋白，才是一个可靠的命中。
- **Outputs（输出）** —— **蛋白和肽段的定量矩阵**（每个样品里每个蛋白的含量）、差异丰度表，以及质控图
  （MultiQC / PTXQC）。可下载用于你的图表。

**代谢组学：**
- **Results（结果）** —— **特征表**（每一行 = 一个 m/z × 保留时间的特征，带各样品的强度），
  外加任何推定的注释（来自 HMDB/KEGG 的候选代谢物名）。*注意：* 仅凭质量得到的注释是一个**推定鉴定**，而不是一
  个已确认的化合物 —— 确认一个鉴定通常需要一个匹配的标准品，或者 MS/MS 证据。
- **Reproducibility record（可复现记录）** —— 数据库 / FASTA、FDR 阈值、各项容差、软件版本，以及各个输出 ——
  这份审计记录让结果站得住脚。

> **好结果长什么样，以及要留意什么。** 在蛋白质组学里，一次健康的运行会为你的样品类型鉴定到一个合理数量的
> 蛋白，质控图看起来也干净；要对鉴定数极少的情况起疑（往往是 FASTA 用错了、采集模式弄错了，或者转换坏了）。
> 在代谢组学里，保留时间对齐应该能把同一个特征在各样品间对齐；一个只在数个重复中的一个里出现的特征，通常
> 就是噪声。

---

## 6. 如实说明的局限 —— 请仔细读这一节

- **状态：可用，但尚未在真实数据上做过端到端验证 —— 这是整组仪器里证据最弱的一类。** 这里点名的蛋白质组学和
  代谢组学工作流都是**真实的、已建索引的 BioMate 工作流**（已在目录中确认 —— `nf-core/proteomicslfq`、
  `nf-core/dia_proteomics_analysis`、`proteomics_dda_search`、`nf-core/diaproteomics`、
  `xcms_lc_ms_preprocessing`、`metaMS`）。但 BioMate 在开发站点上**没有**一次已记录在案的真实端到端蛋白质
  组学或代谢组学运行。在你拿一个已知数据集或你以前的分析核对过它之前，请把每一个结果都当作*实验性的*来对待。
  不要把 BioMate 给出的蛋白质组学 / 代谢组学数字当作已验证的来报告。
- **连接器的标签只是一个路由提示，不是一个确切的工作流，而且它猜模式猜得很差。** LC-MS 监听器的内部默认值
  （一个内部的 `diann_proteomics` / `xcms_metabolomics` 标签）并**不会**原样对应到目录 ID，而且监听器也无法仅
  凭文件名就可靠地分辨 **DDA 和 DIA**。所以 Launch 时**你**必须说明采集模式，否则你可能拿到错的流程（以及
  错误或空白的结果）。
- **可能需要先做 `.raw` → `.mzML` 转换。** 尤其是 Thermo 的 `.raw` 转换，依赖 ProteoWizard/msconvert（Windows
  或 pwiz Docker 容器）。如果你实验室的连接器没设成自动转换，就在上传前先转好，否则你的运行可能会卡在一个读不
  进去的输入上。
- **商用场景下引擎的许可证很关键。** 有些蛋白质组学引擎（例如 DIA-NN、MSFragger、Spectronaut）在商用工作中
  **不是许可证干净的**。如果这对你适用，就优先走**许可证干净**的路线（用 Comet/Sage/mokapot 的
  `proteomics_dda_search`，或基于 OpenSWATH 的 DIA）。不确定就在运行前先问一下。
- **代谢物的鉴定是推定的。** 特征检测是可靠的；但仅凭质量就把一个特征变成一个有名字的化合物，那是一个假设，
  而不是一个已确认的鉴定。
- **脂质组学是一个空白。** 连接器虽有一个 `lipidomics` 标签，但目录里**没有一个已确认的、专门的脂质组学
  工作流**；一个脂质组学请求可能不会路由到一条真实的流程。我们如实说明，而不是把它糊弄过去。

---

## 7. 下一步去哪儿

| 你想… | 去哪儿 |
|---|---|
| 连接 LC-MS 仪器，让运行自动到达 | **教程六** |
| 手动转换 / 上传单个 `.mzML` | **教程四** |
| 理解那份两标签页报告 | **教程三** |
| 对同一批样品整合蛋白质组学 + 代谢组学 | 向它要 **`Lc Ms Proteomics Metabolomics`** |
| 走一条许可证干净的蛋白质组学路线 | 向它要 **`proteomics_dda_search`**（Comet/Sage/mokapot） |

习惯是：**Launch（启动）这个 LC-MS 事件 → 告诉 BioMate 模式（DDA/DIA）以及是蛋白还是代谢物 → 接上你的
FASTA / mzML + 样品表 → 运行（预计是个长任务）→ 读定量表和差异表，并把结果当作实验性的来看待。**

---

## 8. 关键术语

| 术语 | 含义 —— 以及你为什么要在意 |
|---|---|
| **m/z** | 质荷比 —— 质谱仪用来给分子"称重"的测量量。 |
| **保留时间（Retention time）** | 一个分子从色谱柱上洗脱下来的时间；同一个分子在各样品间应当在相同的时间洗脱出来。 |
| **DDA vs. DIA** | 两种采集模式。DDA 碎裂强度最高的那些峰；DIA 以窗口形式碎裂所有东西。**它们需要不同的流程 —— 要清楚你用的是哪种。** |
| **FASTA 数据库** | 肽段要去搜索比对的那份蛋白序列清单（仅蛋白质组学）。FASTA 用错 = 鉴定数极少或为零。 |
| **非标记 vs. TMT/iTRAQ** | 样品是否做了化学标记以便多重定量。通过 `labeling_reagent` 设置。 |
| **特征（代谢组学）（Feature）** | 某个保留时间上的一个 m/z，在各样品间被追踪。非靶向代谢组学的基本单元。 |
| **FDR / 校正后 p 值** | 一个差异命中有多可信；越小越强（常用阈值 0.05）。 |
| **推定注释（Putative annotation）** | 仅凭质量得出的一个候选代谢物名 —— 一个假设，而非一个已确认的身份。 |
| **msconvert / mzML** | ProteoWizard 的工具 / 大多数流程实际读取的厂商中立格式。 |

---

_依据：`biomate-connector/lab_instruments/lcms_connector.py`（厂商识别 + 实验类型 → 工作流路由）以及 BioMate
目录条目 `nf-core/proteomicslfq`、`nf-core/dia_proteomics_analysis`、`proteomics_dda_search`、
`nf-core/diaproteomics`、`xcms_lc_ms_preprocessing`、`metaMS`、`Lc Ms Proteomics Metabolomics` —— 均已通过工作
流搜索确认。验证空白背景：蛋白质组学 / 代谢组学没有经过核验的真实端到端运行证据。配套：教程三、四、六。_
