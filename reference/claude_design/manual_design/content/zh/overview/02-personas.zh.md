# BioMate 适合谁——找到你的入口 > 一句话说明：读完这一页，你会知道从你的角色出发，到达所需章节的最短路径。 BioMate 在同一个对话里服务多种用户。在下面找到你自己，然后沿着路径走——每一步都链接到教你具体怎么做的章节。 ## 湿实验 PI / 实验科学家（很少或不做计算）
你有数据（或一个登录号）和一个问题；你想要的是答案，而不是一条流水线。
- 从[起始页](../modules/I01-getting-started-cold-start.md)开始——用大白话描述你的目标。
- 提一个问题 → 得到一个 [Instant 带引用的回答](../modules/I03-search-and-evidence.md)。
- 有数据 → 在[消息框](../modules/I02-composer-talking-to-biomate.md)里附上它；在任何东西运行之前，BioMate 会先检查它的[导入质量](../modules/I05-files-and-dataset-object.md)。
- 运行一条经过验证的流水线 → [运行分析](../modules/I06-running-an-analysis.md)；在[运行后报告](../modules/I09-reports-and-reproducibility.md)里阅读结果。
- 你所在领域的章节（例如[转录组学](../domains/transcriptomics.md)、[单细胞](../domains/single-cell.md)）就是为你写的——以用例为先，重解读而非统计细节。 ## 生物信息学家 / 计算科学家
你需要掌控力、溯源和可复现性。
- 调整参数，并阅读[完整步骤视图](../modules/I07-full-step-view-provenance.md)（按来源区分的参数、渲染视图⇄原始视图）。
- 依靠[可复现记录](../modules/I09-reports-and-reproducibility.md)——SHA-256 校验和、软件、引用、带版本的方法说明。
- 把[数据集、运行、输出当作对象](01-object-model.md)来看待；在整个工作中引用它们。
- 训练/适配一个[模型](../modules/I10-models.md)；在[设计与生成](../modules/I11-design-and-generate.md)中设计候选物。 ## 药物发现 / 法规事务科学家
你正朝着一次申报前进。
- 旗舰路径：[药物发现 → IND](../domains/drug-discovery-ind.md)——ADMET → 自动循环 → PBPK → IND §2.6，并附带 [21 CFR 11 审计追踪](../domains/cro-regulatory.md)。
- [药理与临床](../domains/pharmacology-clinical.md)，涵盖 PopPK / BOIN / PGx。
- 在依赖它之前，先了解如实的适用范围：[附录 E](../appendix/E-coverage-and-roadmap.md)。 ## 核心平台 / 实验室管理员
你为许多用户运营 BioMate。
- [项目、角色与协作](../modules/I04-projects-instructions-collaboration.md)——owner / editor / viewer，常驻指令与仅供人看的笔记，计划。
- [连接器与技能](../modules/I12-connectors-and-skills.md)，以及[账单与两条通道的计费模型](../modules/I13-billing-quotas-two-lane-cost.md)。
- BioMate 能访问哪些数据：[数据库与检索](../data/II01-workflow-catalog-and-routing.md)，以及[登录号解析](../data/II02-public-datasets-accession-resolver.md)。 > **提示。** 无论你是什么角色，入口都一样：描述目标。路由器会决定走 Instant 还是 Cloud、属于哪个领域——你不需要知道任何工作流名称。
