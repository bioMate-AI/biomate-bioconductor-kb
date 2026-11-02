# 数据库清单：界面（连接器）与后端实际接入的对照

日期：2026-11-01。界面清单来自 `connectors-dialog.tsx` 的 `DB_RAW`（64 行）；后端依据是数据源注册表、联邦检索、研究智能体和 MCP 工具的代码。
状态判断基于代码检索（API 主机名与处理器），不是逐个运行验证；“未发现接入”表示没有找到查询处理器，不等于一定没有。

汇总：可从聊天检索（联邦检索） 22；专用工具/研究智能体 9；仅工作流/脚本/本地数据 15；未发现接入 18；合计 64。

| # | 数据库 | 界面分组 / 类别 | 后端状态 | 说明 |
|---|---|---|---|---|
| 1 | UniProt / Swiss-Prot | 蛋白与结构 / Protein | 可从聊天检索（联邦检索） |  |
| 2 | PDB / RCSB | 蛋白与结构 / Structure | 可从聊天检索（联邦检索） |  |
| 3 | AlphaFold DB | 蛋白与结构 / Structure | 可从聊天检索（联邦检索） |  |
| 4 | EMDB | 蛋白与结构 / Structure | 仅工作流/脚本/本地数据 | 仅冷冻电镜工作流代码中出现 |
| 5 | InterPro | 蛋白与结构 / Protein | 可从聊天检索（联邦检索） |  |
| 6 | STRING | 蛋白与结构 / Protein | 可从聊天检索（联邦检索） |  |
| 7 | Ensembl | 基因组与变异 / Genomics | 可从聊天检索（联邦检索） | 另有研究智能体直接调用（查询、VEP、序列） |
| 8 | NCBI Gene | 基因组与变异 / Genomics | 可从聊天检索（联邦检索） |  |
| 9 | NCBI RefSeq | 基因组与变异 / Genomics | 仅工作流/脚本/本地数据 | 工作流使用的参考序列 |
| 10 | gnomAD | 基因组与变异 / Variants | 可从聊天检索（联邦检索） |  |
| 11 | ClinVar | 基因组与变异 / Variants | 可从聊天检索（联邦检索） |  |
| 12 | dbSNP | 基因组与变异 / Variants | 可从聊天检索（联邦检索） |  |
| 13 | GWAS Catalog | 基因组与变异 / Variants | 专用工具/研究智能体 | 研究智能体直接调用 EBI GWAS API |
| 14 | COSMIC | 基因组与变异 / Variants | 未发现接入 |  |
| 15 | iGenomes (AWS S3) | 基因组与变异 / Reference | 仅工作流/脚本/本地数据 | 工作流使用的参考基因组 |
| 16 | GEO (NCBI) | 组学档案库 / Omics Archive | 专用工具/研究智能体 | 按登记号取回：resolve_accession → Geo Data Connector；无关键词发现 |
| 17 | SRA (NCBI) | 组学档案库 / Omics Archive | 专用工具/研究智能体 | 按登记号经 resolve_accession → fetchngs |
| 18 | ENA (EBI) | 组学档案库 / Omics Archive | 专用工具/研究智能体 | 按登记号（ERR/ERX 等）经 resolve_accession → fetchngs |
| 19 | ArrayExpress (EBI) | 组学档案库 / Omics Archive | 专用工具/研究智能体 | E-MTAB 登记号识别；取回路径未逐一核实 |
| 20 | PRIDE (EBI) | 组学档案库 / Omics Archive | 专用工具/研究智能体 | PXD 登记号识别；取回路径未逐一核实 |
| 21 | EGA | 组学档案库 / Omics Archive | 未发现接入 |  |
| 22 | Metabolights (EBI) | 组学档案库 / Omics Archive | 未发现接入 |  |
| 23 | OmicsDI | 组学档案库 / Omics Archive | 未发现接入 |  |
| 24 | SYNAPSE (Sage Bionetworks) | 组学档案库 / Omics Archive | 未发现接入 |  |
| 25 | MGnify (EBI) | 组学档案库 / Omics Archive | 仅工作流/脚本/本地数据 | 仅宏基因组工作流中出现 |
| 26 | ChEMBL | 化合物与药物 / Chemical / Drug | 可从聊天检索（联邦检索） |  |
| 27 | ChEBI (EBI) | 化合物与药物 / Chemical / Drug | 可从聊天检索（联邦检索） |  |
| 28 | PubChem (NCBI) | 化合物与药物 / Chemical / Drug | 可从聊天检索（联邦检索） |  |
| 29 | DrugBank | 化合物与药物 / Chemical / Drug | 仅工作流/脚本/本地数据 | 仅数据文件中出现（如已上市药物药代参数）；无查询接口 |
| 30 | GTOPDB | 化合物与药物 / Chemical / Drug | 未发现接入 |  |
| 31 | PharmGKB | 化合物与药物 / Chemical / Drug | 未发现接入 |  |
| 32 | MaveDB | 化合物与药物 / Chemical / Drug | 未发现接入 |  |
| 33 | KEGG | 通路与本体 / Pathways | 可从聊天检索（联邦检索） |  |
| 34 | Reactome | 通路与本体 / Pathways | 可从聊天检索（联邦检索） |  |
| 35 | BRENDA | 通路与本体 / Pathways | 仅工作流/脚本/本地数据 | 仅代码中出现；无查询接口 |
| 36 | Gene Ontology (GO) | 通路与本体 / Ontology | 可从聊天检索（联邦检索） |  |
| 37 | HPO | 通路与本体 / Ontology | 可从聊天检索（联邦检索） |  |
| 38 | OMIM | 通路与本体 / Ontology | 未发现接入 | 注册表标为需密钥，无处理器 |
| 39 | Monarch Initiative | 通路与本体 / Ontology | 专用工具/研究智能体 | 研究智能体取表型-基因关联 |
| 40 | Open Targets | 疾病与临床 / Disease / Target | 专用工具/研究智能体 | 靶点识别引擎的主通道（identify_targets）；研究智能体取关联分数 |
| 41 | cBioPortal / TCGA | 疾病与临床 / Disease / Target | 未发现接入 |  |
| 42 | DisGeNET | 疾病与临床 / Disease / Target | 未发现接入 |  |
| 43 | ClinicalTrials.gov | 疾病与临床 / Clinical | 可从聊天检索（联邦检索） | 2026-11-02 新增（官方 API v2，返回登记记录：状态、阶段、申办方、终止原因）；另有 609,551 项完整镜像 |
| 44 | OpenFDA | 疾病与临床 / Clinical | 仅工作流/脚本/本地数据 | 仅一个脚本用它核对批准日期；不是聊天数据源 |
| 45 | IEDB | 疾病与临床 / Immunology | 仅工作流/脚本/本地数据 | 仅一个工作流中出现；无查询接口 |
| 46 | NetMHCpan / NetMHCIIpan | 疾病与临床 / Immunology | 仅工作流/脚本/本地数据 | 仅执行器代码中出现；未见预测接口 |
| 47 | iReceptor | 疾病与临床 / Immunology | 未发现接入 |  |
| 48 | JASPAR | 表观与表达 / Epigenomics | 未发现接入 |  |
| 49 | REGULOMEDB | 表观与表达 / Epigenomics | 未发现接入 |  |
| 50 | REMAP | 表观与表达 / Epigenomics | 未发现接入 |  |
| 51 | miRBase | 表观与表达 / Epigenomics | 仅工作流/脚本/本地数据 | 仅聊天助手文本中出现 |
| 52 | Rfam | 表观与表达 / Epigenomics | 仅工作流/脚本/本地数据 | 仅工作流中出现 |
| 53 | GTEx | 表观与表达 / Expression | 专用工具/研究智能体 | 研究智能体取组织表达中位数 |
| 54 | UCSC Genome Browser | 表观与表达 / Expression | 仅工作流/脚本/本地数据 | Galaxy 的 UCSC Table Browser 导入工具 |
| 55 | PubMed (NCBI) | 文献 / Literature | 可从聊天检索（联邦检索） |  |
| 56 | bioRxiv / medRxiv / arXiv | 文献 / Literature | 可从聊天检索（联邦检索） | bioRxiv/medRxiv 今天新增（经 Europe PMC，标注未经同行评审）；arXiv 仅研究智能体可用 |
| 57 | Europe PMC | 文献 / Literature | 可从聊天检索（联邦检索） |  |
| 58 | Semantic Scholar | 文献 / Literature | 可从聊天检索（联邦检索） |  |
| 59 | IDR / OMERO | 其他 / Imaging | 仅工作流/脚本/本地数据 | 仅一个工作流中出现 |
| 60 | WORMS / IUCN | 其他 / Ecology | 未发现接入 |  |
| 61 | Paleobiology Database | 其他 / Ecology | 未发现接入 |  |
| 62 | Worldclim | 其他 / Ecology | 未发现接入 |  |
| 63 | ENCODE QC Metrics | 其他 / Standards | 仅工作流/脚本/本地数据 | 作为规则/知识使用，不是数据库查询 |
| 64 | GATK Best Practices | 其他 / Standards | 仅工作流/脚本/本地数据 | 作为规则/知识使用，不是数据库查询 |

## 后端有、界面没有的数据源

- 文献：OpenAlex、Crossref（只用于元数据和文献核对）。
- 化合物/基因/结构：BindingDB、Pharos、PDBe。
- 需密钥：Paperclip（无密钥）。
- Galaxy 数据导入工具 30 个：Access Libraries、BioMart（含测试版）、CBI Rice Mart、DICED、EBI SRA、EuPathDB、FlyMine（含测试版）、GenBank、Gramene Mart、HapMap BioMart、HbVar、InterMine、MetabolicMine、Microbial Import、MouseMine、NCBI Datasets、NCBI SRA、RatMine、UCSC Table Browser（含归档与测试版）、WormBase（含测试版）、YeastMine、ZebrafishMine、modENCODE（果蝇、线虫）、modMine。

## 观察

- 界面展示 64 个数据库，其中约 33 个在后端没有查询接口，用户容易以为都能用。
- 注册表只计入联邦检索等四类入口，研究智能体和专用工具里的接入（Open Targets、GWAS Catalog、GTEx、Monarch、GEO 登记号）原先没有被计入。
