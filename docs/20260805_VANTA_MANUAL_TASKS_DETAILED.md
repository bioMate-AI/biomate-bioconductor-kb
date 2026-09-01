# Vanta 剩余手动任务 —— 保姆级逐条教程

Date: 2026-08-05
说明：每条都写了“在哪、点什么、填什么”。按钮文字各版本略有差异，按功能找。

政策：**19 份已全部批准，无需操作。**

---

# A. 先做这批（用 Vanta 自带功能，一次能消好几条）

## A1. 选并分配「安全意识培训」（消 2 条测试 + 相关证据）

对应测试：`security-training-records`（通用）、`hipaa-security-training-records`（HIPAA）
以及证据：`sat-completion-bulk`、`hipaa-sat-completion-bulk`（员工完成后自动满足）

1. 左侧菜单 **Personnel（人员）** 下找 **Training / 培训**，或点顶部搜索输入 “training”
2. 进入 **Security Awareness Training** 设置页
3. 选择 **Use Vanta's training（使用 Vanta 内置培训）**
4. 勾选课程类别：**General Security Awareness** + **HIPAA**（两个都勾）
5. 分配对象：选 **All personnel / 默认组**
6. 保存。→ 两条“training selected”测试立即通过
7. 通知同事去 **My Work** 里完成培训（每人约 20 分钟）。完成后“training completion”证据自动满足

> 这是最高性价比的一步：选一次，消 2 条测试，且员工完成后再消 2 条证据。

## A2. 在 Vanta 里做「访问审查」（消 access-reviews 证据）

对应：`access-reviews`（Proof of completed access review）

1. 左侧 **Access（访问）** 或 **Personnel → Access Reviews**
2. 点 **Start access review / 新建访问审查**
3. 选范围：AWS、GitHub、Google Workspace（已连接的系统会自动带出人员+权限）
4. 逐行勾 **Keep（保留）** 或 **Revoke（撤销）**——对每个人在每个系统的访问做判断
5. 全部过一遍 → **Complete review / 完成**
6. 完成后 Vanta 自动生成审查记录 = 证据满足

---

# B. 供应商（Vendors）—— 你特别问的，写详细

对应测试：
- `vendors-have-authentication-method-specified`（每个供应商填认证方式）
- `high-severity-vendor-compliance-reports`（高风险供应商做安全评估）
- `third-party-security-reviews`（供应商安全审查证据）

## B1. 先给每个供应商填「认证方式」（最快）

1. 左侧 **Vendors（供应商）** → 看到供应商列表
2. 逐个点开供应商 → 找 **Authentication method / 认证方式** 字段
3. 下拉选该供应商登录方式：
   - 用 Google/SSO 登录的 → 选 **SSO**
   - 用账号密码 → 选 **Username & Password**，如启用了 2FA 再勾 **MFA enabled**
4. 保存。所有供应商都填完 → 这条测试通过

## B2. 给高风险供应商做「安全评估」（重点，分步）

“安全评估”= 评估这家供应商的安全状况。Vanta 里有两种做法，任选：

### 做法一：附上供应商的合规报告（最省事，推荐）
适用于 AWS、Google、GitHub、Anthropic 等大厂——它们都有公开的 SOC 2 / ISO 报告。

1. **Vendors** → 点开某个高风险供应商（如 AWS）
2. 找 **Security Assessment / Reviews** 区 → 点 **Add assessment / Start review**
3. 选评估方式 **Attach compliance report（附合规报告）**
4. 上传或粘贴该供应商的合规报告链接：
   - AWS：AWS Artifact 里的 SOC 2 报告（或写 https://aws.amazon.com/compliance/soc-faqs/ ）
   - Google Workspace：https://cloud.google.com/security/compliance/soc-2
   - GitHub：https://github.com/security
   - Anthropic：https://trust.anthropic.com
5. 评估结论选 **Approved / Low risk**，写一句：“该供应商持有有效 SOC 2 报告，风险可接受。”
6. 保存。→ 该供应商评估完成

### 做法二：发安全问卷（供应商没有现成报告时）
1. 同上进入供应商的 **Security Assessment**
2. 选 **Send questionnaire（发送问卷）**
3. 填对方安全联系人邮箱 → Vanta 发一份标准安全问卷
4. 对方回填后，你在 Vanta 里审阅打分 → 标 **Approved**

> **哪些算“高风险”**：能接触你系统/数据的（AWS、Google、GitHub、Anthropic、计费/Lago、任何存数据的 SaaS）。营销类、不碰数据的可标低风险、简单过。
> **B2 做完，`third-party-security-reviews` 证据通常一并满足**（它就是要这些评估记录）。

---

# C. 配置类修复

## C1. IdP（Google Workspace）设为身份源

对应：`idp-linked-to-vanta`（现在报 “No identity provider linked / 连接有问题”）

1. 左侧 **Integrations** → 点 **Google Workspace**
2. 找设置项 **Populate the People page / 用此来源填充人员**，**打开它**
3. 如果页面显示红色报错（fetch error）：按提示点 **Reconnect / 重新授权**，用有管理员权限的 Google 账号重新授权一次
4. 保存。等它重新同步人员 → 测试通过

## C2. 两个仓库标「范围外」

对应：分支保护两条测试里还剩的 `galaxy_chat`（空仓库）、`GalaxyChat_version2`（私有 fork）

1. 左侧 **Tests** → 打开 **Ensure branch protection rules are enforced for administrators (GitHub)**
2. 下方失败列表里找到 **galaxy_chat** 和 **GalaxyChat_version2**
3. 每个右边点 **⋯ → Deactivate resource（停用该资源）**
4. 理由填：“galaxy_chat 为空仓库无代码；GalaxyChat_version2 为外部项目的私有 fork，均非生产代码，范围外。”
5. 对另一条测试 **Application changes reviewed** 里的同样这 2 个仓库，重复 3–4
6. → 两条 GitHub 测试全绿

---

# D. 需要“真做一次再截图”的证据（无法走捷径）

这些要你实际操作一次并上传截图/报告。每条在 Tests 里打开后，右侧有 **Upload evidence / 上传证据** 按钮。

| 测试 | 怎么弄到证据 |
|---|---|
| `vulnerability-scan`（漏洞扫描） | 开 **AWS Inspector**（EC2/ECR 漏洞扫描），扫完截图结果页上传 |
| `vulnerabilities-remediated-sample`（已修复样本） | 从 Inspector 里挑 1-2 个高危、修复后，截“已修复”状态上传 |
| `system-activity-log-settings`（自动告警） | 截 **CloudWatch Alarms** 配置页（有告警规则即可）上传 |
| `access-requests`（访问申请记录） | 截一条给同事开权限的邮件/工单（申请+批准）上传 |
| `access-requests-denied-log`（拒绝日志） | 截一条登录失败/无权限被拒的日志（CloudTrail 或应用日志）上传 |
| `customer-support-site`（客服渠道） | 贴你们的 support 邮箱或帮助页链接 |
| `incident-response-plan-test`（IR 演练） | 组织一次桌面推演（30 分钟走一遍事件响应流程），写个纪要上传。**建议排到审计窗口再做** |

---

# 建议顺序

1. **A1 培训** → 选一次消 2 条 + 后续 2 条证据
2. **B1 供应商认证方式** → 逐个填，快
3. **B2 供应商评估**（做法一附报告）→ 高风险几家
4. **C1 IdP** 打开 populate + 必要时重连
5. **C2** 两个仓库标范围外
6. **A2 访问审查** 在 Vanta 里做一次
7. **D** 那批截图证据，能截的先截，IR 演练放最后

做完 1–6，红的会大幅减少。D 类按你节奏补。
