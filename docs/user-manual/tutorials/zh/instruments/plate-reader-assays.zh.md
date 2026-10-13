# 仪器教程 —— 酶标仪 → 剂量-反应、IC50 与检测定量

> **适合谁读：** 任何使用微孔板酶标仪（BMG FLUOstar/CLARIOstar/PHERAstar、BioTek/Agilent Synergy、
> Molecular Devices SpectraMax、Tecan Spark、PerkinElmer EnSpire）、并希望把满板的数字变成
> **"我这个化合物的 IC50/EC50 是多少"**、**"每个孔里有多少待测物（ELISA）"** 或 **"反应速率是多少"** 的
> 人 —— 不需要编程。
> **用时：** 阅读约 10 分钟；运行很快（在一个小表格上做曲线拟合，不是重量级流程）。
> **它在教程中的位置：** 教程六（T6）讲的是如何*连接*一台酶标仪，让它的文件进入 BioMate。本篇讲**这些数据
> 驱动的是什么分析、怎么跑、怎么读。**

---

## 1. 这台仪器产出什么

酶标仪会测量一块 96 孔或 384 孔板上每个孔里的一个信号。这个信号是以下之一：

- **吸光度（光密度，OD）** —— 例如比色法 ELISA 用的 OD450，或测细胞密度用的 OD600。
- **荧光** —— 一种染料或报告基因发光；越亮 = 你所测的东西越多。
- **发光** —— 例如 CellTiter-Glo（CTG）活力检测，其中光量 ∝ 活细胞数。

它可以**读一次**（终点法），也可以**随时间反复读**（动力学法）。软件（Gen5、MARS、SoftMax Pro、
SparkControl……）会导出一个 `.csv`/`.txt`/`.xlsx` 的"孔 × 数值"网格，通常还带一个表头，注明波长、读取类型
和板型。

**一板原始数字不是答案。** 生物学信息来自对这些数字*拟合一个模型*：拟合一条**剂量-反应曲线**得到 IC50、拟合
一条**标准曲线**把 ELISA 信号换算成浓度，或者从动力学斜率得出一个**速率**。这个拟合，就是 BioMate 要跑的
分析。

---

## 2. 它驱动的 BioMate 分析（以及为什么）

BioMate 跑什么，取决于这块板*是什么*：

### 2a. 剂量-反应 / IC50 / EC50（最常见）

你在若干个浓度（一个稀释系列）上测试了一个化合物，并测了反应。你想知道能产生半数最大效应的那个浓度。

→ **`Dose Response`**（BioMate 的 `biochemistry`（生物化学）领域）：拟合一条**四参数逻辑斯谛（4PL / Hill）**
曲线 —— 或者对不对称曲线拟合 5PL —— 并报告 **IC50**（用于抑制）或 **EC50**（用于激活）。关键输入：`data`（你的
CSV/TSV）、`concentration_col` 和 `response_col`（哪两列分别是剂量和信号）、`model`（`LL.4` = 4PL，`LL.5` =
5PL），以及 `response_type`（`inhibition` → IC50，`activation` → EC50）。

*为什么要一条曲线、而不只是一个数：* 单个孔给不出 IC50 —— 效力是反应随剂量变化的那个*形状*。4PL 拟合把这个
形状总结成了几个可解读的数字（上平台、下平台、斜率、IC50）。

### 2b. 对整板做命中筛选（HTS）

你筛选了许多化合物（每孔一个，外加若干对照列），想知道哪些是"命中"，以及这块板本身质量好不好。

→ **`Hts Plate Qc Hit Calling`**（`drug_discovery`（药物发现））：接收原始板信号 + 对照，计算 **Z 因子 /
Z′ 因子**（一个 0–1 的检测质量分数 —— 见 §5），归一化为**% 活性 / 抑制率**，套用一个命中阈值，并在存在重复浓度
数据的地方拟合 4PL 剂量-反应。关键输入：`plate_data_json`、`hit_threshold_pct`（默认 50）、`hit_direction`
（`inhibition`/`activation`）、`min_z_prime`（默认 0.5）。

### 2c. 酶动力学 / ELISA / 活力检测

| 你做的是什么 | BioMate 提供的工作流 |
|---|---|
| 酶动力学读数（速率、Km、Vmax） | **`Analyze Enzyme Kinetics Assay`**（`biochemistry`） |
| 细胞活力（MTS/MTT/CTG）→ IC50 / GI50 | **`Dose Response`**（拟合活力 vs. 剂量） |
| ELISA / 免疫测定（信号 → 浓度） | 通过剂量-反应 / 酶动力学路径做标准曲线拟合（见 §6） |
| 自动化的多步药物反应处理 | `gdr_automated_drug_response_pipeline`（`pharmacology`（药理学）） |

> **先讲一句实话：** 酶标仪*连接器*会根据文件 / 文件夹名和表头（波长、"kinetic"、"MTT"、"IC50"、"ELISA"……）
> 来猜检测类型，并给文件打上一个内部路由标签。这个标签是一个**提示（hint）** —— 当你 Launch（启动）时，说一句
> 这是什么检测（例如"这是一个细胞活力剂量-反应"），好让 BioMate 路由到上面那个对的拟合。验证状态见 §6。

---

## 3. 开始前 —— 先把数据弄进来（见 T6）

- **连接酶标仪（适合经常使用的场景）。** 在 **Connectors → Instruments（连接器 → 仪器）** 里注册一台
  **Plate reader（酶标仪）**；让你的管理员把它的文件监听器指向你的 Gen5/MARS/SoftMax Pro 导出文件夹。跑完的
  板会出现为 **New data events（新数据事件）**。完整步骤见**教程六**。
- **手动上传（一次性）。** 导出一个 `.csv`，从 Data（数据）区把它带进来。完整步骤见**教程四**。

**你的文件需要什么**，才能做剂量-反应：一列**浓度**（你的剂量）和一列**反应**（信号），且稀释系列的排布要让
BioMate 能把剂量和反应配对起来。要知道你的**单位**（例如 µM、nM），以及效应是**抑制还是激活**。做整板筛选的
话，要把你的**阳性对照孔和阴性对照孔**也包含进来 —— Z′ 因子质控需要它们。

---

## 4. 一步步操作 —— 把它跑起来

<!-- CAPTURE route=/ ; state=New data events list showing a plate-reader event (assay type "dose response", vendor BMG, 96-well) with Launch + Dismiss ; focus=instrument-event ; note=show a plate-reader New-data event card: file name, vendor badge, assay-type + plate-format badge, Launch -->
*（待补图：一个酶标仪的 New-data 事件 —— 导出的文件、厂商徽标、"dose response"（剂量-反应）检测类型徽标、
板型，以及 Launch 按钮。）*

1. **从数据事件开始（或者直接提问）。** 点击 **Launch（启动）**（会打开一个预填草稿，此时还什么都不会跑），
   或者输入你的目标，例如 *"Fit a 4-parameter dose–response and report the IC50 for this inhibition assay;
   concentration in column 'dose_uM', signal in column 'pct_inhibition'."*（为这个抑制实验拟合一条四参数
   剂量-反应曲线并报告 IC50；浓度在 'dose_uM' 列，信号在 'pct_inhibition' 列。）
2. **确认工作流。** 确认面板打开的是你想要的那个拟合 —— IC50/EC50 对应 **Dose Response**、筛选板对应
   **Hts Plate Qc Hit Calling**、速率对应 **Analyze Enzyme Kinetics Assay**。不应是"undefined"；如果弄错了，
   就说清楚这是哪种检测。
3. **把它指向正确的列 / 设置：**
   - **`concentration_col`** 和 **`response_col`** —— 剂量和信号的确切列名（来自你的文件）。
   - **`model`** —— `LL.4`（4PL，通常的选择）或 `LL.5`（5PL，用于不对称曲线）。
   - **`response_type`** —— `inhibition`（→ IC50）或 `activation`（→ EC50）。
   - 做筛选板时：**`hit_threshold_pct`**、**`hit_direction`**、**`min_z_prime`**。
4. **接上板文件**（如果还没自动链接），然后点 **Confirm & Run（确认并运行）**（很快）。

<!-- CAPTURE route=/ ; state=Workflow panel pre-run for Dose Response, param strip showing concentration_col, response_col, model (LL.4), response_type (inhibition) ; focus=workflow-panel ; note=show pre-run dose-response panel: the column mappings + model + response_type, Confirm & Run -->
*（待补图：运行前的 Dose Response 面板 —— 浓度 / 反应列的映射、4PL 模型、抑制 / 激活的选择，以及
Confirm & Run。）*

---

## 5. 读懂结果 / 报告

打开 **After run（运行后）** 这一节（两个标签页 —— 见**教程三**）：

- **Summary（摘要）** —— 核心数字：
  - **IC50 / EC50** —— 产生半数最大效应的那个浓度。**IC50 越低 = 抑制剂越强效。** 按你的单位来读它（例如
    "IC50 = 120 nM"）。
  - **Hill 斜率** —— 曲线有多陡（反应随剂量变化得有多剧烈）。
  - 做筛选板时：**命中列表**和 **Z′ 因子**（板质量）。
- **Outputs（输出）** —— 拟合出的参数、曲线上的点，以及（对筛选而言）每个孔的 % 活性和命中标记，归在产生它们
  的那个步骤之下；可下载用于图表。
- **Reproducibility record（可复现记录）** —— 你用的模型、列和软件版本 —— 这样这次拟合就被记录下来了。

> **如何判断一个拟合（别只看 IC50）。**
> - **Z′ 因子**（筛选）：**> 0.5 = 一个极好、稳健的检测**；0–0.5 = 勉强；< 0 = 你的阳性对照和阴性对照互相重叠，
>   所以**不要相信那块板上的命中**。这是板筛选里最重要的那个质控数字。
> - **曲线形状：** 一个可信的 IC50，应落在你的数据点在上平台（无效应）和下平台（完全效应）**两端都有**的地方。
>   如果你最高的剂量都还没达到平台，那么报告出来的 IC50 是一个外推值 —— 把它当作"大于你的最高剂量"，而不是一个
>   精确值。
> - **重复：** 一个来自三复孔、误差棒很紧的 IC50 是可靠的；来自单点的，就只能作为参考。

---

## 6. 如实说明的局限 —— 该抱有什么预期

- **状态：可用，但尚未在真实数据上做过端到端验证。** `Dose Response`、`Hts Plate Qc Hit Calling` 和
  `Analyze Enzyme Kinetics Assay` 都是**真实的、已建索引的 BioMate 工作流**（已在目录中确认，带有真实的参数
  模式和质控设置）。但 BioMate 在开发站点上**没有**一次已记录在案的真实端到端酶标仪运行，而且酶标仪的覆盖已知
  是偏薄的。把结果当作*可用但未经测试*来对待：在你信任之前，先拿你第一个 IC50 去和你在 GraphPad/Prism 或你平时
  用的工具里算出来的值核对一遍。
- **连接器的标签只是一个路由提示，不是一个确切的工作流。** 监听器的内部检测标签（`dose_response`、
  `cell_viability_ic50`、`elisa_quantification` 等）并**不会**原样对应到目录 ID；BioMate 是通过匹配你的请求，
  把你的 Launch 路由到真实的拟合的。说明你的检测类型来把它扳对。
- **ELISA 没有自己专门的标准曲线工作流。** 一个 ELISA（通过标准曲线把信号 → 浓度）是靠复用剂量-反应 / 酶动力学
  的拟合来处理的，而不是一条量身定制的 ELISA 流程。原理上行得通，但请你自己确认一下标准曲线的拟合和反算出来
  的浓度。我们如实说明，而不是夸大其词。
- **你必须映射好列。** 工作流需要知道**哪一列是剂量、哪一列是反应** —— 它并不能可靠地猜出板的排布。如果你导出
  的是一个原始的孔网格、而不是整齐的剂量 / 反应两列，就先把它重整一下（或者让 BioMate 来做）。
- **对照上的垃圾数据会毁掉筛选质控。** 只有在你的阳性 / 阴性对照孔被正确标注、且是真实的时，Z′ 因子才有意义；
  标错的对照会给出一个误导性的质量分数。

---

## 7. 下一步去哪儿

| 你想… | 去哪儿 |
|---|---|
| 连接酶标仪，让运行自动到达 | **教程六** |
| 手动带进单个板文件 | **教程四** |
| 理解那份两标签页报告 | **教程三** |
| 筛选整板并对它做质控 | 向它要 **`Hts Plate Qc Hit Calling`** |
| 拟合酶动力学（Km/Vmax） | 向它要 **`Analyze Enzyme Kinetics Assay`** |
| 把一个命中推进到 ADMET / 安全性筛选 | **BioMate 药物发现（ADMET）流程**（见主运行教程 T3） |

习惯是：**Launch（启动）这个板事件 → 确认是对的那个拟合（剂量-反应 / 筛选 / 动力学）→ 映射好你的剂量列和
反应列 → 运行 → 读 IC50 并检查 Z′ / 曲线形状。**

---

## 8. 关键术语

| 术语 | 含义 —— 以及你为什么要在意 |
|---|---|
| **吸光度 / OD** | 一个孔吸收了多少光（例如 ELISA 的 OD450、测细胞密度的 OD600）。一种常见的板信号。 |
| **终点 vs. 动力学** | 读一次 vs. 随时间反复读。动力学读数能给出速率。 |
| **剂量-反应曲线** | 反应对剂量作图；它的形状定义了效力。单个孔给不出它。 |
| **IC50 / EC50** | 产生半数最大抑制 / 激活的浓度。**IC50 越低 = 越强效。** |
| **4PL / Hill（LL.4）** | 拟合到剂量-反应曲线上的四参数逻辑斯谛模型（上平台、下平台、斜率、IC50）。 |
| **Z 因子 / Z′ 因子** | 一个 0–1 的检测质量分数。**>0.5 = 极好**；<0 = 对照重叠，不要相信命中。 |
| **标准曲线** | 一个参考用的稀释系列，用来把 ELISA 信号换算成浓度。 |
| **Km / Vmax** | 酶动力学参数（底物亲和力 / 最大速率），来自一次动力学读数。 |

---

_依据：`biomate-connector/lab_instruments/plate_reader_connector.py`（检测类型 → 工作流路由）以及 BioMate 目录
条目 `Dose Response`（biochemistry）、`Hts Plate Qc Hit Calling`（drug_discovery）、
`Analyze Enzyme Kinetics Assay`（biochemistry）、`gdr_automated_drug_response_pipeline`（pharmacology）——
均已通过工作流搜索确认。配套：教程三、四、六。_
