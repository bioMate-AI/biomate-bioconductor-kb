# ra-drugscreen narration (ZH)

## Step 1 — 介绍,屏幕中央

药物筛选常需要先做 pilot、QC 失败、再用 auto-loop 修复。 整个序列在对话流中可视化,是唯一默认展示 Run-vs-Run 对比卡片的场景。 约一分半钟。本教程自动执行所有决策。

---

## Step 2 — Plan checklist · 5 个子任务

BioMate 将请求分解为 5 个子任务: Ingest、ADMET 预测、hERG gate、Ames gate、ranking。 逐一推进。 请留意 hERG 与 Ames 两行 —— 它们会在 pilot 中触发警示。

---

## Step 3 — Pilot-first 提示卡

一万化合物体量较大。DeepAgent 建议先做 5% 的 pilot。 卡片在对话中同时显示采样比例、策略与完整运行成本对比 —— 无需单独弹窗。决策就在对话中完成。

---

## Step 4 — Pilot 运行中

Pilot 正在对 10000 个化合物中的 500 个进行运算。 plan items 从空心圆到实心点再到对勾,逐步推进。 小规模 pilot 用于验证 QC gate,然后再投入完整运行。

---

## Step 5 — Pilot 中 QC 失败

hERG 与 Ames 触发警示。Plan items 原地变为琥珀色 warn pill。 管线不会崩溃 —— 下一个 surface 承接决策。 QC gate 按 phase 评估;一旦 trip,auto-loop 会提出修复方案。

---

## Step 6 — QC speaker pills

对话流中出现两条 QC pill 行 —— 一条 hERG,一条 Ames。 pill 颜色为琥珀色,与 plan 上的 warn pill 一致。 pill 颜色在整个 UI 中保持稳定 —— plan、对话、Tweaks 面板皆同。

---

## Step 7 — Pilot 停止 · QC gate trip

Pilot promotion card 解释失败原因, 并直接展示 auto-loop 的修复建议 —— 新的 *logp_max* 与 *mw_max* 值, 一键点击 *Apply fixes and re-pilot* 即可重试。 绝无静默重试 —— 用户始终先看到建议的改动。

---

## Step 8 — Auto-loop · LOOP speaker

修复方案已应用。LOOP speaker —— 紫色 pill —— 接管。 LOOP 下的每一行都是 auto-loop 的决策,审计轨迹清晰。 QC 重新评估,两个 gate 在第二次运行中均通过。

---

## Step 9 — Run-vs-Run 对比卡片

两次 pilot 均已完成。对比卡片并排展示: 含 Δ 列的指标表;按来源标注(auto-loop vs 用户)的参数差异; 带 confidence 与 p 值的奖杯推荐徽章。 Run A 的 QC 失败标红,Run B 的 QC 通过标绿 —— 决策一目了然。

---

## Step 10 — 10 秒自动选取

confidence 为 high(此处 p < 0.01)时,推荐按钮显示 10 秒倒计时。 鼠标悬停可暂停;点击立即提交。 自动触发会留下 *No response — using Run B automatically* 这一行, 不存在静默动作。 中等或低 confidence:无自动触发,卡片等待用户操作。

---

## Step 11 — 完整运行 · Run B 参数

决策已提交。完整筛选现以 auto-loop 调优后的参数运行于 10000 化合物。 plan items 再次推进 —— 速度更快,因为 pilot 已经验证了 gate。

---

## Step 12 — Findings card · 47 个候选

完成总结直接在对话中落地。 经过所有 QC gate 后,47 个 BBB 穿透候选化合物。 含运行时长、QC 通过率、完整 Report 链接 —— Findings、Outputs、Methods、Parameters、Software、Citations。 将鼠标悬停在前文 step-decision 行的 *(why?)* 锚点上,即可看到工具选择的理由。

---

## Step 13 — 收束,屏幕中央

端到端 auto-loop 完成。 pilot → 失败 → auto-loop → 对比 → 完整运行 → findings,完整链路一次走完。 三张决策卡片、一张对比卡片、由 speaker 串起的清晰审计。 Variant calling 教程演示嵌套 plan + step 重试 —— 推荐紧接着观看。

---
