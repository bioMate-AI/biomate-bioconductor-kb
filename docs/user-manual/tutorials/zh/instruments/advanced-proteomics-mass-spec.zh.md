# 仪器教程 —— 质谱蛋白质组学进阶：TMT 定量、翻译后修饰（PTM）/磷酸化位点定位、免疫肽组学

> **适合谁读：** 用高分辨质谱仪（Thermo Orbitrap / Q-Exactive / Fusion / Lumos、Bruker timsTOF）做**进阶**
> 蛋白质组学的人 —— 包括**多重 TMT/iTRAQ 定量**、**翻译后修饰（PTM）位点定位**（磷酸化蛋白质组学），或
> **免疫肽组学**（分析 HLA 呈递的肽段谱）。不需要编程。
> **用时：** 阅读约 15 分钟；一次真实的质谱流程运行需要几十分钟到数小时（重量级计算）。
> **它在教程中的位置：** 本篇是主 LC-MS 教程
> [`lcms-proteomics-metabolomics.zh.md`](./lcms-proteomics-metabolomics.zh.md) 的**配套篇**。那一篇
> 已经讲了非标记 DDA/DIA 蛋白质组学和非靶向代谢组学 —— 共通的基础（采集模式、FASTA 数据库、`.raw`→`.mzML`
> 转换）请先读那一篇，本篇不再重复，只讲那篇没覆盖的三种进阶实验。教程六（**T6**）讲如何*连接*仪器、把文件
> 送进 BioMate；**本篇**讲这些数据驱动的是什么分析、怎么跑、怎么读。

---

## 1. 这些实验产出什么

这三种实验用的都是跟普通 LC-MS 一样的硬件 —— 色谱进样、高分辨质谱记录（`m/z`、保留时间、强度）和碎片
（MS/MS）谱。厂商原始格式也跟主教程里完全一样（Thermo `.raw`、Bruker `.d`、SCIEX `.wiff`，再转成厂商中立的
`.mzML`）。真正不同的是**实验设计**、因而是**分析方法**，而不是文件类型：

- **TMT / iTRAQ（多重定量）。** 样品在混合上机前先用**等重同位素标签**做化学标记。碎裂时每种标签释放一个各自
  特有的**报告离子**，于是一张 MS/MS 谱就同时带上了该肽段在各个通道里的相对丰度（6、10、11、16、18 重）。能
  拿来分析的输入，不是原始谱本身，而是搜库软件（Proteome Discoverer、MaxQuant、SpectroMine、OpenMS 或
  Philosopher）导出的 **PSM 级结果**，外加一份你自己编写的**通道→条件对应表**。
- **PTM / 磷酸化蛋白质组学。** 还是同一批谱图，但问题变成了*修饰到底落在哪个残基上*。磷酸富集样品里，一条
  鉴定出来的肽段上，修饰可能落在若干个 S/T/Y 残基的任意一个；**位点定位**要给每一种落点打一个把握分。这里的
  输入是肽段**鉴定文件**（`identifications.id.csv`）和与之配套的 **MS2 峰列表**（`peaklist.mgf`）。
- **免疫肽组学。** 先免疫沉淀 HLA 分子、洗脱出它呈递的短肽，再用 LC-MS/MS 采集。由于洗脱下来的 HLA 配体丰度
  低、而且是**非胰蛋白酶切**的，这个实验只有在 **Orbitrap / timsTOF 级**仪器（高分辨、高灵敏度）上才有意义。
  能分析的输入是 `.mzML` 加一个蛋白 **FASTA** 搜库数据库。

**原始质谱图不是一个答案。** 要把它们变成"这个磷酸化位点在处理组里上调三倍"或"这些肽段呈递在患者的
HLA-A\*02:01 上"，需要一条多步流程 —— 具体哪一条，取决于上面的实验类型。

---

## 2. 它们驱动的 BioMate 分析（以及为什么）

### 2a. TMT / iTRAQ —— 跨通道差异丰度

→ **`msstatstmt` · `tmt_differential_abundance_analysis`** —— Bioconductor **MSstatsTMT**，做 TMT 差异丰度的
权威 R 包。
（`backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/msstatstmt/main.nf`）

它跑的是标准的 MSstatsTMT 链路：

1. **转换**：把你的搜库结果 + 注释表转成 MSstatsTMT 格式（`PDtoMSstatsTMTFormat`；MaxQuant、SpectroMine、
   OpenMS、Philosopher 各有对应的转换函数）。
2. **蛋白层汇总**：带通道/批次归一化和缺失值填补（`proteinSummarization`，`method="msstats"`、
   `global_norm=TRUE`、`reference_norm=TRUE`）。
3. **诊断谱图**（`dataProcessPlotsTMT`）。
4. **差异检验**：调节 t 检验，默认做所有两两比较（`groupComparisonTMT`），并可选一个**自定义对比矩阵**。

**输入（两个文件）：**
- `raw.pd` —— 搜库软件导出的 PSM 级结果（Proteome Discoverer 的制表符分隔表，或 MaxQuant / SpectroMine /
  OpenMS / Philosopher 的对应导出）。
- `annotation.pd` —— **需要你自己编写的 CSV**，用来描述实验设计：列包括 `Run`、`Fraction`、
  `TechRepMixture`、`Channel`、`Condition`、`BioReplicate`、`Mixture`。这份表 MSstatsTMT 没法从搜库结果里
  自动推出来。

**几个关键选项**（默认值通常就对，没理由别乱改）：`which.proteinid`（蛋白登录号在哪一列 —— PD 用
`Protein.Accessions`，MaxQuant 用 `Leading.razor.proteins`）、`method`（`msstats` 会填补缺失值，
`MedianPolish`/`Median`/`LogSum` 不填补）、`global_norm`、`reference_norm`、`moderated`，以及做自定义比较用的
`contrast.matrix`。

### 2b. PTM / 磷酸化 —— 位点定位与修饰肽比值

→ **`isobar` · `ptm_localization_quant`** —— Bioconductor **isobar**，借助 **PhosphoRS** 定位概率。
（`backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/isobar/ptm_localization_quant.nf`）

它会：

1. 写出 **PhosphoRS** 输入（`writePhosphoRSInput`），再读回定位概率（`readPhosphoRSOutput` /
   `getPhosphoRSProbabilities`）。
2. 在读入时**过滤谱图** —— 按 delta 分数（`filterSpectraDeltaScore`，`min.delta.score=10`），或者在有
   PhosphoRS 引擎时按定位概率（`filterSpectraPhosphoRS`，`min.prob=0.9`）。
3. 拟合**噪声模型**（`NoiseModel`），并在报告通道之间**估计修饰肽的比值**（`estimateRatio`）。
4. 从 PhosphoSitePlus（`getPtmInfoFromPhosphoSitePlus`）和 neXtProt（`getPtmInfoFromNextprot`）取回
   **PTM 注释**。

**输入（两个文件）：** `identifications.id.csv`（肽段鉴定）和 `peaklist.mgf`（配套的 MS2 峰列表）。
**关键选项：** `type`（同位素标记化学类型 —— `iTRAQ4plexSpectra`、`TMT6plexSpectra` 等）、`min.delta.score`、
`min.prob`、`massTolerance`，以及 `activationType`（`CID`/`HCD`）。

### 2c. 免疫肽组学 —— HLA 呈递肽鉴定、结合预测与抗原排序

免疫肽组学是一**条链** —— 几个 nf-core 流程加上 BioMate 的一个融合步骤。定量引擎 **`nf-core/mhcquant`** 是一
个 **nf-core 流程，本仓库里没有本地桩文件**；BioMate 把它当成外部 nf-core 流程来调用，参数因此遵循
nf-core/mhcquant 官方文档。

- **`nf-core/mhcquant`** —— 从 LC-MS/MS 中**鉴定并定量 MHC 结合（洗脱配体）肽段**。它跑一条基于 OpenMS 的
  流程：用 Comet 搜你的蛋白 **FASTA**、用针对非胰酶切 HLA 配体调好的 **Percolator** 控制 FDR，并可选做非标记
  定量。输入：一张 `.mzML` 样品表 + 一个 FASTA 数据库；输出：经 FDR 控制的 MHC 肽段鉴定与定量表。
- **`nf-core/hlatyping`**（OptiType）—— 从测序 reads 判定样品的 **HLA 等位基因**（I 类），让结合预测对准正确
  的等位基因。
- **`nf-core/epitopeprediction`** —— **肽段 × HLA 结合**预测（NetMHCpan / NetMHCIIpan 风格：结合分数与
  %rank）。
- **`immunology/antigen_resolution`**（一个**真实的本地** BioMate 融合流程，
  `backend/biomni_workflows/nextflow_nfcore/subworkflows/immunology/antigen_resolution/main.nf`）—— 它**不**
  重跑上面那些工具，而是**吃进**它们的输出（克隆库、HLA 分型、表位预测），为每个候选肽段算一个综合的
  **抗原解析分数**，融合 HLA 结合强度、克隆库支持度，以及可选的疾病基因相关性。它特意把一向研究不足的
  **II 类（HLA-DP/DQ/DR）**候选也拎出来。输出：`antigen_candidates.csv`、`antigen_resolution_results.json`，
  以及一份 Markdown 报告。

| 你测的是 | BioMate 提供的工作流 | 它在哪里 |
|---|---|---|
| TMT/iTRAQ 多重定量 | **`msstatstmt`**（`tmt_differential_abundance_analysis`） | 本地 Bioconductor 工作流 |
| 磷酸化 / PTM 位点定位 | **`isobar`**（`ptm_localization_quant`） | 本地 Bioconductor 工作流 |
| HLA 洗脱肽鉴定与定量 | **`nf-core/mhcquant`** | **nf-core 流程（非本地）** |
| 样品 HLA 分型 | **`nf-core/hlatyping`**（OptiType） | nf-core 流程 |
| 肽段 × HLA 结合预测 | **`nf-core/epitopeprediction`** | nf-core 流程 |
| 候选抗原/表位排序 | **`immunology/antigen_resolution`** | 本地 BioMate 融合流程 |
| 普通非标记 DDA/DIA，或代谢组学 | 见主 LC-MS 教程 | —— |

---

## 3. 开始之前 —— 先把数据弄进来（见 T6）

连接仪器**不在本篇范围内** —— 一旦你的 `.raw`/`.d`/`.wiff` 文件转成了 `.mzML`（或搜库导出已备好）、并且已经
**进入 BioMate**，本篇就接手了。连接仪器看 T6，一次性手动上传看教程四。和所有质谱工作一样，`.raw`→`.mzML`
转换（ProteoWizard **msconvert**）可能得先做 —— 参见主 LC-MS 教程的第 6 节。

**你必须先备好：**
- **TMT：** 搜库软件的 **PSM 导出**（`raw.pd`），**以及**一份手工编写的**注释 CSV**（`annotation.pd`），
  里面是通道→条件的设计（见 2a）。如果你只有**一次 MS 运行**，把 `reference_norm` 设为 FALSE（参考归一化需要
  每个运行里都有一个 `Norm` 通道）。
- **PTM/磷酸化：** 肽段**鉴定文件**（`identifications.id.csv`）和配套的 **MS2 峰列表**（`peaklist.mgf`）；
  并且清楚你的**同位素标记类型**（`type`）。
- **免疫肽组学：** 来自 **Orbitrap / timsTOF 级**仪器的 `.mzML` 文件，加一个蛋白 **FASTA** 数据库；若要跑完整
  链路，还需要用于 HLA 分型的测序 reads 以及一份 HLA 等位基因清单。

---

## 4. 一步步跑起来

1. **在对话里说清楚（或点工作流卡片）。** 把实验类型讲明白，例如
   *"用 MSstatsTMT 对这份 Proteome Discoverer 的 PSM 导出和我的注释文件做 TMT 差异丰度，处理组 vs 对照组"*，
   或 *"用 isobar 对这些鉴定结果和这个 mgf 峰列表做磷酸化位点定位，TMT6plex"*，
   或 *"免疫肽组学：用 nf-core/mhcquant 对着人类 FASTA 鉴定 HLA 洗脱肽"*。
2. **核对工作流卡片。** 确认面板打开的是对的工作流（`msstatstmt`、`isobar` 的 `ptm_localization_quant`，或
   `nf-core/mhcquant`）—— 名字不能是 "undefined"。要是开错了，把实验类型重说一遍。
3. **挂上输入**（见第 3 节里你这个实验对应的文件），设好关键选项（见第 2 节）—— 大多数运行默认值就对。
4. **确认并运行。** 点 **Confirm & Run**。预计是一次**长**运行（真实质谱计算）。看阶段卡片从
   *pending → running → completed* 推进。

<!-- CAPTURE route=/ ; state=Workflow panel running for msstatstmt tmt_differential_abundance_analysis, phase cards with one running ; focus=workflow-panel ; note=show the TMT pipeline mid-run with a phase in the running state -->
*（待补图：TMT 流程运行中 —— 转换 / 汇总 / 差异检验的阶段卡片，其中一个处于 running 状态。）*

---

## 5. 读结果 / 报告

打开 **After run** 区（两个标签页 —— 见**教程三**）。

**TMT（`msstatstmt`）：**
- **蛋白层定量** —— `quant_msstats_protein_level.csv`（每个蛋白在每个通道里的归一化丰度），以及序列化的
  `quant_msstats.rds`。
- **差异丰度** —— `test_pairwise_results.csv`（所有两两组间比较），以及当你的条件名与内置对比匹配时的
  `test_contrast_results.csv`。看 **log2 倍数变化**加**校正后 p 值**（越小越强；常用阈值是校正 p < 0.05）。
- **诊断** —— `ProfilePlot` 的 PDF，再加一个 `qc_metrics.json`，里面有若干门控检查（缺失值比例、文库大小 CV、
  保留特征比例）。

**PTM / 磷酸化（`isobar`）：**
- **`estimated_ratios.csv`** —— 每条肽段的报告通道比值（`lratio`、方差、`n.spectra`、`p.value.rat`）。
- **`ptm_info_phosphositeplus.csv`** / **`ptm_info_nextprot.csv`** —— 注释好的修饰位点信息。
- **`isobar_ptm_plots.pdf`** —— 95% 置信区间的噪声模型 MA 图；`ib_phospho.rds` / `noise_model_hcd.rds` 供下游
  复用。**定位概率高**（PhosphoRS ≥ 0.9）才让你有底气说修饰落在报告的那个残基上，而不是隔壁那个。

**免疫肽组学：**
- **`nf-core/mhcquant`** —— 经 FDR 控制的 MHC 肽段鉴定/定量表（即呈递的肽段谱）。
- **`immunology/antigen_resolution`** —— `antigen_candidates.csv`（带综合分数的排序候选）、
  `antigen_resolution_results.json`，以及一份 Markdown 报告；II 类（DP/DQ/DR）的覆盖情况会被单独列出来。

> **好结果长什么样、要留神什么。** TMT 里，一次健康的运行会把各通道归一到同一尺度上，ProfilePlot 里不会有哪个
> 通道离谱地偏；要是结果里几乎没有缺失值被*填补*，反而可疑（常是注释表写错了）。磷酸化里，只信定位概率高的
> 位点 —— 一条"鉴定出来"但位点模糊的磷酸肽，只是关于*落在哪*的一个假设，不是确证的位点。免疫肽组学里，合理
> 产出一批富集了你那个 HLA 结合基序的 **8–11 肽**（I 类）就是合格信号；肽段太少通常意味着 FASTA 用错了，或者
> 仪器灵敏度不足以测洗脱配体。

---

## 6. BioMate 还能做什么（能力面）

除了这三种实验，该平台的质谱数据还能驱动 BioMate 一大片蛋白质组学能力：

- **非标记 DDA/DIA 定量与代谢组学** —— 见主 LC-MS 教程（`nf-core/proteomicslfq`、`nf-core/diaproteomics`、
  `proteomics_dda_search`、`xcms_lc_ms_preprocessing`、`metaMS`）。
- **等重标记 PSM 装配与 DEqMS** —— `deqms/psm_table_isobaric`，用来构建等重标记 PSM 表并做 DEqMS 差异检验，是
  MSstatsTMT 之外的一条互补路线。
- **标准（非 PTM）等重标记定量** —— `isobar` 包的 `isobaric_quantification` 工作流（同位素杂质校正、归一化、
  噪声建模、蛋白比值估计）。
- **免疫基因组学全家桶** —— `nf-core/airrflow`（TCR/BCR 克隆库）、`nf-core/hlatyping`、
  `nf-core/epitopeprediction`，以及 `immunology/antigen_resolution`，用于抗原/表位发现。
- **知识与工具检索** —— BioMate 索引了 1,000+ 个 Bioconductor 工作流和 12,000+ 个工具；在对话里问一个富集/通路
  步骤（clusterProfiler/enrichGO、GSEA）、一个蛋白互作网络，或一张图，它就会路由到对的那个。

---

## 7. 诚实的边界 —— 要有的预期（请认真读）

- **TMT 和 PTM 的状态：🔧 偏薄 —— 真实，但是单包封装、非最优，且未做端到端验证。** `msstatstmt` 和 `isobar` 是
  **真实、已索引的 BioMate 工作流**，封装的是权威 Bioconductor 包（MSstatsTMT；isobar + PhosphoRS）。但它们是
  **薄薄的单包封装**，不是业界最优的伞式流程，而且在开发环境上**没有记录在案的真实端到端运行**。升级**已在计划
  中**（TMT → nf-core/quantms 伞式流程；PTM → PTMShepherd/FragPipe），但尚未交付。在用已知数据集核对过之前，
  把每个结果都当成**实验性**的 —— 不要把 BioMate 跑出来的 TMT/PTM 数字当成已验证的结果去汇报。
- **TMT 的自定义对比是个模板，不是通用比较。** 内置的自定义 `contrast.matrix` 是为一个 spike-in 设计硬编码
  的，条件名叫 `0.125`/`0.5`/`0.667`/`1`。它做了容错包裹，碰到别的设计不会崩，但只有当**你的**条件名正好对上
  时才会产出 `test_contrast_results.csv`。**两两比较**（`test_pairwise_results.csv`）则总会跑，任意设计下你该读
  的是它。
- **PhosphoRS 需要它的引擎在场。** 直接计算 PhosphoRS 概率，要求工作目录里有一个 Java 的
  `PhosphoRS.jar`/`phosphoRS.jar`，或一份预先算好的 `phosphors.out.xml`。两者都没有时，工作流会退回到
  **delta 分数**过滤（`min.delta.score=10`）—— 仍然有用，但你拿不到 PhosphoRS 的定位概率。
- **TMT 注释得你自己写。** 搜库软件**不会**生成通道→条件的注释（`Run`、`Fraction`、`Channel`、`Condition`、
  `BioReplicate`、`Mixture` 等）；注释写错或缺失，是 TMT 结果悄悄出错的头号原因。单次运行的实验必须设
  `reference_norm=FALSE`。
- **免疫肽组学很强，但受仪器档位限制，且 nf-core/mhcquant 不是本地的。** mhcquant → hlatyping →
  epitopeprediction → antigen_resolution 这条链是**业界最优且完整**的 —— 但它**受限于 Orbitrap / timsTOF 级**
  仪器；三重四极杆跑不出可用的免疫肽组。该平台的具体质谱型号**尚不清楚**，所以依赖这个实验前先确认仪器档位。
  `nf-core/mhcquant`、`nf-core/hlatyping`、`nf-core/epitopeprediction` 都是 **nf-core 流程、本仓库里没有桩
  文件** —— 只有 `antigen_resolution` 这个融合步骤是本地的。
- **`.raw`→`.mzML` 转换与引擎授权**沿用主 LC-MS 教程：上传前可能得先转换，而且某些搜库引擎（DIA-NN、MSFragger、
  Spectronaut）在商业用途下并非授权干净。详见那一篇的第 6 节。

---

## 8. 接下来去哪

| 你想… | 去哪 |
|---|---|
| 做普通非标记 DDA/DIA 蛋白质组学，或代谢组学 | 主 [LC-MS 教程](./lcms-proteomics-metabolomics.zh.md) |
| 连接质谱仪，让运行自动送达 | **教程六** |
| 手动转换/上传单个 `.mzML` | **教程四** |
| 读懂三标签页报告 | **教程三** |
| 构建等重标记 PSM 表 / 做 DEqMS 检验 | 向 BioMate 要 **`deqms/psm_table_isobaric`** |
| 从免疫肽组里排序候选抗原 | 向 BioMate 要 **`immunology/antigen_resolution`** |

养成的习惯：**说清实验类型（TMT / 磷酸化 / 免疫肽组学）→ 挂上对应输入（PSM 导出 + 注释，或 id.csv + mgf，或
mzML + FASTA）→ 确认并运行（预计是长任务）→ 读定量 / 比值 / 候选表，并把 TMT 和 PTM 结果当作实验性数据看待。**

---

## 9. 关键术语

| 术语 | 含义 —— 以及你为什么要在意 |
|---|---|
| **等重标签（TMT/iTRAQ）** | 一种化学标签，让多个样品混合后在一次运行里定量；每种标签释放一个各自特有的**报告离子**。 |
| **通道（Channel）** | 一种等重标签 = 多重组里的一个样品（例如 TMT-10plex = 10 个通道）。 |
| **参考 / `Norm` 通道** | 用于批次间归一化的通道；`reference_norm` 要求每个运行里都有一个（单次运行则设 FALSE）。 |
| **注释文件** | *你*自己写的 CSV，把通道映射到条件/生物学重复/混合组；MSstatsTMT 推不出来。 |
| **PSM** | 肽段-谱图匹配（Peptide-Spectrum Match），即一张鉴定出的谱；TMT 的输入是 PSM 级搜库导出。 |
| **位点定位 / PhosphoRS** | 修饰落在某个特定残基（而非隔壁残基）上的把握有多大；概率 ≥ 0.9 算一个可信位点。 |
| **Delta 分数** | 最佳与次佳肽段匹配之间的分数差；差距越大，这个鉴定越可信。 |
| **免疫肽组** | 一个细胞呈递在它的 HLA/MHC 分子上的那一套短肽。 |
| **HLA 分型（OptiType）** | 判定样品的 HLA 等位基因，好让结合预测用对等位基因。 |
| **结合 %rank（NetMHCpan）** | 一条肽段被预测结合某个 HLA 等位基因的强度；强结合 ≤ 2 %rank。 |
| **I 类 vs II 类 HLA** | I 类向 CD8 T 细胞呈递约 8–11 肽；II 类（DP/DQ/DR）向 CD4 T 细胞呈递更长的肽。 |

---

_依据的真实工作流文件：
`backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/msstatstmt/main.nf`（及 `_interpretation.json`、
`requirements.json`）—— MSstatsTMT 的 TMT 差异丰度；
`backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/isobar/ptm_localization_quant.nf`
（及 `_interpretation.json`、`requirements.json`）—— isobar/PhosphoRS 的 PTM 位点定位；
`backend/biomni_workflows/nextflow_nfcore/subworkflows/immunology/antigen_resolution/main.nf` —— 本地抗原融合
步骤。`nf-core/mhcquant`、`nf-core/hlatyping`、`nf-core/epitopeprediction` 是 **nf-core 流程、本地无桩文件** ——
依据 nf-core 官方流程文档。状态依 `docs/20260920_HOSPITAL_INSTRUMENT_RESOURCE_INVENTORY.md`：TMT/PTM 🔧
（U9/U12 升级在计划中），免疫肽组学 ✅ 业界最优，但受限于 Orbitrap/timsTOF 级仪器。连接不在本篇范围（交由 T6）。
配套：主 LC-MS 教程；教程三、四、六。_
