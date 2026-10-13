# 仪器教程 —— 体细胞 / 肿瘤测序 → 肿瘤-正常配对变异检测（nf-core/sarek），附 Sanger（.ab1）说明

> **适合谁读：** 任何在做**癌症**样本测序的人 —— 同一位患者的**肿瘤**标本加上一份**配对正常样本**（血液或
> 癌旁正常组织）—— 希望把这些读段变成肿瘤所获得的**体细胞**突变清单：那些只在癌细胞中出现、而非遗传而来的
> SNV 和小插入缺失。不需要编程。
> **用时：** 阅读约 12 分钟；一次真实的体细胞分析运行需要几十分钟到许多小时（重量级云端计算 —— 全基因组
> 肿瘤/正常配对是 BioMate 所跑的分析里最吃资源的几类之一）。
> **它在教程中的位置：** 教程六（T6）讲的是**如何把你的肿瘤与配对正常 FASTQ 送进 BioMate**。本篇讲**这些
> 读段驱动的是什么分析、怎么跑、怎么读。** 它与**胚系 / RNA-seq 测序教程**
> （[`basespace-sequencing.md`](../../instruments/basespace-sequencing.md)）互为补充 —— 那一篇讲 RNA-seq、
> 胚系 WGS/WES 和 16S；**本篇只讲肿瘤/正常体细胞这条路。** 在相信任何结果之前，请先读 §6 的状态说明：
> 体细胞检测目前在 BioMate 上是**已注册、但尚未端到端验证**的状态。

---

## 1. 这台仪器产出什么

癌症测序研究用的是和其他 DNA 文库一样的 NGS 测序仪（Illumina、MGI……），但它的**实验设计是配对的**。对每一位
患者，你要测**两份**（或更多）文库：

- 一份**肿瘤**样本 —— 从癌组织（新鲜/冻存或 FFPE 石蜡）中提取的 DNA，以及
- 一份**配对正常**样本 —— 来自同一患者健康细胞的 DNA（通常是血液，或组织学上正常的癌旁组织）。

每份文库从仪器下机都是 **FASTQ** 读段 —— 数百万个片段的 A/C/G/T 序列，每个碱基带一个 **Phred** 质量分数；
双端测序为每份样本产生两个文件（**R1** 和 **R2**）。肿瘤文库通常会测到**比胚系工作更高的深度**（这样即便某个
突变只存在于一小部分肿瘤细胞中也能被看到），而配对正常样本则作为该患者的基线一同测序。

**配对正常样本正是关键所在。** 一个肿瘤基因组里混着两类截然不同的变异：患者生来就有的**胚系**变异（在正常
样本里也有），以及癌症**后天获得**的**体细胞**变异（只在肿瘤里有）。把肿瘤和它自己的配对正常样本相比，正是
为了能**扣掉胚系背景**、只留下体细胞事件 —— 也就是这个癌症真正的生物学。这个"相减"的工作由下面的流程来做；
光靠原始读段是做不到的。

---

## 2. 它驱动的 BioMate 分析（以及为什么）

肿瘤/正常这种设计会路由到一条**和胚系流程不同的流程**。胚系 WGS/WES 由 `Wgs Germline Gatk` 负责（见
[`basespace-sequencing.md`](../../instruments/basespace-sequencing.md) §2b）—— 那条流程是拿一个基因组去比
参考序列，**不适合**癌症，因为它根本没有"配对正常样本可供相减"这个概念。

对于肿瘤/正常癌症基因组学，BioMate 会路由到 **`nf-core/sarek`**
（`backend/biomni_workflows/nfcore/sarek/main.nf`）—— 社区标准的 nf-core 流程，同时支持胚系**和**体细胞变异
检测。做体细胞工作时，它以 `analysis_type = somatic` 运行，并使用一个肿瘤感知的检测器（**Mutect2**）。它的
各个阶段是：

1. **预处理（Preprocessing）** —— `FastQC` 读段质控、`MarkDuplicates` 去重、GATK **BQSR**（碱基质量重校正），
   逐样本进行。
2. **比对（Alignment）** —— `BWA-MEM2` 把读段比对到参考基因组 → 每份样本一个排好序、建好索引的 **BAM/CRAM**。
3. **变异检测（体细胞）** —— 在 `tools = mutect2` 下，**GATK Mutect2** 拿肿瘤对它的配对正常样本做比较，报出
   **体细胞** SNV 和小插入缺失。sarek 还可以在同一对样本上额外跑 **Strelka2**（体细胞 SNV/indel）、**Manta**
   （结构变异）和 **CNVkit**（拷贝数）。
4. **注释（Annotation）** —— **VEP**（或 ANNOVAR）为每个变异加上功能后果（落在哪个基因、编码影响）和人群频率。
5. **报告（Report）** —— 一份 **MultiQC** HTML、变异统计，以及（在配置了的情况下）一份 **TMB/MSI** 概要
   （肿瘤突变负荷 / 微卫星不稳定性，两个都是有临床意义的癌症标志物）。

*为什么是一条流程、而不是一个检测器：* 从配对读段走到一个可信的**体细胞**变异集，需要把去重、重校正、比对、
肿瘤-对-正常检测、过滤和注释正确地串起来 —— 而"肿瘤对正常"这一步本身正是去掉胚系背景的地方。nf-core/sarek
就是为此而生、经过检验的那条社区链。

### 输入的样子 —— 肿瘤/正常样品表

sarek 的 `input` 是一份**样品表 CSV**，它按患者把每份肿瘤和它的正常样本配起来。BioMate stub 里真实的列是：

```
patient,sample,status,fastq_1,fastq_2
P001,P001_N,0,/data/P001_normal_R1.fastq.gz,/data/P001_normal_R2.fastq.gz
P001,P001_T,1,/data/P001_tumour_R1.fastq.gz,/data/P001_tumour_R2.fastq.gz
```

- **`patient`** —— 把一份肿瘤和它的正常样本归到一起的患者 ID（两行都是 `P001`）。
- **`status`** —— **`0` = 正常，`1` = 肿瘤**（就是这个标志告诉 sarek 谁是谁）。
- **`fastq_1` / `fastq_2`** —— 这份文库的 R1 / R2 FASTQ。

| 设计 / 目标 | sarek 怎么跑 |
|---|---|
| **肿瘤 + 配对正常**（标准癌症设计） | `analysis_type = somatic`、`tools = mutect2`（可再加 `strelka`、`manta`、`cnvkit`） |
| **仅肿瘤**（没有配对正常可用） | `analysis_type = tumor_only` —— 更依赖人群 panel；特异性较低、胚系残留更多 |
| **全外显子 / 靶向 panel**，而非全基因组 | 设 `wes = true` 并提供 panel 的 **`intervals`** BED 文件 |
| 胚系（遗传）变异，不是癌症设计 | **不用这条流程** —— 用 `Wgs Germline Gatk`（见胚系测序教程） |

> **先把丑话说前头 —— 请读 §6。** 体细胞这条路**能路由**、也有**真实的参数规格**，但 BioMate **还没有一条
> 经过端到端验证的体细胞"金标准"链**，而借助 **ASCAT/PURPLE** 做肿瘤**纯度/倍性**估计是一项**计划中的升级
> （U13），尚未接入路由。** 在你拿已知病例核对过之前，请把体细胞结果当作*实验性的*。不要把 BioMate 的体细胞
> 变异集当成已验证的结果去报告。

---

## 3. 开始之前 —— 把数据送进来（见 T6）

本篇**不**讲如何连接测序仪；连接这件事统一在**教程六**里讲。一句话：**一旦你的肿瘤与配对正常 FASTQ 进了
BioMate** —— 无论是从数据区手动上传（教程四），还是经由你们单位用的任何途径到达（教程六）—— 下面的步骤都
是一样的。

**你必须准备好的东西：**
- **每一对的两份都要带齐：** 既要**肿瘤** FASTQ，*也*要**配对正常** FASTQ，每份双端文库的 R1 和 R2 都要有。
- **哪个文件是哪个** —— 你的肿瘤-对-正常标注，好让样品表的 `status` 列填对。把肿瘤和正常搞反会让整个分析反向。
- 一个**参考基因组**版本 —— `GRCh38`（默认）、`GRCh37`，小鼠则用 `GRCm38`。BioMate 可以提供标准人类参考序列。
- 做**外显子/panel** 时：描述你捕获区域的 **`intervals`** BED 文件（并设 `wes = true`）。

---

## 4. 一步步跑起来

<!-- CAPTURE route=/ ; state=Workflow panel pre-run for nf-core/sarek, somatic mode, param strip showing analysis_type=somatic, tools=mutect2, genome=GRCh38, samplesheet with a tumour+normal pair ; focus=workflow-panel ; note=show the sarek pre-run card: workflow name nf-core/sarek, genomics domain badge, param strip (analysis_type, tools, genome), Confirm & Run -->
*（待补图：sarek 运行前面板 —— 流程名 `nf-core/sarek`、genomics 领域徽标、参数条显示
`analysis_type = somatic`、`tools = mutect2`、`genome = GRCh38`，以及"确认并运行"按钮。）*

1. **直接提出需求（或点卡片）。** 说明这是**体细胞 / 肿瘤-正常**，例如：*"用 nf-core/sarek 对这份肿瘤和配对
   正常样本做体细胞变异检测，用 Mutect2，比对 GRCh38。"* 明确说出*肿瘤 + 配对正常*，正是把它引向体细胞路、
   而不是胚系路的关键。
2. **核对流程。** 确认面板打开的是 **`nf-core/sarek`**（不是"undefined"，也不是 `Wgs Germline Gatk`）。领域
   徽标应为 genomics。
3. **搭好 / 核对样品表。** 确保每位患者都**既有** `status = 0`（正常）**又有** `status = 1`（肿瘤）两行，并
   指向正确的 FASTQ（§2）。这个配对是最重要的一项输入。
4. **设好关键参数：**
   - `analysis_type = somatic`（若你确实没有配对正常，则 `tumor_only`），
   - `tools = mutect2`（若还想要 SNV 互相印证、结构变异或拷贝数，再加 `strelka`、`manta`、`cnvkit`），
   - `genome = GRCh38`（或你的版本），
   - 做 panel/外显子：`wes = true` 并附上 `intervals`。
5. **确认并运行。** 点"确认并运行"。预期是一次**又长又重**的云端运行（全基因组肿瘤/正常非常吃资源 —— 内存
   上限 `max_memory = 128 GB`）。在 Phases 标签页里看各阶段 *pending → running → completed* 地推进，并让运行
   中的任何**质控门（QC gate）**暂停并报告，而不是悄悄放行（见教程三）。

<!-- CAPTURE route=/ ; state=Workflow panel running for nf-core/sarek, phase cards (Preprocessing, Alignment, Variant Calling, Annotation, Report) with Variant Calling running ; focus=workflow-panel ; note=show the sarek pipeline mid-run with the somatic Variant Calling phase in the running state and the overall running badge -->
*（待补图：sarek 流程运行中 —— 预处理 / 比对 / 变异检测 / 注释 / 报告 这几张阶段卡片，其中体细胞"变异检测"
阶段处于运行状态。）*

---

## 5. 读结果 / 读报告

打开 **After run（运行后）**区（两个标签页 —— 见**教程三**）：

- **Summary（概要）** —— 体细胞变异的总数，以及最有意义的那几个。这些是肿瘤*获得*的突变（胚系已经用配对
  正常样本扣掉了），按**基因**、**后果**（如错义、终止获得）以及（如有）驱动基因/标志物注释来读。
- **Outputs（输出）** ——
  - 一个注释过的**体细胞 VCF**（头牌文件：每个变异的位置、参考碱基 vs. 变异碱基、**变异等位基因频率 /
    VAF** —— 有多少比例的肿瘤读段带着它 —— 以及 VEP 后果），
  - 肿瘤和正常各自重校正后的 **BAM/CRAM** 比对文件，
  - 如果你跑了 Manta/CNVkit，还会有结构变异 / 拷贝数输出，
  - **MultiQC** 报告，以及（配置了的话）**TMB/MSI** 概要。
  都可下载用于作图。
- **可复现记录（Reproducibility record）** —— 基因组版本、所用检测器及其过滤条件、工具版本，以及带校验和的
  输出 —— 这份审计轨迹让一个癌症基因组学结果在论文或肿瘤多学科会诊（tumour board）上站得住脚。

预览：VCF 预览为变异表格；**BAM/CRAM** 为下载 / 交互式（暂无内嵌的基因组浏览器轨道 —— 见教程五）。

> **什么样算好、要盯什么。**
> - **这里深度比胚系工作更要紧** —— 体细胞灵敏度取决于把肿瘤测得够深、能看到低频突变；相信一个*阴性*结果
>   之前先查肿瘤覆盖度。
> - **肿瘤纯度低会把突变藏起来。** 一份大部分是正常组织的标本会稀释肿瘤信号，真正的体细胞变异就掉到检测器
>   阈值以下了。纯度/倍性估计（ASCAT/PURPLE）正是用来纠正这一点的 —— 而它在这里是一项**待上线的升级**
>   （U13，§6），所以在它落地之前，对 VAF 和任何拷贝数结果都要谨慎解读。
> - **肿瘤/正常搞反** —— 如果体细胞变异集大得不合常理、而且看着像胚系，先确认 `status` 列没有填反。

---

## 6. 诚实的边界 —— 该有什么预期（请仔细读）

- **状态：🟡 已注册，尚未端到端验证。** `nf-core/sarek` 是一条**真实的流程**，体细胞这条路也**能用真实的参数
  规格路由** —— 但 BioMate **没有记录在案的体细胞"金标准"链**：在开发环境上没有一次针对已知肿瘤/正常病例、
  跑通整条 读段→体细胞 VCF 路径的端到端运行。这一点和配套教程里那些已验证的胚系、RNA-seq 流程不同。
  **请把每一个体细胞结果都当作实验性的**，在报告之前拿已知病例或你以往的分析核对过。
- **肿瘤纯度/倍性（ASCAT/PURPLE）是计划中的升级，尚未上线。** 准确的体细胞解读 —— 尤其是拷贝数、VAF 校正和
  克隆性 —— 需要一个纯度/倍性估计。那套路由（**U13**）**还没接进来**。没有它，VAF 是未经校正的，拷贝数结果
  也应当看作暂定值。
- **这是靠扣胚系来做的，所以要出最好的结果，配对正常样本不可或缺。** `tumor_only` 模式是有的，但没有患者特异
  的正常样本就只能依赖人群 panel、残留的胚系漏得更多、特异性更低。能有配对正常就一定要给。
- **把配对关系弄对。** `status` 列（0 = 正常，1 = 肿瘤）和共用的 `patient` ID 驱动着整个比较。标错的一对会悄无
  声息地把结果反过来 —— 不报错，只是生物学是错的。
- **这些是真实、重量级的云端运行。** 全基因组肿瘤/正常需要大内存，可能跑上好几个小时。别试探性地乱启动 ——
  先确认好样品表、基因组版本和检测器。
- **FFPE 和低投入量的注意事项同样适用。** FFPE 来源的肿瘤 DNA 带有脱氨基假象，会冒充低 VAF 的体细胞 SNV；
  这里标准的 sarek 默认**不**做 FFPE 专门的假象过滤 —— 对 FFPE 材料上低频的 C>T/G>A 变异要格外小心地解读。
- **不声称任何连接器/自动路由。** FASTQ 是*怎么*到达的不在本篇范围（教程六）；本篇假设它们已经在 BioMate 里了。

---

## 7. Sanger 测序（.ab1）—— 诚实的状态：尚不支持

有些单位还会运行一台 **Sanger**（毛细管）测序仪，它为每条读段产出一个 **`.ab1` 色谱图（chromatogram）** ——
那种经典的四色峰图，用于单扩增子确认、质粒/插入片段核对以及变异验证。

**BioMate 目前还不能分析 `.ab1` 色谱图。** 没有任何工作流能读取一条峰图、对它做碱基识别或质量修剪，也不能把
读段拼成一致序列/重叠群（consensus/contig）。这是一个**已知的缺口**，记录为路线图条目 **B5**（一条基于
**Tracy** 的链：色谱图修剪 → 一致序列 / 重叠群组装）。在 B5 上线之前：

- 请**不要**指望上传一个 `.ab1` 就能拿到结果 —— 没有可路由的流程，我们也不会假装有一个。
- 眼下，请在你惯用的桌面工具里确认 Sanger 峰图（例如色谱图查看器 / SnapGene / 本地跑 Tracy），只把下游的
  问题带给 BioMate（例如"这个已确认的变异和体细胞检测结果对得上吗？"）。

一旦 B5 落地，本节会替换成真正的操作指南。

---

## 8. BioMate 还提供什么 —— 相关的基因组学与变异检测能力

除了体细胞这条路，BioMate 的**变异检测**领域（约 180 条工作流）和更广的基因组学目录，还能给一家做肿瘤基因组
的平台更多可用的东西：

| 你还想…… | 真实的 BioMate 资源 |
|---|---|
| 检测**胚系**（遗传）变异 —— GATK4 最佳实践 | **`Wgs Germline Gatk`**（已验证 —— 见 [`basespace-sequencing.md`](../../instruments/basespace-sequencing.md)） |
| 第二个体细胞检测器 / 轻量级的肿瘤-正常突变 + SnpEff 注释 | **`detect_and_annotate_somatic_mutations`**（`backend/biomni_workflows/nextflow/subworkflows/cancer_biology/`）—— 肿瘤 BAM vs. 正常 BAM，SnpEff |
| 检测肿瘤里的**结构变异**（融合、大片段重排） | sarek 里的 Manta（`tools = manta`） |
| **拷贝数**改变 | sarek 里的 CNVkit（`tools = cnvkit`） |
| 别的胚系/体细胞检测器（**DeepVariant、Strelka2、FreeBayes**） | 作为 sarek 的 `tools` 选项可用 |
| 在同一队列上定量肿瘤**基因表达**（RNA-seq） | `nf-core/rnaseq` → DESeq2（见胚系 / RNA-seq 教程） |
| 查一个基因的**癌症相关性 / 成药性** | **`query_opentarget`**（`…/subworkflows/database/query_opentarget.nf`）—— Open Targets |
| 把一串体细胞基因做通路富集 | 通路富集工作流（clusterProfiler/GSEA，系统生物学领域） |

注释步骤所依据的公共癌症参考资源包括 **COSMIC**、**dbSNP**、**gnomAD** 和 **ClinVar**（为 sarek 报出的变异提供
人群频率和临床意义）。

---

## 9. 接下来去哪儿

| 你想…… | 去哪儿 |
|---|---|
| 把肿瘤 + 配对正常 FASTQ 送进 BioMate | **教程六**（连接）/ **教程四**（手动上传） |
| 改跑胚系 / RNA-seq / 16S | 测序教程（[`basespace-sequencing.md`](../../instruments/basespace-sequencing.md)） |
| 搞懂三标签页报告和质控门 | **教程三** |
| 查看 VCF / BAM 输出 | **教程五** |
| 分析 Sanger `.ab1` 峰图 | **尚不支持** —— 路线图条目 **B5**（§7） |

习惯动作：**把肿瘤 + 配对正常 FASTQ 送进 BioMate → 要求用 nf-core/sarek 做体细胞检测 → 核对肿瘤/正常样品表
（status 0/1）、`analysis_type = somatic`、`tools = mutect2`、基因组版本 → 运行（预期是长任务）→ 读体细胞 VCF
和 VAF，在体细胞链与纯度（U13）得到验证之前，把结果都当作实验性的。**

---

## 10. 关键术语

| 术语 | 它是什么 —— 以及你为什么要在意 |
|---|---|
| **体细胞 vs. 胚系** | 胚系 = 遗传来的（正常样本里也有）；体细胞 = 肿瘤后天获得的（只在肿瘤里）。癌症基因组学关心的是体细胞那一组。 |
| **配对正常样本** | 患者自己健康细胞的 DNA，和肿瘤一起测，好把胚系扣掉。整个设计的核心。 |
| **样品表 `status`** | `0` = 正常，`1` = 肿瘤 —— 给每份文库配对、定向的标志。填错分析就反了。 |
| **Mutect2** | GATK 的肿瘤感知体细胞检测器 —— sarek 里默认的体细胞检测器。 |
| **VAF（变异等位基因频率）** | 带着某个变异的肿瘤读段所占的比例；VAF 低 = 突变只在少数肿瘤细胞里（或纯度低）。 |
| **肿瘤纯度 / 倍性** | 标本里到底有多少是肿瘤、以及它的拷贝数状态。由 **ASCAT/PURPLE** 估计 —— BioMate 一项待上线的升级（U13）。 |
| **TMB / MSI** | 肿瘤突变负荷 / 微卫星不稳定性 —— sarek 能概括的癌症标志物。 |
| **VCF** | 变异清单：位置、参考碱基 vs. 变异碱基、VAF 和功能注释。头牌输出。 |
| **`.ab1`** | 一个 Sanger 色谱图峰图文件。**BioMate 尚不能分析**（路线图 B5）。 |

---

_依据：`backend/biomni_workflows/nfcore/sarek/main.nf`（真实本地 stub —— 参数 `input` 样品表
`patient,sample,status,fastq_1,fastq_2`、`analysis_type ∈ {germline,somatic,tumor_only}`、`tools ∈
{mutect2,haplotypecaller,strelka,freebayes,deepvariant,cnvkit,manta}`、`genome`、`wes`/`intervals`；阶段为
预处理→比对→变异检测→注释→报告，含 TMB/MSI），以及
`backend/biomni_workflows/nextflow/subworkflows/cancer_biology/detect_and_annotate_somatic_mutations.nf`
（肿瘤 BAM vs. 正常 BAM + SnpEff）。状态依据 `docs/20260920_HOSPITAL_INSTRUMENT_RESOURCE_INVENTORY.md`：
体细胞 = 🟡 已注册，U13 ASCAT/PURPLE 纯度路由待接入，尚无已验证的体细胞金标准链；Sanger `.ab1` = 🛑 B5
（Tracy 修剪→一致序列/重叠群），尚不支持。配套：胚系 / RNA-seq 测序教程（`basespace-sequencing.md`）；
教程三、四、五、六。_
