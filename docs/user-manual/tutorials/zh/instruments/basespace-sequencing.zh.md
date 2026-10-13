# 仪器教程 —— Illumina BaseSpace → RNA-seq、变异检测（WGS）与 16S

> **适合谁读：** 任何使用的 Illumina 测序仪（NovaSeq、NextSeq、MiSeq……）会上传到 **Illumina BaseSpace**、
> 并希望把这些读段变成生物学信息 —— **基因表达**、**DNA 变异**或**微生物组谱** —— 而不必手动来回搬运 FASTQ
> 文件的人。不需要编程。
> **用时：** 阅读约 12 分钟；一次测序分析运行需要几十分钟到许多小时（真实的、重量级的云端计算）。
> **它在教程中的位置：** 教程六（T6）讲的是如何*连接* BaseSpace。本篇讲**这些读段驱动的是什么分析、怎么跑、
> 怎么读。** 在五篇仪器教程里，这一篇是**验证得最好的** —— RNA-seq 和 WGS 变异检测是 BioMate 被运行得最多的
> 流程。

---

## 1. 这台仪器产出什么

一台 Illumina 测序仪会读取数百万个短 DNA 片段，并把它们写成 **FASTQ** 文件 —— 这是一种文本文件，里面是一个个
**读段（read）**（每个片段的 A/C/G/T 序列），每个读段都带一个**每碱基质量分数**（Phred：仪器对每个字母有
多大把握）。双端（paired-end）测序会为每个样品产生两个文件（**R1** 和 **R2** —— 每个片段的两端；两个都要带
上）。当你在一台连接了 **BaseSpace** 的 Illumina 机器上测序时，这些 FASTQ（以及运行元数据 —— 实验类型、平台、
样品表）就会落到 Illumina 的**云**里。

**FASTQ 读段不是一个答案。** 原始读段必须经过比对 / 定量并加以解读。你拿它们*做什么*，完全取决于**你测的是
哪种文库** —— 而这，正是决定由哪条 BioMate 流程来跑的东西。

---

## 2. 它驱动的 BioMate 分析（以及为什么）

BaseSpace 会把这次运行的**实验类型（experiment type）**告诉 BioMate，BioMate 再路由到相应的流程：

### 2a. RNA-seq → "哪些基因在两组之间发生了变化？"*（验证得最好）*

如果文库是 RNA / 转录组，目标通常是差异基因表达 —— 哪些基因在不同条件之间（疾病 vs. 健康、处理 vs. 对照）
上调或下调了。

→ **`nf-core/rnaseq`**：标准的 bulk RNA-seq 流程 —— 质控（FastQC/MultiQC）、接头 / rRNA 清理、比对
（STAR/HISAT2）和定量（Salmon/featureCounts），产出可用于差异表达（DESeq2/edgeR）的**基因计数矩阵**。它能
处理双端 / 单端，并自动检测链特异性。

*为什么是一条流程、而不是一个工具：* 从读段走到一个可信的计数矩阵，需要把修剪、比对、定量和质控正确地串接
起来 —— nf-core/rnaseq 就是社区标准的、经过测试的那条链。

### 2b. WGS / WES → "这个基因组携带哪些 DNA 变异？"*（验证得最好）*

如果是全基因组或全外显子测序，目标就是**变异检测（variant calling）** —— 找出这个样品相对于参考基因组不同的
那些 SNP 和小的插入 / 缺失（用于遗传病研究、群体遗传学等）。

→ **`Wgs Germline Gatk`**：一条 14 步的 **GATK4 最佳实践**胚系流程 —— FastQC → fastp → BWA-MEM2 比对 →
MarkDuplicates → BQSR → HaplotypeCaller → GenotypeGVCFs → 过滤 → SnpEff 注释。输入：`reads`（你的 FASTQ 或一个
SRA 登录号）、`reference` + `known_sites` + `dbsnp_vcf`，以及一个 `genome` 版本（`hg38`/`hg19`/`mm10`）。它
支持 DeepVariant/FreeBayes 作为备选的变异检出器，也支持三人家系 / 家族检出。*（对于肿瘤 / 体细胞样品，请改用
nf-core/sarek —— 这一条只做胚系。）*

### 2c. 16S / 扩增子 → "有哪些微生物、各占什么比例？"

如果是 16S/18S/ITS 扩增子运行（微生物组），目标是群落谱分析。

→ **`nf-core/ampliseq`**：用 DADA2/QIIME2 做 ASV 检出、物种分类（SILVA/UNITE），以及 α/β 多样性。输入包括
引物序列（`FW_primer`/`RV_primer`）、高变`region`（区域），以及一个 `classifier`（分类器）。

| BaseSpace 运行类型 | BioMate 路由到的工作流 | 验证情况 |
|---|---|---|
| RNA / 转录组 | **`nf-core/rnaseq`** | **已在真实数据上验证**（在真实 GEO 数据集上跑过，例如在 AWS Batch 上） |
| 全基因组 / 外显子（胚系） | **`Wgs Germline Gatk`** | **已验证**（BioMate 精心构建的 GATK4 流程，与目录精确匹配） |
| 16S / 18S / ITS 扩增子 | **`nf-core/ampliseq`** | 可用（真实的 nf-core 流程；请在你的数据上确认） |
| 肿瘤 / 体细胞 | `nf-core/sarek`（向它要） | 可用 |
| 未知 / 其他 | 一个通用的 FASTQ 处理器 | **兜底 —— 可能不会路由到某条特定流程；请你自己点名分析** |

> **先讲一句实话：** BaseSpace 是唯一一个接入**云服务**、而不是你局域网上文件监听器的连接器。连接器会读取
> BaseSpace 的运行元数据，并把**实验类型**映射到上面那些流程之一（它内部对 RNA-seq 的标签是
> `rnaseq_differential`、对 WGS 是 `wgs_germline_gatk`、对扩增子是 `metagenomics_16s`）。当你 Launch（启动）
> 时，BioMate 会路由到上面点名的那条真实目录流程。如果某次运行的实验类型是空白或标错了，就说明一下这个文库是
> 什么，好让它路由正确。

---

## 3. 开始前 —— 先把数据弄进来（见 T6）

BaseSpace 和那些实验台上的仪器有两点你必须知道的不同：

- **数据驻留 = 云端。** BaseSpace 是 Illumina 的**云**服务，所以你的数据存放在（并从那里拉取）Illumina 的系统
  里 —— 它**不在**本地。对于患者数据或其他受限数据，这种驻留方式是由你来负责的。每一行仪器都会显示这个徽标；
  **在连接受限数据之前，务必先核对它。**（T6 讲了数据驻留。）
- **连接 = OAuth，外加一个持续运行的轮询。** 你用一个 **API 密钥 / OAuth 令牌**来连接 BaseSpace，而不是一个
  局域网文件监听器。注册密钥能让 BioMate **检查并存储**这个连接；但还必须有一个云端连接器 / 轮询带着你的密钥
  运行起来，已完成的运行才会作为事件出现。问一下你的管理员那个轮询是否在运行。完整步骤见**教程六**。

连接好之后，BioMate 会列出你**已完成**的 BaseSpace 运行，连同它们的实验类型、平台和样品数，并为每次运行预填一个
工作流建议。

**每类分析你会需要什么：** 做 **WGS**，要一个参考基因组版本（`hg38`/`hg19`/`mm10`）和 known-sites VCF
（BioMate 可以注入标准参考）；做 **RNA-seq**，要你用于差异比较的样品 / 条件分组；做 **16S**，要你的引物序列和
目标区域。

---

## 4. 一步步操作 —— 把它跑起来

<!-- CAPTURE route=/ ; state=New data events / BaseSpace runs list showing a completed run (experiment type RNA-seq, platform NovaSeq, N samples) with Launch ; focus=instrument-event ; note=show a BaseSpace run card: run name, experiment-type badge, platform, sample count, cloud residency badge, Launch -->
*（待补图：一个 BaseSpace 的已完成运行事件 —— 运行名、实验类型徽标、平台、样品数、**cloud**（云端）数据驻留
徽标，以及 Launch 按钮。）*

1. **从运行事件开始（或者直接提问）。** 在那次已完成的 BaseSpace 运行上点击 **Launch（启动）**（会打开一个
   预填草稿，此时还什么都不会跑），或者输入你的目标，例如 *"Run nf-core/rnaseq on this BaseSpace run, then
   differential expression treated vs. control"*（对这次 BaseSpace 运行跑 nf-core/rnaseq，然后做处理组 vs.
   对照组的差异表达）或 *"Germline variant calling (GATK) on this WGS run against hg38."*（对这次 WGS 运行
   针对 hg38 做胚系变异检测（GATK）。）
2. **确认工作流。** 确认面板打开的是与你的运行类型相符的那条流程（§2）—— `nf-core/rnaseq`、`Wgs Germline
   Gatk`，或 `nf-core/ampliseq`。不应是"undefined"；如果实验类型是空白、它又猜错了，就重新说明这个文库是
   什么。
3. **确认关键输入：**
   - **RNA-seq：** 确认 FASTQ 已链接（双端就是 R1/R2），并设好你的样品 / 条件分组。
   - **WGS：** 设好 `genome` 版本（例如 `hg38`）；BioMate 可以提供标准参考 / known-sites。
   - **16S：** 设好引物和区域。
4. **确认并运行。** 点击 **Confirm & Run（确认并运行）**。预计会是一次**漫长**的云端运行 —— 在 Phases
   （阶段）标签页里看着各阶段从 *pending → running → completed*（等待中 → 运行中 → 已完成）地推进，并让任何
   运行途中的**质控闸门（QC gate）**暂停并给出报告（它绝不会悄悄放过一个没通过的检查 —— 见 T3）。

<!-- CAPTURE route=/ ; state=Workflow panel running for Wgs Germline Gatk, 14-step phase cards (QC, Alignment, Variant Calling…) with one phase running ; focus=workflow-panel ; note=show the WGS pipeline mid-run with a phase in the running state and the overall running badge -->
*（待补图：WGS 流程运行中 —— FastQC / Alignment（比对）/ Variant-Calling（变异检测）等阶段卡片，其中一个
阶段处于运行中状态。）*

---

## 5. 读懂结果 / 报告

打开 **After run（运行后）** 这一节（两个标签页 —— 见**教程三**）：

**RNA-seq：**
- **Summary（摘要）** —— 差异表达的基因：看两个数 —— **log2 倍数变化**（上调 / 下调了多少个翻倍；+1 = 翻了
  一倍，−1 = 减半）和**校正后 p 值 / FDR**（可信度；越小越强，常用阈值 0.05）。一个倍数变化大*且* FDR 小的
  基因，才是一个可靠的命中。
- **Outputs（输出）** —— **基因计数矩阵**、差异表达表，以及 **MultiQC** 报告（整体运行质量）。可下载用于你的
  图表。

**WGS / 变异检测：**
- **Summary / Outputs（结果）** —— 一个带注释的 **VCF**（变异清单：位置、参考碱基 vs. 替代碱基，以及
  SnpEff 对可能效应的注释）、一个重校正后的 **BAM**（比对结果），以及覆盖度 / 质控指标。VCF 是核心；覆盖度告诉
  你测得够不够深、能不能信任这些检出。
- 预览方面：一个 VCF 会以变异表的形式预览；一个 **BAM** 则是下载 / 交互式（目前还没有内嵌的基因组浏览器
  轨道 —— 见 T5）。

**16S：** 一张物种分类表（有谁在场）和多样性指标（每个群落有多丰富多样）。

- **Reproducibility record（可复现记录）**（所有类型都有）—— 基因组版本、参数、工具版本，以及带校验和的
  各个输出 —— 这份审计记录让结果在论文或申报里站得住脚。

> **好结果长什么样，以及要留意什么。**
> - **RNA-seq：** MultiQC 应显示干净的每碱基质量和一个合理的比对率；一张平的火山图（没有显著基因）可能意味着
>   一个真实的无差异结果，*也*可能意味着实验设计功效不足（重复太少）。
> - **WGS：** 检查**平均覆盖度**（覆盖度偏低时流程会警告，默认 < 20×）和**比对率**（< 70% 时警告）—— 数值偏低
>   意味着你不应过度信任这些变异检出。

---

## 6. 如实说明的局限 —— 该抱有什么预期

- **状态：五台仪器里验证得最好的一台 —— 但也有如实的注意事项。** `nf-core/rnaseq` 和 `Wgs Germline Gatk` 都是
  **真实的、已建索引的、被运行得最多的 BioMate 流程**（RNA-seq 已在真实的公开数据集上、于 AWS Batch 上端到端
  地跑过；WGS 胚系是一条 BioMate 精心构建的、与目录精确匹配的 GATK4 流程）。`nf-core/ampliseq` 是一条真实的
  nf-core 流程，但 BioMate 专门的运行证据较少 —— 请在你的数据上确认。
- **连接器的标签只是一个路由提示，不是一个确切的工作流。** BaseSpace 连接器会把运行的*实验类型*映射到一个
  内部标签；BioMate 会把你的 Launch 路由到上面那条真实的目录流程。如果运行的实验类型是空白 / 标错了，连接器会
  回退到一个**通用 FASTQ** 处理器，而它可能不会路由到某条特定流程 —— 所以那种情况下，请**你自己说明文库
  类型**。
- **云端数据驻留由你负责。** BaseSpace 数据会离开你所在机构的系统（它在 Illumina 的云里）。对于受限 / 患者
  数据，请在连接**之前**确认这在你的治理规范下是可接受的 —— 那个数据驻留徽标正是为此而显示的。
- **连接 ≠ 数据在流动。** 输入 API 密钥能让 BioMate 检查 / 存储这个连接；但还必须有一个云端轮询带着你的密钥
  运行起来，已完成的运行才会出现。如果没有任何事件冒出来，那个轮询就是第一个要检查的地方（T6）。
- **这些是真实的、重量级的云端运行。** WGS 尤其需要大内存，可能要跑好几个小时。不要盲目地启动 —— 先把输入和
  基因组版本检查好。
- **体细胞 / 肿瘤需要另一条流程。** `Wgs Germline Gatk` **只做胚系**；对于肿瘤样品，请向它要 `nf-core/sarek`。

---

## 7. 下一步去哪儿

| 你想… | 去哪儿 |
|---|---|
| 连接 BaseSpace（API 密钥 + 轮询、数据驻留） | **教程六** |
| 理解那份三标签页报告和质控闸门 | **教程三** |
| 查看 VCF / BAM 以及其他输出 | **教程五** |
| 测量几个基因、而不是全基因组范围 | **qPCR 教程**（`qpcr-quantification.md`） |
| 在肿瘤样品里做变异检测 | 向它要 **`nf-core/sarek`** |

习惯是：**连接 BaseSpace（留意云端数据驻留）→ Launch（启动）一次已完成的运行 → 确认它路由到了 rnaseq /
WGS-GATK / ampliseq → 设好基因组版本或样品分组 → 运行 → 读倍数变化或 VCF，并检查质控 / 覆盖度。**

---

## 8. 关键术语

| 术语 | 含义 —— 以及你为什么要在意 |
|---|---|
| **FASTQ** | 测序仪的输出：读段（A/C/G/T）+ 每碱基质量。双端 = R1 + R2（两个都要带上）。 |
| **Phred / 质量分数** | 仪器对每个碱基有多大把握。质量低 → 触发修剪 / 质控标记。 |
| **BaseSpace** | Illumina 的**云**平台，测序仪往这里上传。**云端数据驻留 —— 数据会离开你的机构。** |
| **实验类型（Experiment type）** | 这次运行的文库种类（RNA、WGS、扩增子……）。决定用哪条流程。 |
| **RNA-seq / nf-core/rnaseq** | 在全基因组范围测量基因表达；做这件事的标准、经过测试的流程。 |
| **变异检测 / VCF** | 找出一个基因组相对于参考的不同之处；VCF 列出这些变异。 |
| **GATK4 最佳实践** | 社区标准的胚系变异检测链（本篇的 WGS 流程）。 |
| **log2 倍数变化 / FDR** | RNA-seq 结果术语：变化幅度（+1 = 翻了一倍）和可信度（FDR 越小越强）。 |
| **覆盖度（深度）** | 多少个读段覆盖每个位置；太低 → 不要信任变异检出（< 20× 时警告）。 |
| **16S 扩增子** | 通过测序一个标记基因来做微生物组谱分析；有谁在场、各占什么比例。 |

---

_依据：`biomate-connector/lab_instruments/illumina_basespace_connector.py`（`detect_workflow_from_run`：实验
类型 → 工作流路由）以及 BioMate 目录条目 `nf-core/rnaseq`、`Wgs Germline Gatk`、`nf-core/ampliseq` —— 均已通过
工作流搜索确认（WGS 为一个精确的高置信度匹配）。配套：教程三、四、五、六。_
