// Information architecture — mirrors docs/user-manual/README.md (Index) + tutorials/README.md.
// [route, EN label, ZH label]. Route = path under content/ without .md. Tutorials resolve to zh/<id>.zh.md in 中文.
window.MANUAL_NAV = [
 {id:"p0", num:"0", en:"Overview & orientation", zh:"概览与入门", items:[
  ["overview/00-what-is-biomate","What BioMate is","BioMate 是什么"],
  ["overview/01-object-model","The object model","对象模型"],
  ["overview/02-personas","Who BioMate is for","适用人群"],
  ["overview/03-first-analysis-5min","Your first analysis in 5 minutes","5 分钟完成第一次分析"]]},
 {id:"p1", num:"I", en:"Function modules", zh:"通用功能模块", items:[
  ["modules/I01-getting-started-cold-start","I.1 · The cold start","I.1 · 起始页"],
  ["modules/I02-composer-talking-to-biomate","I.2 · The composer","I.2 · 消息框"],
  ["modules/I03-search-and-evidence","I.3 · Search & evidence","I.3 · 检索与证据"],
  ["modules/I04-projects-instructions-collaboration","I.4 · Projects & collaboration","I.4 · 项目、指令与协作"],
  ["modules/I05-files-and-dataset-object","I.5 · Files & the dataset object","I.5 · 文件与数据集对象"],
  ["modules/I06-running-an-analysis","I.6 · Running an analysis","I.6 · 运行分析"],
  ["modules/I07-full-step-view-provenance","I.7 · Full step view & provenance","I.7 · 完整步骤视图与溯源"],
  ["modules/I08-outputs-viewers-interactive","I.8 · Outputs & viewers","I.8 · 输出与查看器"],
  ["modules/I09-reports-and-reproducibility","I.9 · Reports & reproducibility","I.9 · 报告与可复现性"],
  ["modules/I10-models","I.10 · Models","I.10 · 模型"],
  ["modules/I11-design-and-generate","I.11 · Design & generate","I.11 · 设计与生成"],
  ["modules/I12-connectors-and-skills","I.12 · Connectors & skills","I.12 · 连接器与技能"],
  ["modules/I13-billing-quotas-two-lane-cost","I.13 · Billing & quotas","I.13 · 账单与配额"],
  ["modules/I14-instruments-and-lab-connectivity","I.14 · Instruments & lab connectivity","I.14 · 仪器与实验室连接"]]},
 {id:"p2", num:"II", en:"Databases & retrieval", zh:"数据库与检索支持", items:[
  ["data/II01-workflow-catalog-and-routing","II.1 · Workflow catalog & routing","II.1 · 工作流目录与路由"],
  ["data/II02-public-datasets-accession-resolver","II.2 · Public datasets & accessions","II.2 · 公共数据集与登录号解析"],
  ["data/II03-literature-and-evidence-retrieval","II.3 · Literature retrieval","II.3 · 文献与证据检索"],
  ["data/II04-reference-data-and-indexes","II.4 · Reference data & indexes","II.4 · 参考数据与索引"],
  ["data/II05-memory-and-project-knowledge","II.5 · Memory & project knowledge","II.5 · 记忆与项目知识"]]},
 {id:"p3", num:"III", en:"Function areas by domain", zh:"按领域划分的功能", items:[
  ["domains/drug-discovery-ind","Drug discovery → IND","药物发现 → IND"],
  ["domains/transcriptomics","Transcriptomics","转录组学"],
  ["domains/cryo-em","Cryo-EM","冷冻电镜"],
  ["domains/single-cell","Single-cell RNA-seq","单细胞 RNA-seq"],
  ["domains/variant-calling","Variant calling","变异检测"],
  ["domains/structural-biology","Structural biology","结构生物学"],
  ["domains/pharmacology-clinical","Pharmacology & clinical","药理与临床"],
  ["domains/multi-omics","Multi-omics","多组学"],
  ["domains/epigenomics","Epigenomics","表观基因组学"],
  ["domains/proteomics","Proteomics","蛋白质组学"],
  ["domains/metabolomics","Metabolomics","代谢组学"],
  ["domains/metagenomics","Metagenomics","宏基因组学"],
  ["domains/cro-regulatory","CRO & regulatory","CRO 与法规"]]},
 {id:"app", num:"A–E", en:"Appendices", zh:"附录", items:[
  ["appendix/A-glossary","A · Glossary","A · 术语表"],
  ["appendix/B-file-formats","B · File formats","B · 文件格式"],
  ["appendix/C-qc-gate-reference","C · QC gate reference","C · QC 关卡参考"],
  ["appendix/D-troubleshooting-routing","D · Troubleshooting","D · 故障排查"],
  ["appendix/E-coverage-and-roadmap","E · Coverage & roadmap","E · 覆盖范围与路线图"]]},
 {id:"tut", num:"T", en:"Tutorials", zh:"教程", tutorial:true, groups:[
  {en:"Core journey", zh:"核心路径", items:[
   ["tutorials/T0-getting-started","T0 · Getting started","T0 · 入门"],
   ["tutorials/T1-design-and-generate","T1 · Design & generate","T1 · 设计与生成"],
   ["tutorials/T2-models-and-the-closed-loop","T2 · Models & the closed loop","T2 · 模型与闭环"],
   ["tutorials/T3-running-a-workflow-and-reading-the-report","T3 · Run a workflow & read the report","T3 · 运行工作流并读懂报告"],
   ["tutorials/T4-bringing-your-own-data","T4 · Bringing your own data","T4 · 带入你自己的数据"],
   ["tutorials/T5-viewing-your-results","T5 · Viewing your results","T5 · 查看结果"],
   ["tutorials/T6-connecting-instruments","T6 · Connecting instruments","T6 · 连接仪器"],
   ["tutorials/T7-projects-and-collaboration","T7 · Projects & collaboration","T7 · 项目与协作"],
   ["tutorials/T8-reports-edit-and-export","T8 · Reports — edit & export","T8 · 报告编辑与导出"],
   ["tutorials/T9-connecting-data-and-tools","T9 · Connecting data & tools","T9 · 连接数据源与工具"],
   ["tutorials/T10-exploring-your-datasets","T10 · Exploring your datasets","T10 · 探索数据集"],
   ["tutorials/T11-drug-development-end-to-end","T11 · Drug development, end to end","T11 · 药物研发全流程"]]},
  {en:"Cold-start modules", zh:"起始页模块", items:[
   ["tutorials/M1-search-and-evidence","M1 · Search & evidence","M1 · 检索与证据"],
   ["tutorials/M2-data-analysis","M2 · Data analysis","M2 · 数据分析"]]},
  {en:"Navigation & workflow panel", zh:"导航与工作流面板", items:[
   ["tutorials/S1-sidebar-navigation","S1 · The sidebar","S1 · 侧边栏"],
   ["tutorials/W1-workflow-panel-tabs","W1 · Workflow panel","W1 · 工作流面板"],
   ["tutorials/W2-after-run-panel","W2 · After-run panel","W2 · 运行后面板"],
   ["tutorials/W3-full-step-view","W3 · Full step view","W3 · 完整步骤视图"]]},
  {en:"Per-instrument", zh:"按仪器", items:[
   ["tutorials/instruments/basespace-sequencing","Illumina BaseSpace","Illumina BaseSpace"],
   ["tutorials/instruments/cryoem-reconstruction","Cryo-EM reconstruction","冷冻电镜三维重构"],
   ["tutorials/instruments/qpcr-quantification","qPCR (ΔΔCt)","qPCR（ΔΔCt）"],
   ["tutorials/instruments/flow-cytometry-gating","Flow cytometry","流式细胞术"],
   ["tutorials/instruments/lcms-proteomics-metabolomics","LC-MS","LC-MS"],
   ["tutorials/instruments/advanced-proteomics-mass-spec","Advanced mass-spec proteomics","质谱蛋白质组学进阶"],
   ["tutorials/instruments/plate-reader-assays","Plate reader","酶标仪"],
   ["tutorials/instruments/nanopore-minknow","Nanopore MinKNOW","Nanopore MinKNOW"],
   ["tutorials/instruments/microscopy-pathology-imaging","Microscopy & pathology","显微与病理影像"],
   ["tutorials/instruments/sample-qc-instruments","Sample-QC instruments","样本质控仪器"],
   ["tutorials/instruments/somatic-tumor-sequencing","Somatic / tumour sequencing","体细胞 / 肿瘤测序"],
   ["tutorials/instruments/benchling-eln-lims","Benchling ELN / LIMS","Benchling ELN / LIMS"],
   ["tutorials/instruments/opentrons-liquid-handling","Opentrons liquid handling","Opentrons 液体处理"],
   ["tutorials/instruments/sila2-devices","SiLA2 devices","SiLA2 设备"]]}]}
];
// 中文 chapter translations present under content/zh/<route>.zh.md (tutorials use content/tutorials/zh/). Others fall back to English with a notice.
window.MANUAL_ZH=["overview/00-what-is-biomate","overview/01-object-model","overview/02-personas","overview/03-first-analysis-5min","modules/I01-getting-started-cold-start"];
window.MANUAL_I18N = {
 en:{title:"User Manual",search:"Search the manual",searchHint:"Type to search all chapters",noResults:"No matches.",onPage:"On this page",home:"Manual home",part:"Part",prev:"Previous",next:"Next",trial:"Free trial:",chapters:"chapters",tutorials:"tutorials",
  enOnly:"",zhMissing:"",drafted:"Drafted · verifying",verified:"Verified",cov:"Coverage",covV:"verified",covC:"corrected in text",covP:"pending live check",covR:"not yet available",covOpen:"See what is not yet available",roadmap:"Not yet available",roadmapLbl:"Roadmap — not available today",shotTag:"Current build",shotPending:"Screenshot to be captured",shotNote:"Captured from the current build; the interface is being refreshed and may differ.",close:"Close",
  homeEyebrow:"BioMate · reference",homeTitle:"BioMate User Manual",homeLede:"How to ask BioMate for something, what runs when you do, how to read what comes back — and, listed separately, what is not yet available.",start:"Start here",honestyLbl:"How this manual is kept honest",honesty:"Every function documented as available has been checked against the product. Anything not yet built or not yet verified appears only under Appendix E — Coverage & roadmap.",openRoadmap:"Open Appendix E",
  tip:"Tip",pitfall:"Pitfall",qc:"QC gate",note:"Note",tutHub:"Task-first walkthroughs, each with an honest-limits section.",menu:"Menu",copied:"Link copied",copyLink:"Copy link to this section"},
 zh:{title:"用户手册",search:"搜索手册",searchHint:"输入关键词，搜索全部章节",noResults:"没有找到匹配内容。",onPage:"本页内容",home:"手册首页",part:"第",prev:"上一篇",next:"下一篇",trial:"免费试用：",chapters:"章",tutorials:"篇教程",
  enOnly:"本章中文版正在翻译中，暂时显示英文原文。",zhMissing:"",drafted:"已起草 · 核验中",verified:"已核验",cov:"覆盖情况",covV:"项已核验",covC:"项已在正文中更正",covP:"项待线上复核",covR:"项暂未提供",covOpen:"查看暂未提供的功能",roadmap:"暂未提供",roadmapLbl:"路线图 —— 目前尚不可用",shotTag:"当前版本",shotPending:"截图待补拍",shotNote:"截图来自当前版本；界面正在更新，实际可能略有不同。",close:"关闭",
  homeEyebrow:"BioMate · 参考文档",homeTitle:"BioMate 用户手册",homeLede:"如何向 BioMate 提出需求、提交后会运行什么、如何读懂返回的结果——以及单独列出的、目前尚未提供的功能。",start:"从这里开始",honestyLbl:"本手册如何保证如实",honesty:"凡标注为可用的功能，均已对照产品核验。尚未构建或尚未核验的内容，只出现在附录 E「覆盖范围与路线图」中。",openRoadmap:"打开附录 E",
  tip:"提示",pitfall:"注意",qc:"QC 关卡",note:"说明",tutHub:"以任务为主线的分步教程，每篇都附有「如实说明局限」一节。",menu:"目录",copied:"链接已复制",copyLink:"复制本节链接"}
};
