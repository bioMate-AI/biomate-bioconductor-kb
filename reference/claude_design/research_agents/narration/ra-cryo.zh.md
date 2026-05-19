# ra-cryo narration (ZH)

## Step 1 — 欢迎,屏幕中央

你好。让我们一起完成一次完整的 cryo-EM 单颗粒分析。 不需要 CryoSPARC 经验 —— BioMate 会自动配置参数,你只需跟随演示。

---

## Step 2 — 双视图、同一任务,Plan checklist

BioMate 用两个视图展示同一次运行。 左侧是对话流:粘性 plan checklist + 带 speaker 标签的进度行。 右侧是工作流面板:阶段、步骤、参数、输出 —— 技术视图。 两侧实时同步。

---

## Step 3 — 面板头部

这里是 run header。工作流名称、状态徽章、实时进度条。 目前状态为 *idle* —— 工作流已加载,但尚未启动。

---

## Step 4 — 5 阶段、23 步骤

CryoSPARC SPA 分为 5 个阶段: A. 运动校正与 CTF 估计; B. 颗粒挑选; C. 二维分类; D. 三维重构; E. 锐化与验证。 只有当前活动阶段自动展开,其他阶段折叠为状态芯片,保持面板简洁。

---

## Step 5 — Phase A 内部

当前阶段实时显示每个步骤的状态。你可以随时查看其他阶段,不会打扰运行。

---

## Step 6 — 唯一主操作 · Confirm & Run

参数已由 BioMate 从你的对话自动填充。 点击 *Confirm and run workflow* 即可向 the cloud 提交任务。 底部永远只有一个主按钮 —— 杜绝选择困境。

---

## Step 7 — Phase A 已启动

状态徽章已变为 running,进度条移动。Phase A 在云端 GPU 上进行运动校正。

---

## Step 8 — 每个步骤的实时进度

Phase A 内,每个步骤都有实时状态芯片 —— queued、running、completed、failed。 MotionCor2 每处理完一帧,计数即时更新。 对话流与面板共用同一 SSE 流,双视图始终同步。

---

## Step 9 — CTF 拟合质量门 trip

CTF 估计中,BioMate 检测到 CTF 拟合分辨率低于阈值 —— 散焦扫描范围可能过窄。 QC gate 是质量护栏 —— 与其产出低质量重构,BioMate 选择暂停并提供修复方案。

---

## Step 10 — Halt card · 接受或编辑修复方案

Auto-loop 默认关闭,halt card 等待你决策。 BioMate 建议将散焦范围扩大到 0.5–4.0 微米。 你可以 *Accept* 采纳建议,*Edit* 自行调整数值,或 *Dismiss* 维持原样。 打开该阶段的 auto-loop 开关后,BioMate 会自动套用修复方案并重试,最多 3 次。

---

## Step 11 — Gate 通过 · Phase A 完成

你采纳了建议。Phase A 用新散焦范围重新运行,gate 通过,阶段标记为完成。 Phase B 自动启动。 每一次接受、编辑、重试都记录在 QC audit 报告中 —— 完全可审计。

---

## Step 12 — 步骤输出实时落地

注意每个已完成步骤行上的小文件芯片? 步骤一完成,输出文件即时出现 —— 文件名、类型图标、*view*、*download* 链接齐备。 无需等待整个运行结束。

---

## Step 13 — Phase B · 颗粒挑选

Phase B 在每张显微图上挑选颗粒,并为下一阶段输出坐标文件。

---

## Step 14 — Phase C · 二维分类

Phase C 进行二维分类并剔除杂质,仅保留清晰视角进入三维。

---

## Step 15 — Phase D · 三维重构

Phase D 重构三维密度图,并保留 half-map 对用于分辨率评估。

---

## Step 16 — Phase E · 锐化与验证

Phase E 对密度图进行锐化与分辨率验证,输出可发表的结果。

---

## Step 17 — 23 步全部完成

23 步全部完成。状态切换为 *completed*。 重构在 GSFSC 0.143 下收敛于 3.21 Å —— 完全达到发表级别。

---

## Step 18 — 输出可下载

底部主按钮已变为 *Run again*。 向上滚动可看到 *View Results*、*Download All* 和自动生成的 Findings。

---

## Step 19 — After-run 区块解锁

每次完成运行,面板底部都会新增一个 *After run* 区块 —— Outputs、Findings、Methods、Parameters、Software、Citations、QC audit 一次性聚合。 有一个专门的教程详细介绍这部分。

---

## Step 20 — 收束,屏幕中央

这就是一次完整的 cryo-EM 运行 —— 从原始视频帧到锐化的三维密度图,19 个步骤。 真实运行需要 30–;本教程为方便演示,加速了云端时间。

---
