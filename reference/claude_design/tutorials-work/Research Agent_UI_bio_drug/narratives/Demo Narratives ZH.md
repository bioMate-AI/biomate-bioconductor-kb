# BioMate 教程演示字幕 · 中文字幕脚本

本文件为 BioMate Research-Agent UI 三个核心教程的中文字幕脚本,用于中国市场推广演示。
字幕与教程引导卡(tour callout)的步骤一一对应,可直接用于视频后期叠加。

字幕约定:
- 每行不超过 16–20 个汉字,便于阅读
- 行内英文专有名词(cryoSPARC、ADMET、hERG、QC、IMRaD 等)保留原文,符合中文科研社区习惯
- 简体中文 · 科研语气 · 演示者向同行讲解

---

## 1 · CryoSPARC SPA · 3 分钟深度演示(`09d`)

> **场景背景。** 用户请求 BioMate 对 EMPIAR-10025 数据集运行单颗粒重构。本演示完整覆盖从原始视频帧到锐化三维密度图的全流程 —— 5 个阶段、23 个进程。

**[第 1 步 — 欢迎,屏幕中央]**
"你好。让我们一起完成一次完整的 cryo-EM 单颗粒分析。
不需要 CryoSPARC 经验 —— BioMate 会自动配置参数,你只需跟随演示。"

**[第 2 步 — 双视图、同一任务,Plan checklist]**
"BioMate 用两个视图展示同一次运行。
左侧是对话流:粘性 plan checklist + 带 speaker 标签的进度行。
右侧是工作流面板:阶段、步骤、参数、输出 —— 技术视图。
两侧实时同步。"

**[第 3 步 — 面板头部]**
"这里是 run header。工作流名称、状态徽章、实时进度条。
目前状态为 *idle* —— 工作流已加载,但尚未启动。"

**[第 4 步 — 5 阶段、23 步骤]**
"CryoSPARC SPA 分为 5 个阶段:
A. 运动校正与 CTF 估计;
B. 颗粒挑选;
C. 二维分类;
D. 三维重构;
E. 锐化与验证。
只有当前活动阶段自动展开,其他阶段折叠为状态芯片,保持面板简洁。"

**[第 5 步 — Phase A 内部]**
"当前活动阶段会自动展开,显示每一步的实时状态。
Phase A 运行 *MotionCor2* 做帧对齐,*CTFFIND4* 做散焦估计。
任意阶段都可以随时点开查看,不会打断运行。"

**[第 6 步 — 唯一主操作 · Confirm & Run]**(自动滚动到底部)
"参数已由 BioMate 从你的对话自动填充。
点击 *Confirm and run workflow* 即可向 AWS Batch 提交任务。
底部永远只有一个主按钮 —— 杜绝选择困境。"

**[第 7 步 — Phase A 已启动]**(自动滚动回顶部)
"任务已启动。状态徽章变为 *running*,进度条开始推进。
Phase A 的运动校正已在 Batch GPU 上执行。
小规模数据集通常耗时 3–6 分钟。"

**[第 8 步 — 每个步骤的实时进度]**
"Phase A 内,每个步骤都有实时状态芯片 —— queued、running、completed、failed。
MotionCor2 每处理完一帧,计数即时更新。
对话流与面板共用同一 SSE 流,双视图始终同步。"

**[第 9 步 — CTF 拟合质量门 trip]**
"CTF 估计中,BioMate 检测到 CTF 拟合分辨率低于阈值 —— 散焦扫描范围可能过窄。
QC gate 是质量护栏 —— 与其产出低质量重构,BioMate 选择暂停并提供修复方案。"

**[第 10 步 — Halt card · 接受或编辑修复方案]**
"Auto-loop 默认关闭,halt card 等待你决策。
BioMate 建议将散焦范围扩大到 0.5–4.0 微米。
你可以 *Accept* 采纳建议,*Edit* 自行调整数值,或 *Dismiss* 维持原样。
打开该阶段的 auto-loop 开关后,BioMate 会自动套用修复方案并重试,最多 3 次。"

**[第 11 步 — Gate 通过 · Phase A 完成]**
"你采纳了建议。Phase A 用新散焦范围重新运行,gate 通过,阶段标记为完成。
Phase B 自动启动。
每一次接受、编辑、重试都记录在 QC audit 报告中 —— 完全可审计。"

**[第 12 步 — 步骤输出实时落地]**
"注意每个已完成步骤行上的小文件芯片?
步骤一完成,输出文件即时出现 —— 文件名、类型图标、*view*、*download* 链接齐备。
无需等待整个运行结束。"

**[第 13 步 — Phase B · 颗粒挑选]**(滚动到当前展开阶段)
"Phase B。*Topaz* —— 神经网络颗粒拾取器 —— 扫描每张显微图寻找颗粒。
输出是每张显微图的坐标文件,作为二维分类的输入颗粒。"

**[第 14 步 — Phase C · 二维分类]**
"Phase C。颗粒被分入二维类。
垃圾类 —— 冰、碳膜边缘、聚集体 —— 被剔除。
只有定义清晰的视角进入三维。"

**[第 15 步 — Phase D · 三维重构]**
"Phase D。清洗后的颗粒进入 ab-initio 初步重构,随后做 homogeneous refinement。
输出是未锐化的三维密度图,以及用于分辨率估计的 half-map 对。
half-map 刻意分离 —— 这是 gold-standard FSC 的基础。"

**[第 16 步 — Phase E · 锐化与验证]**
"Phase E。B-factor 锐化、用 half-map 估计 FSC 分辨率、局部分辨率分布图。
B-factor 数值直接从 manifest 读取 —— 绝不推断。
结果即可用于发表、可直接提交至 EMDB 的密度图。"

**[第 17 步 — 23 步全部完成]**(滚动回顶部)
"23 步全部完成。状态切换为 *completed*。
重构在 GSFSC 0.143 下收敛于 3.21 Å —— 完全达到发表级别。"

**[第 18 步 — 输出可下载]**(滚动到底部)
"底部主按钮已变为 *Run again*。
向上滚动可看到 *View Results*、*Download All* 和自动生成的 Findings。"

**[第 19 步 — After-run 区块解锁]**(滚动到 After-run 头部)
"每次完成运行,面板底部都会新增一个 *After run* 区块 ——
Outputs、Findings、Methods、Parameters、Software、Citations、QC audit 一次性聚合。
有一个专门的教程详细介绍这部分。"

**[第 20 步 — 收束,屏幕中央]**
"这就是一次完整的 cryo-EM 运行 —— 从原始视频帧到锐化的三维密度图,19 个步骤。
真实运行需要 30–90 分钟;本教程为方便演示,加速了云端时间。"

---

## 2 · After-run 报告完整演示(`09f`)

> **场景背景。** 接续 cryo-EM 运行刚刚完成的状态。完整遍历 After-run 报告的全部标签页,中途插入一次内联预览。

**[第 1 步 — 介绍,屏幕中央]**
"运行刚刚完成。面板底部的 *After run* 区块由 7 个标签页组成,
覆盖 BioMate 产出的所有内容。
我们将逐一访问,标签内容随之切换。"

**[第 2 步 — After run 头部 + 下载报告]**(滚动到 After-run 区块)
"每次完成运行都会留下一个 *After run* 区块。
右侧的 *Download report* 链接将下面 7 个标签打包为一份结构化文档 ——
DOCX、Markdown、LaTeX 三种格式可选 —— 一键即可获得发表级输出。"

**[第 3 步 — 7 个标签概览]**
"7 个标签覆盖完整故事:
Findings、Outputs、Methods、Parameters、Software、Citations、QC audit。
顺序符合自然阅读顺序 —— 先叙述、再产物、再方法与可重复性、最后审计。"

**[第 4 步 — Findings 标签]**(自动切换到 Findings)
"Findings 标签以头条指标开篇 —— 3.21 Å 分辨率,
配 2–3 条要点说明,加一张数值表。
每个数字都从 manifest 读取,绝非生成。
若某项 finding 缺乏引用,BioMate 会标注为 author judgment。"

**[第 5 步 — Outputs 标签]**(自动切换到 Outputs)
"Outputs 标签按 phase + step 分组,每行一个文件。
*view* 内联预览,*download* 单文件下载。
顶部的 *Download all* 按钮打包全部为 ZIP。"

**[第 6 步 — 步骤侧也有输出]**(向上滚动到 phase list)
"无需等待报告才能取文件。
看上方面板任意已完成步骤行 —— 步骤一完成,输出芯片立即出现。
同样的预览、同样的下载,只是粒度更细。"

**[第 7 步 — aligned_sums 内联预览]**(打开预览模态框)
"我们打开一个看看。
*aligned_sums* —— MotionCor2 的运动校正显微图 —— 直接在预览模态框中渲染。
表格用排序网格,曲线自动绘图,三维图用可视化器。
BioMate 根据文件类型选择正确的渲染器。"

**[第 8 步 — Methods 标签]**(关闭预览,滚动下,切换到 Methods)
"Methods 标签。段落形式的 IMRaD 文本,
可直接粘贴至论文。工具名称、版本、精确参数 ——
便于同行复现。底部斜体标注哪些值是推断的,哪些是从 manifest 读取的。"

**[第 9 步 — Parameters 标签]**(自动切换)
"Parameters 标签。Phase、step、参数、值 ——
本次运行触及的每个参数都在一张表中。
默认值与用户覆盖、auto-loop 调整分别标记。
审稿人偏好将此作为补充材料。"

**[第 10 步 — Software 标签]**(自动切换)
"Software 标签。每一个参与运行的工具及其精确版本 ——
编排器、容器运行时、科学软件包。
与 Parameters 共同构成可重复性基线。
匹配这些版本即可复现相同输出。"

**[第 11 步 — Citations 标签]**(自动切换)
"Citations 标签。自动生成的参考文献列表,对应 Methods 中引用的工具与方法。
PMID 可点击直达 PubMed。
导出的 Download report 已经预绑定 Citations + Methods。"

**[第 12 步 — QC audit 标签]**(自动切换)
"QC audit 标签 —— 合规视角。
每次触发的 QC gate,含时间戳、阈值、观测值、结果、动作。
含 chain-of-custody 与 operator e-signature。
21 CFR Part 11 友好 —— 监管方与审稿人需要看到的全部信息。"

**[第 13 步 — 收束,屏幕中央]**(重置为 Findings)
"这就是 After-run 报告。每个标签都从同一份 run manifest 生成。
*Download report* 链接将 7 个标签打包为结构化文档 ——
DOCX 用于 Word,Markdown 用于 Notion/GitHub,LaTeX 用于期刊模板。
分享 run URL,协作者即可以只读身份打开同一面板。"

---

## 3 · 药物筛选 · auto-loop + 对比演示(`R02`)

> **场景背景。** 用户对一万化合物库做血脑屏障穿透性筛选。我们将完整观察一次因 QC 失败而触发的 pilot,BioMate 用调整后的参数发起 auto-loop,Run A 与 Run B 的对比,以及在胜出参数下的完整运行。**全自动 —— 端到端约 90 秒。**

**[第 1 步 — 介绍,屏幕中央]**
"药物筛选常需要先做 pilot、QC 失败、再用 auto-loop 修复。
整个序列在对话流中可视化,是唯一默认展示 Run-vs-Run 对比卡片的场景。
约一分半钟。本教程自动执行所有决策。"

**[第 2 步 — Plan checklist · 5 个子任务]**
"BioMate 将请求分解为 5 个子任务:
Ingest、ADMET 预测、hERG gate、Ames gate、ranking。
逐一推进。
请留意 hERG 与 Ames 两行 —— 它们会在 pilot 中触发警示。"

**[第 3 步 — Pilot-first 提示卡]**
"一万化合物体量较大。DeepAgent 建议先做 5% 的 pilot。
卡片在对话中同时显示采样比例、策略与完整运行成本对比 ——
无需单独弹窗。决策就在对话中完成。"

**[第 4 步 — Pilot 运行中]**
"Pilot 正在对 10000 个化合物中的 500 个进行运算。
plan items 从空心圆到实心点再到对勾,逐步推进。
小规模 pilot 用于验证 QC gate,然后再投入完整运行。"

**[第 5 步 — Pilot 中 QC 失败]**
"hERG 与 Ames 触发警示。Plan items 原地变为琥珀色 warn pill。
管线不会崩溃 —— 下一个 surface 承接决策。
QC gate 按 phase 评估;一旦 trip,auto-loop 会提出修复方案。"

**[第 6 步 — QC speaker pills]**
"对话流中出现两条 QC pill 行 —— 一条 hERG,一条 Ames。
pill 颜色为琥珀色,与 plan 上的 warn pill 一致。
pill 颜色在整个 UI 中保持稳定 —— plan、对话、Tweaks 面板皆同。"

**[第 7 步 — Pilot 停止 · QC gate trip]**
"Pilot promotion card 解释失败原因,
并直接展示 auto-loop 的修复建议 —— 新的 *logp_max* 与 *mw_max* 值,
一键点击 *Apply fixes and re-pilot* 即可重试。
绝无静默重试 —— 用户始终先看到建议的改动。"

**[第 8 步 — Auto-loop · LOOP speaker]**
"修复方案已应用。LOOP speaker —— 紫色 pill —— 接管。
LOOP 下的每一行都是 auto-loop 的决策,审计轨迹清晰。
QC 重新评估,两个 gate 在第二次运行中均通过。"

**[第 9 步 — Run-vs-Run 对比卡片]**
"两次 pilot 均已完成。对比卡片并排展示:
含 Δ 列的指标表;按来源标注(auto-loop vs 用户)的参数差异;
带 confidence 与 p 值的奖杯推荐徽章。
Run A 的 QC 失败标红,Run B 的 QC 通过标绿 —— 决策一目了然。"

**[第 10 步 — 10 秒自动选取]**
"confidence 为 high(此处 p < 0.01)时,推荐按钮显示 10 秒倒计时。
鼠标悬停可暂停;点击立即提交。
自动触发会留下 *No response — using Run B automatically* 这一行,
不存在静默动作。
中等或低 confidence:无自动触发,卡片等待用户操作。"

**[第 11 步 — 完整运行 · Run B 参数]**
"决策已提交。完整筛选现以 auto-loop 调优后的参数运行于 10000 化合物。
plan items 再次推进 —— 速度更快,因为 pilot 已经验证了 gate。"

**[第 12 步 — Findings card · 47 个候选]**
"完成总结直接在对话中落地。
经过所有 QC gate 后,47 个 BBB 穿透候选化合物。
含运行时长、QC 通过率、完整 Report 链接 ——
Findings、Outputs、Methods、Parameters、Software、Citations。
将鼠标悬停在前文 step-decision 行的 *(why?)* 锚点上,即可看到工具选择的理由。"

**[第 13 步 — 收束,屏幕中央]**
"端到端 auto-loop 完成。
pilot → 失败 → auto-loop → 对比 → 完整运行 → findings,完整链路一次走完。
三张决策卡片、一张对比卡片、由 speaker 串起的清晰审计。
Variant calling 教程演示嵌套 plan + step 重试 —— 推荐紧接着观看。"

---

## 4 · IND Report · 五步流水线 → 文档 → 签章(`IND-01`)

> **场景背景。** 一位法规科学家打开一个进行中的 IND 项目(BM-0042 · CB1 反向激动剂 · 肥胖症)。本演示完整走过 5 步流水线、右侧实时文档面板、段落反馈、Audit 抽屉,以及 21 CFR Part 11 的签章冻结。约 2 分钟。

**[第 1 步 — 欢迎,屏幕中央]**
"欢迎使用 BioMate IND Report。
我们将走过构建 IND §2.6 非临床档案的 5 步流水线、
右侧的实时文档面板,以及 21 CFR Part 11 的签章冻结。
全程约 2 分钟。"

**[第 2 步 — 项目列表]**
"每个新药项目独立存在。
左侧彩色圆点表示状态 —— 绿色已签章,蓝色进行中,琥珀色被 gate 阻塞。
点击切换项目,各项目工作内容自动保留。"

**[第 3 步 — 新建项目]**
"两种方式启动 IND:
此处侧栏的 *New Project*,
或更常用的方式 —— 在 BioMate chat 中。
当你在 chat 中运行 ADMET 工作流后,
结果下方会出现 *Generate IND* 芯片,
直接跳转到这里,并自动填好 Step 1 和 Step 2。"

**[第 4 步 — Step 1 · 项目设置]**
"Step 1 是项目头部:
分子、靶点、适应症、申办方,以及你计划申报的法规机构。
每添加一个区域,文档面板就开启该区域专属段落 ——
NMPA 追加 GLP 声明,PMDA 追加种族桥接说明。"

**[第 5 步 — 多区域一次性申报]**
"FDA、EMA、NMPA、PMDA —— 任意组合勾选。
文档面板内嵌渲染区域专属段落;
对所有区域都适用的正文保持不变。
单一数据源,产出四份机构版本。"

**[第 6 步 — Step 2 · ADMET 筛选]**
"Step 2 在 AWS Batch 上运行 BioMate 的 *predict_admet_properties* 工作流。
覆盖 41 个 endpoint:hERG、DILI、Ames、PPBR、Caco-2、BBB、CYPs、P-gp。
结果直接喂入档案的 §2.6.1.3 与 §2.6.4。"

**[第 7 步 — 逐化合物分诊]**
"点击 *View ADMET table* 查看逐化合物视图。
每个表头悬停显示对应 guideline 引用 ——
例如 hERG 引用 Redfern 2003 与 ICH S7B,液体 IC50 < 10 µM 即为风险。
绿勾、琥珀波浪线、红叉 —— 这套配色贯穿整篇档案。"

**[第 8 步 — 引入湿实验数据]**
"计算预测只能给出 Partial 覆盖。
要升级到 Full,需上传湿实验数据 ——
NTP GLP 报告 PDF 或 FDA NDA 审评报告。
BioMate 自动抽取实测值;
凡是重叠条目,实测值优先级高于预测值。"

**[第 9 步 — Step 3 · PBPK 资格认证]**
"Step 3 依据 EMA 的 PBPK qualification guideline,
针对 30 种参考药物的数据集对模型进行资格认证。
Cmax 与 AUC 在 67% 以上的参考集内,误差不超过 2 倍 ——
这就是法规通过门槛。"

**[第 10 步 — 关键门户徽章]**
"这枚徽章是整条流水线最重要的一处像素。
PBPK 一旦未通过,下游 IND 装配立即被阻塞,直到重新认证。
*Re-run with new params* 可调整清除率、分布容积、吸收等参数,
直接在当前页面重试。"

**[第 11 步 — Step 4 · 主候选筛选]**
"Step 4 对候选集合进行排序。
高斯过程模型 + EHVI 采集函数,基于 Morgan 指纹,
在 hERG、DILI、Ames、效价、适用域 5 个维度上为每个候选打分。"

**[第 12 步 — 读懂排序]**
"实心圆点编码效价 —— 五格中四格实心代表强活性。
*OOD* 表示越出适用域 —— 候选仍然排序,
但在 §2.6.1.5 标注 limitation 声明,让审评员看到注意事项。"

**[第 13 步 — Step 5 · IND 文档]**
"Step 5 装配整份档案 ——
§2.6.1.1 到 §2.6.6 ——
当 Step 1 到 Step 4 全部完成时自动生成。
右侧面板随每一步流水线完成而实时填充文档。"

**[第 14 步 — 章节覆盖度]**
"章节覆盖度一目了然。
实心圆 = Full,计算 + 实测,可提交;
半圆 = Partial,仅计算,标记为待补湿实验;
空心圆 = 尚未生成。
§2.6.5 和 §2.6.6 必须有 GLP 数据才能升至 Full。"

**[第 15 步 — 实时文档查看器]**
"文档面板始终常驻右侧。
每一步流水线完成,对应章节就地填充 ——
无需刷新页面,无需另开预览,无需从临时文档复制粘贴。"

**[第 16 步 — 任意章节跳转]**
"顶部 tab 条直达任意章节。
每个 tab 旁的圆点编码该章节覆盖度 ——
绿色 Full,琥珀 Partial ——
无需滚动即可发现缺口。"

**[第 17 步 — 区域专属视图]**
"在这里切换渲染区域。
NMPA 视图追加 GLP 声明段落;
PMDA 视图追加种族桥接假设表。
*所有区域合并* 视图,即最终递交给各机构的版本。"

**[第 18 步 — 编辑任意段落]**
"每一段都可编辑。
修改一段,旁边即出现 *edited — saved for model improvement* 提示。
后台中这次编辑形成一对训练样本 ——
你的版本为 chosen,我们的版本为 rejected。
这就是 BioMate 法规模型不断进化的方式 ——
靠每一位客户的专业知识沉淀。"

**[第 19 步 — 推荐引用]**
"看到段落末尾的 + 图标了吗?
点击即可推荐我们尚未收录的 guideline ——
NMPA / CDE 技术指南尤其有用。
审核通过后,该条目在下次刷新时进入共享语料库。"

**[第 20 步 — 法规审计]**
"§2.6 顶部的 audit 横条,就是 compliance 的检视镜。
0 critical · 0 major · 2 minor · 4 info —— 意味着文档可签章。
critical 直接阻止签章;
major 显示琥珀警告,但允许法规科学家凭判断继续。"

**[第 21 步 — 每条 finding 都附建议]**
"打开 audit 抽屉。
每一条 finding 展示触发原因、推荐修复,以及 *jump to section* 链接。
点击 *Dismiss* 并填写理由 ——
例如 *not applicable to this topical product* ——
该理由会自动反哺所有客户的 checker 规则。"

**[第 22 步 — 签章并冻结]**
"签章并冻结。
依据 21 CFR Part 11 §11.200,
审核人凭证、6 位 TOTP 验证码,
以及 meaning-of-signature 声明,
全部永久写入冻结后的文档。"

**[第 23 步 — 版本不可变]**
"已签章版本以 SHA-256 冻结。
创建 v3 取代 v2,
但 v2 的签章记录永久保留在审计链中。
任意历史版本都可按字节渲染重现。"

**[第 24 步 — 收束,屏幕中央]**
"这就是端到端的 IND Report 演示。
5 步流水线、实时文档、audit 抽屉、签章冻结。
建议自行试三件事 ——
点击 *Sign & Freeze* 走完 TOTP 弹窗、
编辑任意段落看 training-pair 提示、
对一条 minor finding 写 dismiss 理由,完成反馈闭环。
祝申报顺利。"

---

## 录制与配音建议

- **语速。** 中文约 200–240 字/分钟;每个 step 旁白控制在 5–8 秒,与画面同步。
- **语气。** 演示者风格,科研人员对同行讲解。沉稳、自信、不夸张。
- **专有名词读法(中文配音建议)。**
  - "cryo-EM" → 直接读英文,或中文"冷冻电镜",保持全片统一
  - "CryoSPARC" → 读作 "cryo-spark"
  - "FSC / GSFSC" → 直接读字母 "F-S-C / GS-F-S-C"
  - "EMPIAR-10025" → "EMPIAR 一万零二十五"
  - "IMRaD" → 直接读作一个词 "IM-rad"
  - "DOCX / Markdown / LaTeX" → 各读原文
  - "hERG / Ames" → 字母 + 原文
  - "21 CFR Part 11" → "二十一 CFR 第十一部"
  - "logp_max / mw_max" → 读字母,如 "log-p-max / m-w-max"
  - "p < 0.01" → "p 小于零点零一"
  - "AWS Batch" → 直接读英文
  - "ADMET" → 读作一个词 "AD-met";或读"AD-MET"
  - "PBPK / DILI / NMPA / PMDA / CDE / FDA / EMA" → 字母拼读
  - "Caco-2" → "Caco 二"
  - "Cmax / AUC" → "C-max / A-U-C"
  - "P-gp" → "P-g-p"
  - "EHVI" → 字母拼读
  - "TOTP" → 字母拼读
  - "SHA-256" → "SHA 二五六"
  - "§2.6.1.3 / §2.6.4" → 读 "第 2 点 6 点 1 点 3 章" 或直接读英文 "section 2-point-6-point-1-point-3"
  - "OOD" → 字母拼读;首次说明可加注 "超出适用域"
  - "BM-0042" → "B-M 零零四二"
- **同步要点。**
  - 药物筛选教程为自动播放(autoAdvance);字幕需严格匹配每步约 7 秒的节奏。
  - cryo 与 output 教程由演示者手动点击;字幕可在每步之间留半秒呼吸。
  - 卡片或模态框入场时,字幕略延迟 0.5 秒,留出动画呼吸空间。
- **字幕格式输出(可选)。** 后期制作团队如需 SRT 格式,可基于本文件每个 step 的旁白生成时间码。
