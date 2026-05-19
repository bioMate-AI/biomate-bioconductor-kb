# ra-afterrun narration (ZH)

## Step 1 — 介绍,屏幕中央

运行刚刚完成。面板底部的 *After run* 区块由 7 个标签页组成, 覆盖 BioMate 产出的所有内容。 我们将逐一访问,标签内容随之切换。

---

## Step 2 — After run 头部 + 下载报告

每次完成运行都会留下一个 *After run* 区块。 右侧的 *Download report* 链接将下面 7 个标签打包为一份结构化文档 —— DOCX、Markdown、LaTeX 三种格式可选 —— 一键即可获得发表级输出。

---

## Step 3 — 7 个标签概览

7 个标签覆盖完整故事: Findings、Outputs、Methods、Parameters、Software、Citations、QC audit。 顺序符合自然阅读顺序 —— 先叙述、再产物、再方法与可重复性、最后审计。

---

## Step 4 — Findings 标签

Findings 标签以头条指标开篇 —— 3.21 Å 分辨率, 配 2–3 条要点说明,加一张数值表。 每个数字都从 manifest 读取,绝非生成。 若某项 finding 缺乏引用,BioMate 会标注为 author judgment。

---

## Step 5 — Outputs 标签

Outputs 标签按 phase + step 分组,每行一个文件。 *view* 内联预览,*download* 单文件下载。 顶部的 *Download all* 按钮打包全部为 ZIP。

---

## Step 6 — 步骤侧也有输出

无需等待报告才能取文件。 看上方面板任意已完成步骤行 —— 步骤一完成,输出芯片立即出现。 同样的预览、同样的下载,只是粒度更细。

---

## Step 7 — aligned_sums 内联预览

我们打开一个看看。 *aligned_sums* —— MotionCor2 的运动校正显微图 —— 直接在预览模态框中渲染。 表格用排序网格,曲线自动绘图,三维图用可视化器。 BioMate 根据文件类型选择正确的渲染器。

---

## Step 8 — Methods 标签

Methods 标签。段落形式的 IMRaD 文本, 可直接粘贴至论文。工具名称、版本、精确参数 —— 便于同行复现。底部斜体标注哪些值是推断的,哪些是从 manifest 读取的。

---

## Step 9 — Parameters 标签

Parameters 标签。Phase、step、参数、值 —— 本次运行触及的每个参数都在一张表中。 默认值与用户覆盖、auto-loop 调整分别标记。 审稿人偏好将此作为补充材料。

---

## Step 10 — Software 标签

Software 标签。每一个参与运行的工具及其精确版本 —— 编排器、容器运行时、科学软件包。 与 Parameters 共同构成可重复性基线。 匹配这些版本即可复现相同输出。

---

## Step 11 — Citations 标签

Citations 标签。自动生成的参考文献列表,对应 Methods 中引用的工具与方法。 PMID 可点击直达 PubMed。 导出的 Download report 已经预绑定 Citations + Methods。

---

## Step 12 — QC audit 标签

QC audit 标签 —— 合规视角。 每次触发的 QC gate,含时间戳、阈值、观测值、结果、动作。 含 chain-of-custody 与 operator e-signature。 21 CFR Part 11 友好 —— 监管方与审稿人需要看到的全部信息。

---

## Step 13 — 收束,屏幕中央

这就是 After-run 报告。每个标签都从同一份 run manifest 生成。 *Download report* 链接将 7 个标签打包为结构化文档 —— DOCX 用于 Word,Markdown 用于 Notion/GitHub,LaTeX 用于期刊模板。 分享 run URL,协作者即可以只读身份打开同一面板。

---
