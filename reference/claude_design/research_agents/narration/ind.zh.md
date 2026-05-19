# ind narration (ZH)

## Step 1 — 欢迎,屏幕中央

欢迎使用 BioMate IND Report。 我们将走过构建 IND §2.6 非临床档案的 5 步流水线、 右侧的实时文档面板,以及 21 CFR Part 11 的签章冻结。 全程约 2 分钟。

---

## Step 2 — 项目列表

每个新药项目独立存在。 左侧彩色圆点表示状态 —— 绿色已签章,蓝色进行中,琥珀色被 gate 阻塞。 点击切换项目,各项目工作内容自动保留。

---

## Step 3 — 新建项目

两种方式启动 IND: 此处侧栏的 *New Project*, 或更常用的方式 —— 在 BioMate chat 中。 当你在 chat 中运行 ADMET 工作流后, 结果下方会出现 *Generate IND* 芯片, 直接跳转到这里,并自动填好 Step 1 和 Step 2。

---

## Step 4 — Step 1 · 项目设置

Step 1 是项目头部: 分子、靶点、适应症、申办方,以及你计划申报的法规机构。 每添加一个区域,文档面板就开启该区域专属段落 —— NMPA 追加 GLP 声明,PMDA 追加种族桥接说明。

---

## Step 5 — 多区域一次性申报

FDA、EMA、NMPA、PMDA —— 任意组合勾选。 文档面板内嵌渲染区域专属段落; 对所有区域都适用的正文保持不变。 单一数据源,产出四份机构版本。

---

## Step 6 — Step 2 · ADMET 筛选

Step 2 在 the cloud 上运行 BioMate 的 *predict_admet_properties* 工作流。 覆盖 41 个 endpoint:hERG、DILI、Ames、PPBR、Caco-2、BBB、CYPs、P-gp。 结果直接喂入档案的 §2.6.1.3 与 §2.6.4。

---

## Step 7 — 逐化合物分诊

点击 *View ADMET table* 查看逐化合物视图。 每个表头悬停显示对应 guideline 引用 —— 例如 hERG 引用 Redfern 2003 与 ICH S7B,液体 IC50 < 10 µM 即为风险。 绿勾、琥珀波浪线、红叉 —— 这套配色贯穿整篇档案。

---

## Step 8 — 引入湿实验数据

计算预测只能给出 Partial 覆盖。 要升级到 Full,需上传湿实验数据 —— NTP GLP 报告 PDF 或 FDA NDA 审评报告。 BioMate 自动抽取实测值; 凡是重叠条目,实测值优先级高于预测值。

---

## Step 9 — Step 3 · PBPK 资格认证

Step 3 依据 EMA 的 PBPK qualification guideline, 针对 30 种参考药物的数据集对模型进行资格认证。 Cmax 与 AUC 在 67% 以上的参考集内,误差不超过 2 倍 —— 这就是法规通过门槛。

---

## Step 10 — 关键门户徽章

这枚徽章是整条流水线最重要的一处像素。 PBPK 一旦未通过,下游 IND 装配立即被阻塞,直到重新认证。 *Re-run with new params* 可调整清除率、分布容积、吸收等参数, 直接在当前页面重试。

---

## Step 11 — Step 4 · 主候选筛选

Step 4 对候选集合进行排序。 高斯过程模型 + EHVI 采集函数,基于 Morgan 指纹, 在 hERG、DILI、Ames、效价、适用域 5 个维度上为每个候选打分。

---

## Step 12 — 读懂排序

实心圆点编码效价 —— 五格中四格实心代表强活性。 *OOD* 表示越出适用域 —— 候选仍然排序, 但在 §2.6.1.5 标注 limitation 声明,让审评员看到注意事项。

---

## Step 13 — Step 5 · IND 文档

Step 5 装配整份档案 —— §2.6.1.1 到 §2.6.6 —— 当 Step 1 到 Step 4 全部完成时自动生成。 右侧面板随每一步流水线完成而实时填充文档。

---

## Step 14 — 章节覆盖度

章节覆盖度一目了然。 实心圆 = Full,计算 + 实测,可提交; 半圆 = Partial,仅计算,标记为待补湿实验; 空心圆 = 尚未生成。 §2.6.5 和 §2.6.6 必须有 GLP 数据才能升至 Full。

---

## Step 15 — 实时文档查看器

文档面板始终常驻右侧。 每一步流水线完成,对应章节就地填充 —— 无需刷新页面,无需另开预览,无需从临时文档复制粘贴。

---

## Step 16 — 任意章节跳转

顶部 tab 条直达任意章节。 每个 tab 旁的圆点编码该章节覆盖度 —— 绿色 Full,琥珀 Partial —— 无需滚动即可发现缺口。

---

## Step 17 — 区域专属视图

在这里切换渲染区域。 NMPA 视图追加 GLP 声明段落; PMDA 视图追加种族桥接假设表。 *所有区域合并* 视图,即最终递交给各机构的版本。

---

## Step 18 — 编辑任意段落

每一段都可编辑。 修改一段,旁边即出现 *edited — saved for model improvement* 提示。 后台中这次编辑形成一对训练样本 —— 你的版本为 chosen,我们的版本为 rejected。 这就是 BioMate 法规模型不断进化的方式 —— 靠每一位客户的专业知识沉淀。

---

## Step 19 — 推荐引用

看到段落末尾的 + 图标了吗? 点击即可推荐我们尚未收录的 guideline —— NMPA / CDE 技术指南尤其有用。 审核通过后,该条目在下次刷新时进入共享语料库。

---

## Step 20 — 法规审计

§2.6 顶部的 audit 横条,就是 compliance 的检视镜。 0 critical · 0 major · 2 minor · 4 info —— 意味着文档可签章。 critical 直接阻止签章; major 显示琥珀警告,但允许法规科学家凭判断继续。

---

## Step 21 — 每条 finding 都附建议

打开 audit 抽屉。 每一条 finding 展示触发原因、推荐修复,以及 *jump to section* 链接。 点击 *Dismiss* 并填写理由 —— 例如 *not applicable to this topical product* —— 该理由会自动反哺所有客户的 checker 规则。

---

## Step 22 — 签章并冻结

签章并冻结。 依据 21 CFR Part 11 §11.200, 审核人凭证、6 位 TOTP 验证码, 以及 meaning-of-signature 声明, 全部永久写入冻结后的文档。

---

## Step 23 — 版本不可变

已签章版本以 SHA-256 冻结。 创建 v3 取代 v2, 但 v2 的签章记录永久保留在审计链中。 任意历史版本都可按字节渲染重现。

---

## Step 24 — 收束,屏幕中央

这就是端到端的 IND Report 演示。 5 步流水线、实时文档、audit 抽屉、签章冻结。 建议自行试三件事 —— 点击 *Sign & Freeze* 走完 TOTP 弹窗、 编辑任意段落看 training-pair 提示、 对一条 minor finding 写 dismiss 理由,完成反馈闭环。 祝申报顺利。

---
