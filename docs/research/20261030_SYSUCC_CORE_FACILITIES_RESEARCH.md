# SYSUCC (中山大学肿瘤防治中心) + State Key Lab of Oncology in South China — Core Facilities, Instruments & Bioinformatics Capability

**Prepared:** 2026-10-30 (web research, Chinese + English sources)
**Audience:** BioMate BD team
**Scope:** in-house instruments, core facilities, data-analysis / bioinformatics service capacity, organoid/PDX/HTS, reliance on SYSU shared platforms and outsourced vendors, molecular diagnostics NGS.

> **Evidence caveats (read first)**
> - The State Key Lab site `skl.sysucc.org.cn` returned **"网站正在维护中" (under maintenance)** when fetched on 2026-10-30. Platform-page details below come from search-engine snapshots of pages dated **2024-04-29**.
> - The Experimental Research Dept (实验研究部) intro page says "更新日期 2026-06-18", but its instrument list still names an **Illumina HiSeq**, so parts of the list are probably legacy text. Treat model names as indicative, not as a current inventory.
> - The Molecular Diagnostics (分子诊断科) intro page describes a 2012–2014-era setup (ABI 7500/7900HT, CEQ8000, Sequenom). Newer procurement notices (2023–2026) show the department has moved on to NGS. Use the procurement notices as the current picture.
> - Many procurement aggregators (千里马, 乙方宝, 马蜂盯标) hide winning vendors behind paywalls. Where the winner is hidden, this doc says so.
> - "Not found" means not found in public web sources. It does **not** mean the capability is absent.

---

## 1. Summary — maturity by area

| Area | Maturity | One-line basis |
|---|---|---|
| NGS data generation (bulk, single-cell, genotyping) | **Mature** | In-house high-throughput sequencing and genotyping platform (Illumina, 10x Genomics, SPLIT-seq, iScan), plus heavy PI-level outsourcing |
| Bioinformatics / data analysis service | **Partial (demand > supply)** | A bioinformatics service platform exists and strong computational PIs (Ren Jian, Zuo Zhixiang) are on staff. A ¥1.40M bioinformatics HPC cluster was awarded 2026-09-28. Yet PI outsourcing tenders in 2026 still require vendors to provide "all bioinformatics analysis needed for publication" plus free training |
| Single-cell / spatial | **Partial** | 10x and SPLIT-seq are in-house. Spatial work (Visium FFPE, Stereo-seq) appears in SYSUCC papers, but no in-house spatial instrument (Visium CytAssist, Xenium, CosMx, Stereo-seq) was found |
| Mass-spec proteomics / metabolomics | **Partial → gap** | A "Bruker protein mass spec system" (model truncated, likely MALDI-TOF) and a microbial-identification MS are listed. No high-end Orbitrap or timsTOF was found at SYSUCC. The SYSU Analysis & Test Center has Orbitrap Exploris 480, TIMS-TOF, and new 2026 proteomics/metabolomics prep stations |
| Flow cytometry | **Mature**; CyTOF **not found** | High-end sorters and analyzers in place. A ¥4.25M "intelligent sorter" tender ran in 2025, and a 4-laser analyzer tender is open with bids due 2026-11-09. No CyTOF or imaging mass cytometry found at SYSUCC |
| Imaging / digital pathology / pathology AI | **Mature** | Super-resolution (new ¥4.8M SIM tender, 2026), confocal, light-sheet, spinning-disk, high-content imaging, and 5 high-throughput whole-slide scanners (2023). Pathology AI is published (CRISP foundation model, GAS platform) and co-developed with Bio-totem |
| Cryo-EM / structural | **Gap at SYSUCC; served by SYSU** | Only protein crystallization and ITC listed in-house. SYSU's central cryo-EM system (Krios G4, Glacios 2, Aquilos 2) officially launched 2025-12-05 |
| Organoids / PDX / HTS | **Partial** | Organoid work is PI-led (e.g., neurosurgery patents licensed to 创芯国际 for ¥1M, 2023-12). NSG mouse breeding, high-content imaging, and a med-chem synthesis platform exist. No central organoid biobank or HTS screening core found |
| Clinical cohorts / clinical data / big data | **Mature (data) / partial (statistics)** | Big-data platform and AI lab since 2018, RDD data-deposit platform since 2017, central randomization 2021, EDC build in 2025. Only 2 dedicated statisticians in Clinical Research Dept |
| Molecular diagnostics NGS | **Partial → growing** | mNGS and MRD NGS assays are sourced via reagent + leased-instrument procurement (2023), plus a 2025 "high-throughput test reagents" survey. In 2026-05 the IT center surveyed servers for a molecular-diagnostics bioinformatics data-integration compute platform |

**Top-line takeaways for BD**
- **The clearest BioMate opening is analysis capacity, not instruments.** SYSUCC generates a lot of omics data, both in-house and outsourced. PIs still buy analysis bundled with vendor sequencing ("提供能够支撑文章发表的所有信息分析服务，直至文章发表" plus "免费的信息分析培训"). That is the job BioMate's validated workflows do.
- **SYSUCC is actively building its own bioinformatics compute** (2026 HPC award; 2026 molecular-diagnostics compute platform survey). Pitch BioMate as the workflow and AI layer that runs on or alongside that compute, not as a replacement for it.
- **Avoid leading with pathology AI or clinical big data.** Those are SYSUCC's own flagship strengths (CRISP, GAS, 863 big-data program, AI lab), and we would look redundant.

---

## 2. Detailed findings

### 2.1 Core facilities / public technology platforms

**SYSUCC Experimental Research Dept (实验研究部): official platform list**
Source: [科室简介 — 实验研究部](http://www.sysucc.org.cn/department/introduction/185) (page footer: 更新日期 2026-06-18)

- Lab area: 33,721 m² across 越秀院区 (8,994), SYSU East Campus (2,354), and 黄埔院区 / 腾飞园 (22,373). The lab runs on a PI system with 32 independent lab suites plus 13 + 67 benches.
- **Nine public service platforms are named:**
  - 生物资源库服务平台 (biobank)
  - 实验动物中心服务平台 (animal center)
  - 公共仪器服务平台 (shared instruments)
  - **生物信息服务平台 (bioinformatics service platform)**
  - 蛋白抗体技术服务平台 (protein/antibody)
  - **高通量测序与基因分型平台 (high-throughput sequencing & genotyping)**
  - 肿瘤微生态技术服务平台 (tumor microbiome)
  - 药物化学合成技术服务平台 (medicinal chemistry synthesis)
  - **单分子测序平台 (single-molecule sequencing)**
- **Instruments listed (no models given for most):**
  - Flow: high-end flow sorter, analytical flow cytometers
  - PCR and sequencing: droplet digital PCR, qPCR, Illumina HiSeq
  - Biophysics: biomolecular interaction analyzer (SPR-type), ITC, protein chromatography, protein crystallization robot
  - Imaging and pathology: whole-slide pathology scanner and analysis system, laser-capture microdissection, high-content imaging system, tissue-microarray scanner, super-resolution microscope, high-resolution confocal, light-sheet microscope, spinning-disk live-cell workstation
  - Other: X-ray irradiator, biochip system, HPLC, drug-concentration analyzer, 2D electrophoresis, **protein mass spectrometry system**, high-throughput mammalian cell phenotype microarray, Seahorse-type cell energy metabolism analyzer, automated microbial identification system
- Public technical services named: super-resolution imaging, immunofluorescence imaging, pathology sectioning, gene sequencing, CGH, cell sorting.
- The animal center provides SPF rodents, large animals, and C57 / **NSG** breeding. It offers "animal experiment venue and **result analysis** services" to internal and external users.

**State Key Lab (华南恶性肿瘤防治全国重点实验室) platform list**
Source: postdoc recruitment article, WeChat ([link](https://mp.weixin.qq.com/s/hzk5j0zWXeuRuSwfOmdWfA)), undated (circa 2025). It states the restructured lab has **107 PIs** across 2.65万 m² (Yuexiu, Huangpu 腾飞园, University Town). Platforms named:
- 肿瘤样本资源库及医学大数据平台
- 多组学研究平台
- **生物信息学和超级计算平台**
- 超分辨细胞显微成像平台
- 小动物分子影像平台
- 放射生物医学平台
- 模式动物中心
- 药物化学合成平台
- 抗体蛋白平台
- 肿瘤微生态研究平台

The SKL home page instrument carousel (search snapshot of [skl.sysucc.org.cn](https://skl.sysucc.org.cn/); site down 2026-10-30) lists:
- Olympus laser confocal; Olympus and Nikon research microscopes
- Automated IHC/ISH stainer
- Ultra-fast flow sorter and flow cytometer
- **MD SpectraMax multimode plate reader**
- qPCR; cell counter
- **"蛋白质谱系统 BRUKER u…"** (model truncated, likely ultrafleXtreme MALDI-TOF; unverified)
- X-ray irradiator
- Hitachi and Beckman ultracentrifuges; GE AKTA; phosphor imager

An older SKL profile ([antpedia](https://m.antpedia.com/lab/2231.html), undated, probably circa 2015–2018) adds **small-animal PET/CT, small-animal photoacoustic imaging**, a live-cell imaging system, and an automated cell-culture bioreactor.

**High-throughput sequencing & genotyping platform (高通量测序与基因分型平台)**
Source: [SKL platform page AID=2924](https://skl.sysucc.org.cn/info/ArticleShow.aspx?AID=2924), dated **2024-04-29** (page now 404 / site in maintenance)
- Located at University Town, SYSU South Basic Lab Building F202. Staff: 1 lead and 4 technicians.
- Instruments: HiSeq; **10x Genomics** and **SPLIT-seq** (self-optimized) for single-cell; **Illumina iScan** genotyping (Omni ZhongHua-8 GWAS chip); an IBM "千核 PB级" (thousand-core, petabyte-scale) compute cluster.
- Services, **paid, for SYSUCC and for internal and external clients**: WGS, WES, RNA-seq, single-cell RNA/genome/ATAC, genotyping, and custom services (target capture, TMB, methylation, genome structure).
- **Data analysis is explicitly offered:** "有偿提供高通量测序、单细胞测序、基因分型及数据分析服务"; RNA-seq includes "建库、测序、信息分析及联合分析".
- **Assessment:** this is a real analysis service, but staffing (4 technicians) is small relative to 107 PIs. The HiSeq generation is old. No NovaSeq X or DNBSEQ-T7 was found in-house, while PIs specify NovaSeq X and DNBSEQ-T7 in outsourcing tenders (see 2.4).

**Tumor microbiome platform (肿瘤微生态技术服务平台)**
Source: [SKL AID=2923](http://skl.sysucc.org.cn/Info/ArticleShow.aspx?AID=2923), 2024-04-29
- Located at Huangpu 腾飞园 F栋 8F. Staff: 1 lead and 3 technicians. Around 20 instruments, including microbial Raman identification, an anaerobic workstation, and **Autobio microbial MS identification**.
- Services include **microbiome data analysis integrated with clinical, metabolome, and single-cell data**, plus 16S full-length (V1–V9) third-generation library prep.

**Single-molecule sequencing platform (单分子测序平台):** named, but **no instrument model was found** (PacBio vs ONT unknown).
**Bioinformatics service platform (生物信息服务平台):** named, but **no public service menu was found.**

**Recent instrument procurement by 实验研究部 (evidence of current investment)**

| Date | Item | Budget / award | Source |
|---|---|---|---|
| 2024-11 | 实验室设备采购项目 (中大招(货)[2024]303号) | Awarded ¥1,259,500 to 广州市东方科苑进出口; item not disclosed | [SYSU bidding](https://bidding.sysu.edu.cn/node/16839) |
| 2025-09-29 | 智能流式细胞分选仪 (中大招(货)[2025]165号) | Budget ¥4.25M; winner not found | [yiqi.com](https://www.yiqi.com/news/detail_10024426.html) |
| 2025-11-06 | 流式细胞分析仪 market survey (4 lasers, 13 colors) | — | [qianlima](https://www.qianlima.com/bid-551314072.html) |
| 2026-01-18 → 2026-09-01 | 超分辨显微镜 (2D/3D-SIM, TIRF) | Budget ¥4.8M, domestic product only, bid opening 2026-09-22 | [sysucc node/11749](http://www.sysucc.org.cn/node/11749), [ccgp](http://www.ccgp.gov.cn/cggg/zygg/gkzb/202609/t20260901_27243380.htm) |
| 2026-07-20 | 生物学X射线辐照仪 (锐源 RS2000) | ¥1.25M | [ccgp](http://www.ccgp.gov.cn/cggg/zygg/zbgg/202607/t20260720_26970622.htm) |
| 2026-09-30 / extended 2026-10-22 | 实验研究部流式细胞分析仪 (CLF0126GZ06ZC72) | Bids due 2026-11-09 | [ccgp](http://www.ccgp.gov.cn/cggg/zygg/gzgg/202610/t20261022_27546338.htm) |

No SYSUCC tender in 2024–2026 was found for sequencers, high-end LC-MS, spatial-omics instruments, CyTOF, or cryo-EM.

### 2.2 Bioinformatics / big-data / AI groups

**Research groups (computational PIs on staff)**
- **Ren Jian (任间)** ([SYSU profile](https://lifesciences.sysu.edu.cn/zh-hans/teacher/1203); [renlab.org](https://renlab.org/people.html)): Professor, jointly appointed at SYSUCC since 2014; "**Director, Bioinformatics Center, SYSU**".
  - Focus: AI-based bioinformatics platforms, PTM and RNA-modification prediction, tumor multi-omics, databases.
  - Output: 30+ tools and databases, 18 NAR papers. Led a "基于天河二号超级计算机的肿瘤多组学数据分析平台" project (2016–17).
- **Zuo Zhixiang (左志向)** ([SYSUCC profile](http://www.sysucc.org.cn/node/7646)): Professor at SYSUCC since 2022.
  - Focus: RNA epigenetics, big-data platforms, algorithms and pipelines.
  - Notable outputs: **MeRIPseqPipe, built on Nextflow** (Bioinformatics 2022), TIGER, RMVar, RM2Target. Co-author on Nat Genet, Cancer Cell, and Cell Res papers.
  - This group already writes Nextflow pipelines, which is directly comparable to BioMate's stack.
- **Bei Jinxin (贝锦新)** ([IAS-HK profile](https://iashk.sysu.edu.cn/zh-cn/teacher/115)): chief PI and deputy head of the Experimental Research Dept. Built a "**多组学数据生成与分析平台**" covering WGS, WES, scRNA, spatial, and epigenome data. Led the SYSU Precision Medicine Center experimental platform 2016–2022. Published NPC single-cell and spatial atlases (Nat Commun 2021, 2024) and a COVID single-cell atlas (Cell 2021). He Shuai (何帅, associate researcher) focuses on single-cell and spatial multi-omics ([GDPMAA 2025-09](http://m.gdpmaa.com/home/Meeting/cententshow/action/speakers/meetingid/2575/id/36490)).
- **Xu Ruihua (徐瑞华)**, Director and President: digestive-cancer big-data platform and the qPhos database ([sysucc node/2945](https://www.sysucc.org.cn/node/2945), 2018); led the 863 "恶性肿瘤大数据" program.
- **Huang Peng / Hu Yumin** (SYSUCC), with Li Weizhong (Zhongshan School of Medicine): **DeepMSProfiler**, end-to-end deep learning for LC-MS metabolomics (Nat Commun 2024-08) ([SYSU news](https://www.sysu.edu.cn/news/info/2331/1285171.htm)).
- **Pathology AI (Cai Muyan 蔡木炎, Xie Dan 谢丹):**
  - **CRISP**: frozen-section foundation model, 100k+ slides, 2,000+ patients prospective ([arXiv 2510.04861](https://doi.org/10.48550/arxiv.2510.04861), 2025-10)
  - **GAS**: intraoperative AI platform ([npj Digit Med 2025-07-20](https://doi.org/10.1038/s41746-025-01808-7))
  - Pathology dept (Sun Peng): AI TIL scoring, IHC and frozen-section image enhancement, all co-developed with **Bio-totem 生物图腾** ([sysucc node/4253](https://sysucc.org.cn/node/4253); [bio-totem](https://www.bio-totem.com/list/post/3096704/))

**Institutional IT / big data**
- Information Center ([科室简介/88](https://sysucc.org.cn/department/introduction/88), updated 2020-09): 22 staff, including an **AI lab of 2 people**. Big-data platform and AI lab established 2018. Self-developed AI-assisted diagnosis and **AI radiotherapy target contouring** live since 2019.
- Specialty databases include the CSCO colorectal standard dataset, plus a data platform shared across dozens of colorectal hospitals in the medical alliance ([CACA 2020-11](http://www.caca.org.cn/system/2020/11/18/020046275.shtml)).
- 2025-04: SYSUCC hosted the Turkish MoH delegation specifically on "clinical medical big data and AI" ([english.sysucc](https://english.sysucc.org.cn/info_62.aspx?itemid=1006)). This signals institutional pride in these capabilities.

**Bioinformatics compute investment (2026)**
- **生信高性能服务平台(2026年)采购项目**, GC-HGX260773. Awarded 2026-09-28; budget ¥2.10M, award **¥1,396,500**. Equipment: 2 × Lenovo WR5220 G3 large-memory nodes, 1 × **Lenovo WA5680 G3 GPU node**, 1 × storage node, all with 10-year service. Winner's name is hidden; address 广州黄埔科学大道48号 ([dingbiao](https://www.dingbiao.com/zhaobiao/c4e201f861d14fb9e19e5f8da4f9e83c.html); [chinabidding](http://www.chinabidding.org.cn/BidInfoDetails_bid_27172464.html)).
- **分子诊断数据整合分析计算平台建设项目** market survey, **2026-05-11**: the IT center will buy servers "为了建设分子诊断科生信数据整合分析应用" ([qianlima](https://www.qianlima.com/bid-595994414.html)).
- **Interpretation:** this is a modest cluster (4 nodes), not a large HPC buildout. It fits a team that runs its own pipelines but needs workflow, software, and analyst capacity on top.

**Bioinformatics service to faculty:** a named "生物信息服务平台" exists, and the sequencing platform sells analysis. No public menu, price list, or staffing for the bioinformatics service platform was found.

### 2.3 Organoid / drug screening / PDX / HTS

- **Organoids:** PI-led, with no central core found.
  - Neurosurgery (牟永告) built pituitary-tumor and glioblastoma organoid models, with 2 patents, and **licensed them to 创芯国际 for ¥1M** (2023-12-20, [sysucc node/7420](https://www.sysucc.org.cn/node/7420)). 创芯国际 will commercialize.
  - SYSUCC may therefore rely on that partner for organoid drug-sensitivity services. This is an inference and was not verified.
- **Other SYSU organoid / drug-screening capacity (not SYSUCC):**
  - SYSU First Affiliated Hospital: BTC organoid biobank (61 PDOs), drug screening, PDOX ([SYSU news 2024-01-11](https://www.sysu.edu.cn/news/info/2331/1086481.htm))
  - SYSU Seventh Hospital: GI organoid high-throughput drug-sensitivity platform ([Molecular Devices webinar 2022](https://www.moleculardevices.com/newsroom/news/2022-danaher-organiod-research-innovation))
  - A SYSU PDC/PDO/PDX multidimensional HTS platform for lenvatinib-resistant HCC (Acta Pharm Sin B; [bioon](https://news.bioon.com/article/176d81e423ec.html)); the institution was not confirmed as SYSUCC
- **PDX:** NSG breeding and a model-animal center exist, and the animal center offers "result analysis". No formal PDX bank was found.
- **HTS:** in-house enablers are the high-content imaging system, the medicinal-chemistry synthesis platform, and an SPR/ITC/crystallization robot. **No compound library, automated HTS line, or screening core was found.** SYSU School of Pharmaceutical Sciences has DEL, virtual-screening, and AI drug-design groups ([sps.sysu.edu.cn](https://sps.sysu.edu.cn/department/Medicinal-chemistry)).

### 2.4 Use of SYSU shared platforms and outsourced vendors

**SYSU shared platforms available to SYSUCC researchers**
- **SYSU large-instrument sharing platform** ([sharing.sysu.edu.cn](https://sharing.sysu.edu.cn/home)) went live **2025-01** ([中山医学院 notice](https://zssom.sysu.edu.cn/article/11070)). All instruments of ¥500k or more must be listed, and SYSU users get one portal for booking and billing.
- **SYSU Analysis & Test Center (分析测试中心) mass spectrometry unit** has 15 MS systems ([iarc](https://iarc.sysu.edu.cn/taxonomy/term/117)):
  - 2 Orbitrap LC-MS
  - IM-Q-TOF with DESI imaging
  - Trapped-ion-mobility TOF (timsTOF-class)
  - Triple quads
  - MRT
  - MALDI-TOF imaging
- The Shenzhen sub-center opened an **Orbitrap Exploris 480** and **SCIEX 6500+** for proteomics and metabolomics in 2025-03 ([iarc/966](https://iarc.sysu.edu.cn/article/966)).
- 2026-10-12: the center awarded a **metabolomics automated prep station (¥1.34M) and a proteomics prep station (¥0.91M)** ([dingbiao](https://www.dingbiao.com/zhaobiao/37edb7d8cc6f73522f08d381c94189ae.html)). SYSU is scaling central omics MS, which SYSUCC PIs can use.
- **SYSU cryo-EM system:**
  - Krios G4 trial 2025-03 at 1.36 Å on ferritin ([iarc/936](https://iarc.sysu.edu.cn/article/936)), plus a Talos L120C
  - **Officially launched 2025-12-05** with Krios G4, Glacios 2, Aquilos 2 for SPA, cryo-ET, and MicroED ([SYSU news](https://www.sysu.edu.cn/news/info/2161/1395281.htm))
  - Located at SYSU East Campus, where SYSUCC also has lab space
- **SYSU Precision Medicine Science Center biobank:** 3 automated −80 °C demonstration biobanks, one at SYSUCC, with a combined 8 million-sample capacity ([SYSU news](https://www.sysu.edu.cn/news/info/2161/513171.htm)). SYSUCC's own NPC biobank had about 100k samples by 2015 ([sciencenet 2015-07](https://news.sciencenet.cn/htmlnews/2015/7/322733.shtml)).

**Outsourced sequencing and analysis: the strongest demand signal found**
SYSUCC PIs post research-service bids through the hospital's research procurement marketplace. The vendor-onboarding form refers to "中肿锐竞平台" ([SKL 服务指引](http://skl.sysucc.org.cn/Service/ArticleList.aspx)). Bids are mirrored on aggregators as "中山大学附属肿瘤医院-J2026…, 竞价类型：科研服务":

| Posted | PI group | Request | Platform / spec | Analysis requirement | Source |
|---|---|---|---|---|---|
| 2026-05-22 | 杨云鹏组 | MRD 8-gene panel, 133 samples | DNBSEQ-T7 PE150 | Library + sequencing + **data analysis**; "提供能够支撑文章发表的所有信息分析服务，直至文章发表"; free bioinformatics training for the group; no subcontracting | [qianlima](https://www.qianlima.com/bid-599499780.html) |
| 2026-07-01 | (hidden) | Pancreatic cancer scRNA-seq + analysis, 58 samples | Budget ¥493k | "测序及分析" | [qianlima](https://www.qianlima.com/bid-610357540.html) |
| 2026-07-31 | 麦海强课题组 | NPC single-nucleus RNA-seq, 60 samples | GEM-X, brand requirement **联川 (LC-Bio)**, Illumina PE150 | Same "all analysis to publication" + training clause | [yfbzb](https://www.yfbzb.com/inviteBid/detail/20260731_618817712.html) |
| 2026-08-15 | 贾卫华课题组 (head of tumor biobank) | cfDNA WGS, **1,700 samples**, 30 G each | NovaSeq X; vendor needs ≥10 Illumina sequencers | Same publication-analysis + training clause | [yiliaozhaobiao](https://www.yiliaozhaobiao.com/news-04a7ec0bfb50cf36796e11ec81828f44/) |

- **Interpretation:** even PIs at a cancer center with its own sequencing platform buy production-scale sequencing (NovaSeq X, DNBSEQ-T7, GEM-X) from vendors. More importantly for BioMate, they **demand that the vendor deliver the analysis and train the lab**. That points to a shortfall in in-house analyst capacity relative to demand.
- **Named vendors seen:** **联川 LC-Bio** (explicit brand requirement, 2026-07). In SYSU Spatial work, Stereo-seq is a BGI technology (paper methods). Elsewhere at SYSU (not SYSUCC): LC-Bio won SYSU First Affiliated Hospital single-cell bids (¥1.10M in 2021; ¥4.48M in 2022), and **Novogene** won a ChIP-seq package (2022) ([sinochemitc](http://e.sinochemitc.com/cms/channel/ywgg2fw/121689.htm)). **BGI 深圳华大生命科学研究院** won a ¥4.75M spatial-transcriptomics bid at SYSU First Affiliated Hospital (2023) ([10huan](https://bid.10huan.com/2023/zhb/10-08/zhb221489.html)).
- **Not found:** SYSUCC-specific awards to BGI, Novogene, 吉因加, 燃石, 世和, 泛生子, 艾吉泰康, 基迪奥 Gene Denovo, or 欧易 OE Biotech. The marketplace bids hide the winners, so absence of evidence is weak here.
- Methods in a SYSUCC NPC TLS paper (Nat Commun 2024, [PMC11375053](https://pmc.ncbi.nlm.nih.gov/articles/PMC11375053/)) show a standard open-source stack: Cell Ranger, Seurat 4, Harmony, DoubletFinder, BayesSpace, Space Ranger, SAW, Monocle3, CellChat, GSVA. This is exactly the analysis class BioMate workflows cover.

### 2.5 Molecular diagnostics / clinical NGS (分子诊断科)

- **Legacy profile** ([科室简介/64](https://sysucc.org.cn/department/introduction/64); English page [index_25 lcid=130](https://english.sysucc.org.cn/index_25.aspx?lcid=130)):
  - Separated from Pathology in 2012
  - PCR-lab certified by MoH in 2006
  - Staff: 2 physicians and 6 technicians
  - Equipment: ABI 7500/7900HT, CEQ8000, SPR, Sequenom
  - 30 test items, more than 50,000 cases
  - **Likely stale** (see caveats)
- **Current NGS signals (procurement):**
  - 2022-04: reagents for **ABI 3500xL** and **Bio-Rad QX200 ddPCR** ([node/1275](https://sysucc.org.cn/node/1275))
  - **2023-04-28: mNGS pathogen NGS and MRD NGS reagents, which must include the full extraction→sequencing chain plus leased equipment and on-site support** ([node/6151](http://sysucc.org.cn/node/6151)). This shows clinical NGS runs on a **vendor reagent-rental model**, where the vendor typically supplies the pipeline as well.
  - 2025-07-10: "高通量检测试剂" market survey with leased instruments ([node/10346](http://sysucc.org.cn/node/10346))
  - 2026-05-22: 3-year maintenance for 1 genetic analyzer and 7 PCR machines, budget ¥1.28M ([node/12742](http://sysucc.org.cn/node/12742))
  - 2026-05-11: **molecular-diagnostics bioinformatics data-integration compute platform** (see 2.2)
- The NPC risk-prediction chip developed in the SKL is offered as an in-hospital clinical test in Molecular Diagnostics ([antpedia](https://m.antpedia.com/lab/2231.html)).
- **Assessment:** clinical NGS capacity exists and is growing, but it is vendor-kit-driven. The department appears to be building in-house capability to **integrate and analyze** molecular-diagnostics data across those vendor kits, which is a relevant but regulated opportunity.

### 2.6 Clinical research / cohorts

- Clinical Research Dept ([科室简介/70](https://www.sysucc.org.cn/department/introduction/70)): 2016–2020 saw 1,876 approved studies, including 470 registered trials and 1,406 IITs. There are **2 full-time statisticians**. The RDD data-deposit platform has been running since 2017 (2,442 deposits by 2021-04).
- Central randomization system went live 2021-11 ([node/4578](https://sysucc.org.cn/node/4578)). EDC build was surveyed 2025-06 ([node/10220](http://www.sysucc.org.cn/node/10220)). GAMP5 validation of trial data systems was surveyed 2026-06 ([市场调研公告](https://sysucc.org.cn/scdygg?page=0)).
- Cohorts: a 30-year, 100k-person NPC screening cohort, plus more than 1,000 registered trials in about 20 years ([SKL 实验室概况](https://skl.sysucc.org.cn/AboutUs/)).

---

## 3. Implications for BioMate

**Likely redundant (don't lead with these)**
- **Digital pathology and pathology AI.** SYSUCC has 5 WSI scanners, its own foundation models (CRISP, GAS), and the Bio-totem partnership. Offer interoperability at most.
- **Clinical big-data infrastructure and trial IT** (big-data platform, RDD, EDC, randomization, GAMP5). These are institution-built and vendor-built; BioMate's clinical-cohort analytics would compete with internal projects.
- **Raw instrument access.** Flow, imaging, and super-resolution are well funded and actively procured (2025–2026). BioMate isn't an instrument play anyway.
- **Basic NGS pipelines for the computational elite.** The Ren and Zuo groups write their own (MeRIPseqPipe on Nextflow). They are potential collaborators or benchmark partners, not customers.

**Complementary (where BioMate fits)**
1. **Analysis capacity for wet-lab PIs.** This is the strongest signal. 2026 tenders show PIs buying "analysis until publication + training" bundled with sequencing. BioMate can unbundle analysis from sequencing, so PIs can buy sequencing on price and still get publication-grade, reproducible single-cell, WGS/cfDNA, MRD-panel, and RNA-seq analysis.
2. **Workflow and AI layer on SYSUCC's new compute.** The 2026 Lenovo HPC (large-memory + GPU) and the molecular-diagnostics compute platform need software. A validated, auditable workflow catalog on top of hospital-owned compute could address data-residency concerns.
3. **Spatial and single-cell integration.** SYSUCC publishes Visium, Stereo-seq, and scRNA work but has no in-house spatial core. Cross-platform spatial analysis (Visium, Stereo-seq/SAW, Xenium, CosMx) is a natural fit.
4. **Proteomics and metabolomics analysis.** Acquisition is likely at the SYSU Analysis & Test Center (Orbitrap/timsTOF, new prep stations), and the center appears to offer acquisition rather than tailored downstream analysis. This is an inference and was not verified.
5. **Flow cytometry analysis.** Demand will grow with a new sorter (2025) and a new analyzer (2026); high-parameter gating and clustering are complementary. CyTOF was not found, so mass-cytometry workflows are only relevant if a PI uses external CyTOF.
6. **Organoid, drug-screen, and HTS data analysis plus drug design.** There is no central screening core. High-content imaging, med-chem synthesis, and PI-level organoid work could use dose-response, high-content image analytics, and BioMate drug-design workflows.
7. **Cryo-EM processing** for SYSUCC structural groups using the new SYSU Krios. Demand is unknown and probably small at a cancer center.
8. **Biostatistics for IITs.** Only 2 statisticians serve more than 1,400 IITs per 5 years; survival, clinical-cohort, and BOIN/dose-escalation workflows could help. This sits next to the regulated trial stack, so position it as research analysis.

---

## 4. Open questions to ask SYSUCC

1. **Bioinformatics service platform:** headcount, service menu, pricing, queue time? Does it serve only SKL PIs or all clinical departments?
2. Which software stack will run on the 2026 生信高性能服务平台 (Lenovo GPU and large-memory nodes)? Who operates it (IT center vs SKL)? Is it open to all PIs?
3. **Molecular-diagnostics data-integration platform (2026-05):** what data (vendor-kit outputs, mNGS, MRD, panels)? Is it clinical (regulated) or research? Is a software or pipeline vendor being selected?
4. Fraction of PI sequencing **outsourced vs in-house**, and annual spend? Main vendors (联川, 诺禾, 华大, 基迪奥)? Do PIs value analysis delivered separately from sequencing?
5. Current in-house sequencers: is HiSeq still the main instrument? NovaSeq, DNBSEQ, or long-read? What is in the 单分子测序平台 (PacBio vs ONT)?
6. Mass spec: which model is the "Bruker 蛋白质谱系统"? Do SYSUCC PIs send proteomics/metabolomics to the SYSU Analysis & Test Center, to vendors (e.g., 景杰, 欧易, 迈维), or to in-house SKL "多组学研究平台"? Who does the downstream analysis?
7. Spatial omics: any plans to buy Xenium, CosMx, Visium HD, or Stereo-seq in-house? Who runs current spatial projects (BGI vs 10x service providers)?
8. CyTOF or imaging mass cytometry: available anywhere in SYSU? Any SYSUCC usage?
9. Organoids and PDX: is a central organoid biobank or drug-screening platform planned? What is the relationship with 创芯国际? Is there any automated HTS?
10. Data governance: rules on sending patient omics data to external cloud vs on-prem deployment (人类遗传资源 / HGRAC constraints)? This determines whether BioMate must deploy on SYSUCC hardware.
11. Who are the budget holders: the SKL (徐瑞华 as SKL director; 实验研究部 leadership), the IT center (李超峰), or individual PIs via the 锐竞 research-service marketplace?

---

## 5. Source list (fetched or searched 2026-10-30)

- SYSUCC 实验研究部 intro: http://www.sysucc.org.cn/department/introduction/185 (updated 2026-06-18)
- SKL home (maintenance on 2026-10-30): https://skl.sysucc.org.cn/ ; 概况 https://skl.sysucc.org.cn/AboutUs/
- SKL sequencing platform (2024-04-29): https://skl.sysucc.org.cn/info/ArticleShow.aspx?AID=2924
- SKL microbiome platform (2024-04-29): http://skl.sysucc.org.cn/Info/ArticleShow.aspx?AID=2923
- SKL 服务指引: http://skl.sysucc.org.cn/Service/ArticleList.aspx
- SKL older profile: https://m.antpedia.com/lab/2231.html
- Postdoc recruitment (platform list): https://mp.weixin.qq.com/s/hzk5j0zWXeuRuSwfOmdWfA
- Super-res microscope survey 2026-01-18: http://www.sysucc.org.cn/node/11749 ; tender 2026-09-01: http://www.ccgp.gov.cn/cggg/zygg/gkzb/202609/t20260901_27243380.htm
- Flow analyzer tender extension 2026-10-22: http://www.ccgp.gov.cn/cggg/zygg/gzgg/202610/t20261022_27546338.htm
- Flow sorter tender 2025-09-29: https://www.yiqi.com/news/detail_10024426.html
- Flow analyzer survey 2025-11: https://www.qianlima.com/bid-551314072.html
- X-ray irradiator award 2026-07-20: http://www.ccgp.gov.cn/cggg/zygg/zbgg/202607/t20260720_26970622.htm
- Lab equipment award 2024: https://bidding.sysu.edu.cn/node/16839
- Bioinformatics HPC award 2026-09-28: https://www.dingbiao.com/zhaobiao/c4e201f861d14fb9e19e5f8da4f9e83c.html
- Mol-dx compute platform survey 2026-05-11: https://www.qianlima.com/bid-595994414.html
- PI research-service bids 2026: https://www.qianlima.com/bid-599499780.html ; https://www.qianlima.com/bid-610357540.html ; https://www.yfbzb.com/inviteBid/detail/20260731_618817712.html ; https://www.yiliaozhaobiao.com/news-04a7ec0bfb50cf36796e11ec81828f44/
- Molecular Diagnostics: https://sysucc.org.cn/department/introduction/64 ; http://sysucc.org.cn/node/6151 ; https://sysucc.org.cn/node/1275 ; http://sysucc.org.cn/node/10346 ; http://sysucc.org.cn/node/12742
- Information Center: https://sysucc.org.cn/department/introduction/88
- Clinical Research Dept: https://www.sysucc.org.cn/department/introduction/70 ; EDC http://www.sysucc.org.cn/node/10220
- Pathology: https://sysucc.org.cn/department/introduction/60 ; digital pathology https://www.cn-healthcare.com/articlewm/20231129/wap-content-1620924.html
- Pathology AI: https://doi.org/10.48550/arxiv.2510.04861 ; https://doi.org/10.1038/s41746-025-01808-7
- Ren Jian: https://lifesciences.sysu.edu.cn/zh-hans/teacher/1203 ; https://renlab.org/people.html
- Zuo Zhixiang: http://www.sysucc.org.cn/node/7646
- Bei Jinxin: https://iashk.sysu.edu.cn/zh-cn/teacher/115
- NPC TLS single-cell/spatial paper: https://pmc.ncbi.nlm.nih.gov/articles/PMC11375053/
- Organoid licensing 2023-12-20: https://www.sysucc.org.cn/node/7420
- SYSU cryo-EM: https://iarc.sysu.edu.cn/article/936 ; https://www.sysu.edu.cn/news/info/2161/1395281.htm
- SYSU MS unit: https://iarc.sysu.edu.cn/taxonomy/term/117 ; Shenzhen Orbitrap: https://iarc.sysu.edu.cn/article/966 ; prep stations 2026-10-12: https://www.dingbiao.com/zhaobiao/37edb7d8cc6f73522f08d381c94189ae.html
- SYSU sharing platform launch 2025-01-02: https://zssom.sysu.edu.cn/article/11070
- SYSU biobank: https://www.sysu.edu.cn/news/info/2161/513171.htm
- SYSU FAH vendor awards (context): http://e.sinochemitc.com/cms/channel/ywgg2fw/121689.htm ; https://bid.10huan.com/2023/zhb/10-08/zhb221489.html
