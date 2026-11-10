# 仪器教程 —— 显微成像与病理影像 → 细胞分割、标志物定量与全片分析

> **适合谁读：** 任何使用**数字化切片扫描仪**（whole-slide imaging / 病理）、**共聚焦显微镜**，或
> **荧光显微镜**，想把图像变成**"细胞/细胞核在哪里、有多少个、每种标志物各表达多少"**的人 —— 不需要编程。
> **用时：** 约 14 分钟。
> **它在教程中的位置：** 教程六（T6）讲的是如何*连接*仪器、或以别的方式把文件送进 BioMate。这一篇讲的是
> **这些图像能驱动哪些分析、怎么运行、怎么读懂**，并且坦白地说清楚**哪些图像格式今天就能用、哪些还在路线图上。**

> **在真正点击运行之前，先读 §6。** 对成像任务来说，开头最该弄清楚的一件事，就是你手里**文件的格式**。
> 有好几种常见的显微镜、扫描仪厂商格式，BioMate 目前还读不了；把这类文件喂进去，得到的是报错或空结果，
> 而不是一个结论。§6 会逐一说明今天能跑什么、哪些还在路线图上。

---

## 1. 这些仪器产出什么

三台仪器都产出像素图像，但种类不同、尺度也不同：

- **荧光显微镜** —— 通常是**二维图像**，一个到几个通道（如 DAPI 核染 + 一两个标志物通道），常导出为
  **TIFF**、**PNG** 或 **JPEG**。这是成像里最简单的情形。
- **共聚焦显微镜** —— 光学切片**z 轴堆栈**（往往还是多通道、多时间点），保存为**厂商格式**：蔡司
  `.czi`、徕卡 `.lif`、尼康 `.nd2`、奥林巴斯 `.oir`。单个文件就可能装下一整个跨多通道的三维体数据。
- **数字化切片扫描仪（WSI）** —— **全片图像**：整张组织切片的吉像素级金字塔影像，保存为 Aperio `.svs`、
  滨松 `.ndpi`、3DHISTECH `.mrxs`，或国产扫描仪格式 `.kfb`（KFBIO）、`.sdpc`（SQRAY）。这类文件体量极大
  （常达数 GB），是逐块（tile）读取的，不会一次性全读进来。

**一张图像并不等于一次测量。** 要把图像变成"这个视野里有 4200 个细胞核；标志物 X 在其中 38% 的核里表达"，
需要先**分割**（勾出每个细胞或细胞核的边界），再**定量**（在每个边界内测量面积、形态和各通道强度）。这条
"先分割、再定量"的流程，正是 BioMate 要跑的 —— 而用哪条流程、甚至能不能打开你的文件，取决于*图像出自哪台
仪器、是什么格式*。

---

## 2. 这些图像驱动哪些 BioMate 分析（以及为什么）

### 2a. 细胞 / 细胞核分割（荧光与共聚焦单视野）

> **工作流：** `segment_cells_with_deep_learning`
> **路径：** `backend/biomni_workflows/nextflow/workflows/microbiology/segment_cells_with_deep_learning.nf`
> **关键输入：** `image_path`（待分割的图像）。

这是显微成像的核心工作流。它**用 Cellpose / Omnipose 系列的预训练模型，对荧光显微图像做深度学习细胞分割**
（取自工作流自身的描述），并用 scikit-image 做边界查找、读写和逐对象统计。流程会读入图像、找出对象边界、
给每个细胞/核标号，并汇总结果（对象计数与强度统计）。产出是一张**带标号的掩膜（mask）**外加一份汇总 ——
这正是用来数细胞、量标志物强度的原材料。

与之紧密相关的 **`segment_and_analyze_microbial_cells`**
（`…/nextflow/workflows/microbiology/segment_and_analyze_microbial_cells.nf`）做同样的分割，并额外**量化形态
学指标**（每个对象的大小与形状）—— 当你关心细胞*形态*、而不只是计数时，用它。

*什么时候用哪个：* 单张二维荧光视野 → 要计数/掩膜用 `segment_cells_with_deep_learning`，还要形态就用
`segment_and_analyze_microbial_cells`。共聚焦的 **z 轴堆栈**是三维体数据：见 §6 —— 它的厂商格式目前还读不了，
你需要先导出二维投影或 OME-TIFF。

### 2b. 多重标记组织 —— 一次完成分割并定量多个标志物

> **工作流：** `segment_and_quantify_cells_in_multiplexed_images`
> **路径：** `backend/biomni_workflows/nextflow/workflows/pathology/segment_and_quantify_cells_in_multiplexed_images.nf`
> **关键输入：** `image_path`、`markers_list`。

对于**多通道组织图像**（如多重免疫荧光 / CyCIF 式的 panel），这条工作流会分割细胞，再**逐标志物量化蛋白
表达水平**：读图、给细胞标号（分水岭 + 区域属性），并在每个细胞内测量每个标志物通道。当你的问题是*组织内
的单细胞标志物表达*、而不只是核计数时用它。请在 `markers_list` 里按通道顺序给出标志物/通道名。

### 2c. 全片成像（数字化切片扫描仪）

对于吉像素级的全片图像，登记在册的流程是 **`nf-core/mcmicro`** —— nf-core 的多重组织成像流程（照明校正 →
拼接/配准 → 分割 → 单细胞标志物定量）。*mcmicro 是 nf-core 流程，本仓库里并没有它的本地桩文件*（已确认：
`backend/biomni_workflows` 下无任何 `*mcmicro*` 文件）；其行为以已发布的 nf-core/mcmicro 文档为准。**关键在于，
mcmicro 要求输入是 OME-TIFF**，而非原始厂商 WSI —— 见 §6。

一个正在成形的仓库内替代方案是 **`wsi_he_nuclei_segmentation`**
（`backend/biomni_workflows/nextflow_nfcore/subworkflows/pathology/wsi_he_nuclei_segmentation/`）：一个仅供科研
用途的 H&E 预处理 + 核分割子工作流，它通过 **OpenSlide** 读入单张切片（Aperio `.svs` 与金字塔 OME-TIFF），对
组织分块并做背景/模糊 QC，再跑一个版权干净的 **Cellpose**（BSD-3-Clause）核模型，输出逐核表格与 QC 叠加图。
它**尚未在数据库注册**（因此今天还不能从对话里被路由到），并且是**仅供科研用途 —— 需病理医师复核**。这里
如实列出，是作为路线图能力，而非一键可用的产品路径（见 §6）。

| 你手里有什么 | BioMate 提供的工作流 | 今天能用吗？ |
|---|---|---|
| 单张二维荧光视野，计数/掩膜 | **`segment_cells_with_deep_learning`**（Cellpose/Omnipose） | ✅ TIFF/PNG/JPEG |
| 单视野，还要形态学 | `segment_and_analyze_microbial_cells` | ✅ TIFF/PNG/JPEG |
| 多通道组织，逐标志物表达 | `segment_and_quantify_cells_in_multiplexed_images` | ✅ OME-TIFF / 多通道 TIFF |
| 全片图像，多重单细胞 | **`nf-core/mcmicro`**（nf-core 文档） | ⚠️ **仅限 OME-TIFF**（厂商 WSI 受阻 —— §6） |
| H&E 切片，核分割 | `wsi_he_nuclei_segmentation`（OpenSlide + Cellpose，RUO） | 🛑 尚不可路由（路线图） |
| 共聚焦 z 堆栈（`.czi/.lif/.nd2/.oir`） | 可喂给上面的分割工作流 | 🛑 **暂无读取器 —— 路线图（B1）** |

---

## 3. 开始之前 —— 先把图像送进来（见 T6）

把仪器连上、让文件进入 BioMate，是**教程六**的事；本篇假定图像已经在你的 BioMate 数据区里（手动上传单个
文件见**教程四**）。文件进来之后，再回到这里运行分析。

**你需要先备好：**

- **一个可读格式的图像。** 这是成像任务的硬门槛 —— 见 §6。实践中，这意味着显微成像用**二维 TIFF / PNG /
  JPEG**，多重组织与全片工作用**（金字塔）OME-TIFF**。如果你手里只有厂商格式（`.czi`、`.lif`、`.nd2`、
  `.oir`、`.svs`、`.ndpi`、`.mrxs`、`.kfb`、`.sdpc`），请先转换（§6），否则运行无法进行。
- **多重标记组织还需：** 按通道顺序排列的**标志物/通道名列表**（`markers_list`）。
- 若打算以物理单位报告对象尺寸，记下**图像比例尺**（每像素对应多少微米）。

---

## 4. 一步一步 —— 运行它

1. **先确认格式（§6）。** 如果你的文件是厂商显微镜/扫描仪格式，第一件事就是把它转成 TIFF 或 OME-TIFF。
   仅这一步检查，就能省下最多的无效运行。
2. **从对话开始（或从预填好的草稿）。** 用大白话写明目标，如*"分割这张荧光 TIFF 里的细胞核并计数"*，或
   *"在这张多重 OME-TIFF 上分割并定量 CD3、CD8、PanCK 这几个标志物"*。BioMate 会在右侧面板打开匹配的工作流卡片
   （§2）；此时还没有运行。
3. **核对工作流名称。** 确认面板打开的是对的流程 —— 单视野分割用 `segment_cells_with_deep_learning`，多重
   组织用 `segment_and_quantify_cells_in_multiplexed_images`，整张切片用 `nf-core/mcmicro`。它必须显示一个真实
   名称，而不是 "undefined"；如果打开的是错的，重新表述你的目标。
4. **填写关键输入。** 把图像作为 `image_path` 附上；多重组织还要在 `markers_list` 里填上通道名。
5. **确认并运行。** 点击 **Confirm & Run**，在 Phases 页看着各阶段从*待运行 → 运行中 → 已完成*推进。单视野
   分割很快；整张切片的 mcmicro 运行则是重计算，可能耗时很久。

---

## 5. 读懂输出

打开 **After run**（运行后）区域（两个标签页 —— 见**教程三**）：

- **分割掩膜 / 带标号图像** —— 每个检测到的细胞或核都被画成一个独立的带标号对象。这是首要产出；把它叠加到
  原图上，核验边界是否贴合真实细胞（而非碎屑、也没有把成团细胞并到一起）。
- **对象 / 细胞表** —— 每个被分割对象一行，含位置、面积，以及（定量与多重工作流会给出的）**逐标志物强度**。
  这就是你用来计数和比较的东西，例如"N 个核；标志物 CD8 阳性占 X%"。
- **QC 汇总** —— 对象计数与强度统计；对 WSI 核分割子工作流，还会给出分块 / 背景 / 模糊叠加图，让你看清哪些
  分块是可用的。
- **可复现记录** —— 所用模型、参数、容器/版本与输出 —— 这是审计留痕。

> **好结果长什么样，又该当心什么。** 把掩膜叠到原图上：边界应当沿着一个个单独的细胞走。常见的失败是
> **欠分割**（几个相邻细胞被并成一个对象）与**过分割**（一个细胞被拆成好几个）—— 两者都会扭曲后续的每一个
> 计数。对象数非常少，通常意味着对比度/通道有问题，或用错了模型。标志物阳性率依赖于所用的强度阈值；报告时
> 请把阈值一并写明。

---

## 6. 诚实的边界 —— 格式就绪情况（请仔细读）

这是成像任务里最要紧的一节。**BioMate 的图像摄取是按格式设门槛的，好几种常见厂商格式目前还不支持。** 这与
设施资源清单里的 **B1** 缺口一致。

**今天就能跑（端到端可用）：**
- **二维荧光显微图像**，格式为 **TIFF / PNG / JPEG** → `segment_cells_with_deep_learning` /
  `segment_and_analyze_microbial_cells`。这是荧光显微镜那条扎实、可用的路径。
- **多通道组织**，格式为 **OME-TIFF**（或多通道 TIFF）→ `segment_and_quantify_cells_in_multiplexed_images`。
- **全片 / 多重** —— **仅当你的切片已经是 OME-TIFF 时** → `nf-core/mcmicro`。

**在路线图上 / 尚不能跑 —— 别以为这些今天就能打开：**
- 🛑 **厂商全片格式** —— Aperio `.svs`、滨松 `.ndpi`、3DHISTECH `.mrxs`，以及国产扫描仪格式 **`.kfb`（KFBIO）**
  与 **`.sdpc`（SQRAY）** —— 在 BioMate 里**没有生产级读取器（缺口 B1）**。原始 `.svs`/`.kfb`/`.sdpc`
  **今天并不能端到端运行**。mcmicro 需要 **OME-TIFF**；把厂商 WSI 转成 OME-TIFF（如用 bioformats2raw/raw2ometiff
  或 QuPath 导出）是 BioMate 之外的一步手工预处理。新建的仓库内子工作流（`wsi_he_nuclei_segmentation`）捆绑了
  OpenSlide，原则上能打开 `.svs` 与 OME-TIFF，但它**尚未在数据库注册（无法从对话路由）、未经端到端验证、且仅
  供科研用途** —— 请当作路线图,而非产品路径。
- 🛑 **共聚焦厂商格式** —— 蔡司 **`.czi`**、徕卡 **`.lif`**、尼康 **`.nd2`**、奥林巴斯 **`.oir`** —— 在 BioMate
  里**没有读取器（缺口 B1）**。这几种格式的共聚焦 z 堆栈今天无法直接摄取。要现在分析共聚焦数据，请先从采集
  软件里导出**二维投影或逐通道的 TIFF/OME-TIFF**，之后再套用上面的分割工作流。
- 🛑 **病理基础模型（B2）与 QuPath 集成（B4）** —— 分块/全片编码器（UNI、CONCH、Virchow2、Prov-GigaPath）与
  基于 QuPath 的全片分析**都尚未具备**；BioMate 今天的基础模型面向的是转录组。全片级嵌入、肿瘤含量 QC、
  IHC/抗原打分都在路线图上,尚不可用。

**分割工作流本身的状态：** 这里点名的显微成像与病理分割工作流都是**真实、已建索引的工作流**（🟡 **已注册**），
但它们在*你这种*数据类型上的端到端可运行性,**在开发环境上尚未验证** —— 目前没有任何真实的端到端成像运行记录。
在用一张已知图像或你以往的分析核对过之前,请把结果当作**实验性的**;不要把 BioMate 给出的成像数字当作已验证
结论来报告。

**与格式无关的科学注意事项：**
- 分割质量取决于模型与图像质量;务必叠加核验掩膜（§5）。
- 标志物阳性率取决于强度阈值 —— 报告时写明阈值。
- WSI 核分割子工作流明确**仅供科研用途,非诊断器械;须经病理医师复核**。

---

## 7. BioMate 还提供（广度）

除上述三台仪器外,BioMate 还带有一套更宽的成像与空间分析工具箱,设施可一并取用：

| 你想… | 工作流 / 工具 |
|---|---|
| 逐细胞量化形态（大小/形状） | `segment_and_analyze_microbial_cells` |
| 组织内逐标志物的单细胞表达 | `segment_and_quantify_cells_in_multiplexed_images` |
| 分析钙成像时间序列 | `analyze_calcium_imaging_data`（`…/nextflow/workflows/bioengineering/`） |
| 用 U-Net 分割体 / 医学图像 | `segment_with_nn_unet`（nnU-Net；`…/subworkflows/bioimaging/`） |
| 图像配准/对齐、度量相似性 | `register_images`、`calculate_similarity_metrics`、`create_segmentation_visualization`（`…/subworkflows/bioimaging/`） |
| H&E 全片核分割（RUO,路线图） | `wsi_he_nuclei_segmentation`（OpenSlide + Cellpose） |
| 分割之后的空间 / 单细胞分析 | BioMate 的单细胞与空间组学工作流（Scanpy/Seurat 系）可接收"细胞 × 标志物"表作为输入 |

底层工具箱都是版权干净的标准件：**Cellpose / Omnipose**（深度学习分割）、**scikit-image**（图像处理与区域
测量）、**OpenSlide**（厂商中立的 WSI 读取器）、**nnU-Net**（体数据分割）。

---

## 8. 接下来去哪

| 你想… | 去哪 |
|---|---|
| 把某台仪器的文件送进 BioMate | **教程六** |
| 手动上传单张图像 | **教程四** |
| 读懂两标签页报告 | **教程三** |
| 跨多重 panel 定量标志物 | 索取 **`segment_and_quantify_cells_in_multiplexed_images`** |
| 分析整张切片（今天仅限 OME-TIFF） | 索取 **`nf-core/mcmicro`** |

养成的习惯：**先查格式（把厂商格式转成 TIFF/OME-TIFF）→ 让 BioMate 做分割/定量 → 核对工作流名称并附上图像
（以及标志物列表）→ 运行 → 叠加核验掩膜、读细胞表,并把结果当作实验性的。**

---

## 9. 关键术语

| 术语 | 含义 —— 以及你为什么要在意 |
|---|---|
| **分割（Segmentation）** | 勾出每个细胞或核的边界。后续的一切（计数、标志物强度）都取决于它是否正确。 |
| **Cellpose / Omnipose** | BioMate 所用的深度学习通用分割模型 —— 无需手工调阈值。 |
| **OME-TIFF** | 一种厂商中立的金字塔图像格式。多重/全片流程真正读的就是它 —— 把厂商文件转成这种。 |
| **全片图像（WSI）** | 整张切片的吉像素级扫描（`.svs/.ndpi/.mrxs/.kfb/.sdpc`）。逐块读取;厂商格式须先转换。 |
| **z 堆栈** | 共聚焦的三维体数据（光学切片）。厂商 `.czi/.lif/.nd2/.oir` 暂不可读 —— 先导出投影/TIFF。 |
| **标志物 / 通道** | 一个荧光通道 = 一种被染的蛋白。`markers_list` 告诉定量工作流每个通道是什么。 |
| **多重成像（Multiplex）** | 同一张组织切片上成像多个标志物;`segment_and_quantify_cells_in_multiplexed_images` / mcmicro 会逐细胞测量全部。 |
| **仅供科研用途（RUO）** | 非诊断器械;任何临床解读前,结论须经专家（病理医师）复核。 |

---

_依据真实工作流文件：`backend/biomni_workflows/nextflow/workflows/microbiology/segment_cells_with_deep_learning.nf`
（参数/步骤/输出）、`…/microbiology/segment_and_analyze_microbial_cells.nf`、
`…/pathology/segment_and_quantify_cells_in_multiplexed_images.nf`（`image_path`、`markers_list`），以及仓库内
`…/nextflow_nfcore/subworkflows/pathology/wsi_he_nuclei_segmentation/`（OpenSlide + Cellpose,RUO,尚未
DB 注册）；`nf-core/mcmicro` 是未在本仓库建桩的 nf-core 流程（以 nf-core 文档为准）。状态以及 B1/B2/B4
摄取/基础模型缺口,与 `docs/20260920_HOSPITAL_INSTRUMENT_RESOURCE_INVENTORY.md` 一致（§1 数字化切片扫描仪 /
共聚焦 / 荧光显微镜各行;§4 的 B1 读取器缺口）。全文未记述或暗示任何仪器连接器、驱动或自动路由 —— 连接相关
内容交由教程六。配套：教程三、四、六。_
