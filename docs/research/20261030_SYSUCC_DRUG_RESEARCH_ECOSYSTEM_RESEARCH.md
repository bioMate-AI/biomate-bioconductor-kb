# SYSUCC (中山大学肿瘤防治中心) — Drug-Research & Research-Computing Ecosystem

**Prepared:** 2026-10-30 · **Method:** web search (Chinese + English), official SYSUCC / SYSU pages, HKEX/SSE disclosures, procurement notices, vendor pages, PubMed/PMC.
**Purpose:** decide how to position BioMate's on-prem AI research platform honestly at SYSUCC — where it already has mature alternatives, and where it doesn't.

**Confidence legend:** ✅ confirmed by a primary or official source · 🟡 secondary source or vendor marketing only · ❌ searched, nothing found (absence of public evidence, not proof of absence).

---

## 1. Summary

- **SYSUCC is a top-tier clinical drug-*development* site, not a drug-*discovery* house.** It runs China's first hospital-run oncology Phase I ward (since 2014): 160+ active studies, 80%+ Class 1.1 innovative drugs, and 10 drugs it helped bring to approval by end-2023. In the 2025 national GCP-volume ranking it is #4 (A+++++). It leads pivotal trials for Junshi (toripalimab, JUPITER-02), BeiGene (tislelizumab, RATIONALE-309), Hengrui (camrelizumab; SHR-A1904), Innovent (sintilimab, ORIENT-11) and Akeso (ivonescimab, HARMONi-A and global HARMONi). ✅
- **Some in-house discovery capacity exists, but it is small and lab-scale.** There is a "药物化学合成平台" (medicinal chemistry synthesis platform), a "抗体蛋白平台" (antibody/protein platform), and a few medicinal-chemistry/pharmacology PIs: 文石军 (Wen Shijun, small-molecule inhibitors/degraders), 黄蓬 (Huang Peng), 朱孝峰 (Zhu Xiaofeng), and 杨大俊 (Yang Dajun, a SYSUCC professor who is also chairman/CEO of 亚盛医药 Ascentage Pharma). I found **no in-house computational chemistry, AI molecular design, or ADMET/PK modeling group at SYSUCC.** ✅/❌
- **Tech transfer is real and active, but biased toward biologics, vaccines and diagnostics.** Examples: Junshi RX-af01 live-bacteria ICI enhancer (2022; up to ¥500M milestones + 5% royalty, the center's largest deal), Zhifei EBV vaccine (2023; ¥100M+), 创芯国际 (Chuangxin International) organoid patents (2023; ¥1M), and a 2026 spin-off by 贝锦新 (Bei Jinxin), 广州曙莱健康科技 (Guangzhou Shulai Health Technology). There were also several small patent sales in 2025–26. **None involve AI drug design.** ✅
- **SYSUCC's AI is mature on the clinical side and almost absent on the drug-discovery side.**
  - **Mature clinical AI:** a Yidu-built (医渡科技) T+0 oncology big-data platform covering 2M+ patients, 43 disease registries and 3,600 supported research projects; a private DeepSeek-R1 671B clinical assistant (March 2025); a Huawei multimodal "AI data lake" (about 10 PB/yr); NPC radiotherapy auto-contouring (deployed in 361 hospitals); a brain-metastasis MRI detector (500+ hospitals); NPC endoscopy and MRI deep-learning models; GRAIDS GI-endoscopy AI; and pathology AI with Bio-totem (生物图腾). ✅
  - **Drug-discovery AI partners:** I found **no public partnership between SYSUCC and XtalPi, Insilico, DP Technology, BioMap, Huawei Pangu-Drug, Tencent iDrug, Alibaba Cloud or BAAI.** ❌
- **Bioinformatics is partly in-house.** There is a 生物信息/超算平台 (bioinformatics and supercomputing platform). PIs include 任间 (Ren Jian), 赵齐 (Zhao Qi), 刘泽先 (Liu Zexian; qPTM, DrugCVar, pSAM, etc.), 贝锦新, 左志向 (Zuo Zhixiang) and 岳家兴 (Yue Jiaxing). The compute is modest:
  - 2020: a ¥2.96M HPC cluster of 20 Lenovo SD530 nodes.
  - 2026-09: a ¥1.40M award for 2 large-memory nodes, **1 GPU node** and 1 storage node.
  - 2026-05: a separate molecular-diagnostics data-analysis server project. ✅
- **Omics data generation is heavily outsourced.** Confirmed in methods sections or announcements:
  - **BGI / 华大**: NPC single-cell atlases in *Cell Research* 2020 and *Nature Medicine* 2023, plus germline panels.
  - **Nanjing Geneseeq / 世和**.
  - **3D Medicines / 思路迪**.
  - Gene Denovo / 基迪奥 lists SYSUCC as a client 🟡.
  - No SYSUCC-specific public evidence was found for Novogene, OE Biotech, LC-Bio, BMK, Metware, PTM Bio or APTBIO. They are almost certainly used by individual labs, but I couldn't prove it. ❌
- **Organoids:** 创芯国际 holds licensed SYSUCC neuro-oncology organoid IP (✅). A SYSUCC co-author appears on a rectal-cancer organoid paper from 丹望医疗 (D1Med) (🟡). No SYSUCC link was found for 大橡科技 (Daxiang Biotech) (❌).
- **Positioning implication:** do **not** pitch BioMate at SYSUCC as a clinical-AI or LLM-assistant platform; Yidu and Huawei own that ground. The credible openings are:
  - (a) reproducible, on-prem omics and translational-biomarker workflows on top of their thin in-house HPC (with 1 GPU node);
  - (b) a computational chemistry / ADMET / design layer for the small med-chem and antibody platforms, which have no visible computational counterpart;
  - (c) versioned assay-data models that link Phase I PK/biomarker data back to preclinical work.

---

## 2. Detailed findings

### 2.1 Drug-research activities

#### Phase I unit & clinical-trial infrastructure ✅
| Fact | Date | Source |
|---|---|---|
| 1983 MoH "临床药理基地" (clinical pharmacology base); 2001 China's first "国家新药(抗肿瘤药物)临床试验研究中心" (national clinical trial center for anticancer drugs); 2016–2020 totals: 1,876 clinical research projects, 434 new-drug trials (182 Class I, 136 Phase I), 1,406 investigator-initiated studies (IIS), and 116 trials where SYSUCC was lead site (16 of them international) | Dept page (data to 2021) | https://www.sysucc.org.cn/department/introduction/70 |
| Phase I ward opened Mar 2014 (12 beds), now 33 beds, ~4,000 admissions/yr, >160 active studies, >80% Class 1.1, 10 drugs approved in CN/US by end-2023; "十四五" (14th Five-Year Plan) first-in-class share ranked #1 among Chinese cancer hospitals | 2025-03-14 | https://news.qq.com/rain/a/20250314A01N2T00 |
| 2025 CCHRP national GCP trial-volume ranking: SYSUCC #4, A+++++ | 2025 | https://zy.runtrial.net/public/share/download.do?ftid=1441 |
| Recent first-in-human/Phase I work: YL201 (B7-H3 ADC, MediLink 映恩), SHR-A1904 (CLDN18.2 ADC, Hengrui), CMG901, MRG003 (EGFR-ADC), JS107 (CLDN18.2 ADC, Junshi), BL-B01D1 (EGFR×HER3 bispecific ADC, Biokin 百利天恒; *Lancet Oncol* 2024) | 2024–2025 | https://english.sysucc.org.cn/info_62.aspx?itemid=991 · https://news.qq.com/rain/a/20250429A08ZI400 · https://www.scholat.com/orgPost.html?id=1183 |
| Registry snapshot: many 2025–26 Phase I/Ib trials (JSKN022, BL-M24D1, GFH276, HBW-012336 KRAS-G12D, RO7673396, etc.) | 2026 | https://www.changbaicao.cn/hospitaldetail-id-280.html |
| The center also runs Phase I PK studies, therapeutic drug monitoring (TDM), data management, a statistics service, and the RDD research-data deposit platform | — | https://english.sysucc.org.cn/index_28.aspx |

#### Pharma pivotal-trial relationships ✅
| Company | Drug / trial | SYSUCC lead | Source |
|---|---|---|---|
| 君实 Junshi | Toripalimab, JUPITER-02 (NPC 1L; FDA approval 2023-10) | 徐瑞华 (Xu Ruihua) | https://www.junshipharma.com/君实生物宣布特瑞普利单抗获得美国fda批准上市/ |
| 君实 Junshi | 2022-08 strategic agreement plus RX-af01 licence | 徐瑞华 | https://www.junshipharma.com/君实生物与中山大学肿瘤防治中心签署战略合作协/ |
| 百济神州 BeiGene | Tislelizumab, RATIONALE-309 (3-yr data in *JAMA Oncol* 2026-02; included a TME gene-expression biomarker analysis) | 张力 (Zhang Li), 方文峰 (Fang Wenfeng) | https://www.medsci.cn/article/show_article.do?id=2c8893045ead |
| 恒瑞 Hengrui | Camrelizumab NPC (*Lancet Oncol*); SHR-A1904 Phase I | 张力; 徐瑞华 | https://www.sysu.edu.cn/info/2121/13822.htm |
| 信达 Innovent | Sintilimab, ORIENT-11 (approved 2021-02) | 张力 | https://news.bioon.com/article/a7ea660e561d.html |
| 康方 Akeso | Ivonescimab, HARMONi-A (*JAMA* 2024; final OS in *JAMA* 2026-06) and global HARMONi (*Lancet Oncol* 2026-08) | 张力, 方文峰 | https://www.sysucc.org.cn/node/8258 · https://www.zhongliujie.com/index.php/news/show/id/1855.shtml |

Note: these are sponsor-funded clinical relationships. None of the sources show SYSUCC doing discovery chemistry for these companies.

#### In-house discovery / "新药创制" (new drug creation) ✅ (scale: small)
- **Research platforms** include a 药物化学合成技术服务平台 (medicinal chemistry synthesis service), a 蛋白抗体技术服务平台 (protein/antibody service), a 生物信息服务平台 (bioinformatics service), a high-throughput sequencing and genotyping platform, a single-molecule sequencing platform, a tumor-microbiome platform, and a biobank. Lab space is 33,721 m². — https://www.sysucc.org.cn/department/introduction/185 ; https://mp.weixin.qq.com/s/hzk5j0zWXeuRuSwfOmdWfA
- **State Key Lab of Oncology in South China** (reorganized as 华南恶性肿瘤防治全国重点实验室, 107 PIs) and the **MOE Key Lab of Cancer-related Genes and Anticancer Drugs** (2003). — http://www.sysucc.org.cn/kypt
- **Medicinal chemistry:** 文石军 works on IDH2/EZH2/BRD4/LSD1 inhibitors and degraders; one HDAC inhibitor has reached preclinical; ~20 patent filings. — http://www.sysucc.org.cn/node/4765
- **Drug-oriented PIs** from the 2024 postdoc call: 黄蓬 (drug treatment/resistance), 符立梧 (Fu Liwu, anticancer pharmacology, MDR), 朱孝峰 ("肿瘤创新药物研究", innovative cancer drug research), 杨大俊 (drug R&D/mechanism), 刘强 (Liu Qiang; prefers small-molecule design experience), 刘然义 (Liu Ranyi; antibody experience), 曾木圣 (Zeng Musheng; vaccines/antibodies). — https://yjs.cd120.com/upload/files/2024/3/773da74af108e342.pdf
- **杨大俊** is a SYSUCC professor and doctoral supervisor, and co-founder/chairman/CEO of **亚盛医药 Ascentage Pharma**, which marketed olverembatinib and lisaftoclax and struck a >¥9B deal with Takeda in 2024. This is the most important "industry-grade drug discovery" person tied to SYSUCC, but the discovery engine sits at Ascentage, not SYSUCC. — https://www.ascentage.cn/company/leadership-team/
- **Hospital leadership statements** mention leading in "创新药物研发" (innovative drug R&D) and building the Huangpu campus phase II as a "医研产一体化" (integrated clinical–research–industry) biomedical innovation and translation platform: ¥500M of district funding, signed 2022-10. — https://www.chinanews.com.cn/cj/2022/10-11/9870906.shtml ; https://difang.gmw.cn/gd/2024-02/19/content_37153252.htm

#### Technology transfer, patents, spin-offs ✅
| Deal | Date | Value | Source |
|---|---|---|---|
| Junshi exclusive global licence: RX-af01 live-bacteria ICI enhancer (3 patent applications incl. PCT; inventors in 徐瑞华's team) | 2022-06/08 | ≤¥500M milestones + 5% net sales; the center's largest deal | http://www.cnpharm.com/upload/resources/file/2022/06/09/118368.pdf · https://www.sysu.edu.cn/news/info/2161/713331.htm |
| Zhifei/智飞龙科马: EBV gHgL nanoparticle vaccine patents (曾木圣) | 2023-07/10 | ¥100M + royalties | https://research.sysu.edu.cn/article/334 · https://www.sysu.edu.cn/news/info/1881/1070201.htm |
| 创芯国际: pituitary-tumor and GBM organoid patents (牟永告, Mou Yonggao) | 2023-12 | ¥1M | https://www.sysucc.org.cn/node/7420 |
| HCC ctDNA methylation diagnostic kit (徐瑞华, 骆卉妍 Luo Huiyan, 张康 Zhang Kang/UCSD; *Nat Mater* 2017); reported as an NMPA Class III device | 2017 / 2024 statement | partner company name not found ❌ | https://www.sysu.edu.cn/news/info/2171/540231.htm · https://difang.gmw.cn/gd/2024-02/19/content_37153252.htm |
| BMP9 + NK + PD-L1 HCC patent → 深圳欧安蒂 (Shenzhen Ouandi) | 2026-01 | ¥0.5M | https://research.sysu.edu.cn/article/3607 |
| NPC immunotherapy response prediction model (TLS/spatial cell-density score) → 深圳巨东 (Shenzhen Judong) | 2026-03 | ¥0.9M | https://bydrug.pharmcube.com/news/detail/fb90103b54451d3ffe728e992e106b60 |
| Six patents (systemic infection detection, etc.; 贝锦新) contributed as equity in spin-off **广州曙莱健康科技** | 2026-04 | valued ¥5.37M | https://research.sysu.edu.cn/article/3802 |
| EMR generation and "dynamic-knowledge-constrained tumor staging" patents (co-owned with Yidu) → Yidu | 2026-07 | ¥50k + royalty | https://sysucc.org.cn/node/13461 |

SYSUCC has its own tech-transfer rules (肿瘤防治〔2024〕22号) and a 科研科 (research office) that runs public transfer notices.

### 2.2 AI-for-drug-discovery and computational partnerships

| Candidate | Finding | Status |
|---|---|---|
| 晶泰 XtalPi | No SYSUCC partnership found; XtalPi oncology deals are with pharma (CTTQ 正大天晴, 3D Medicines, CSPC) | ❌ |
| 英矽智能 Insilico | None with SYSUCC; Insilico–Tencent Health deal 2026-07 (general) | ❌ |
| 深势科技 DP Technology | None with SYSUCC | ❌ |
| 百图生科 BioMap | None with SYSUCC | ❌ |
| 华为云 盘古药物分子大模型 (Pangu drug-molecule model) | Pangu-Drug partners are SIMM, Xi'an Jiaotong 1st Hospital, Chipscreen (微芯) and others. **Huawei's SYSUCC work is infrastructure:** a multimodal "一院多区融合医疗AI数据湖" (multi-campus medical AI data lake; ~10 PB/yr; pathology–genomics–imaging joint modeling; federated learning planned), named a 2025 China Computing Power Conference "创新先锋" (innovation pioneer) case | ❌ for drug design; ✅ for infra (https://www.odcc.org.cn/news/p-1978991561917935617.html, 2025-10-17) |
| 腾讯 Tencent iDrug / AI Lab | No SYSUCC drug link. Tencent AI Lab worked with **SYSU 6th Affiliated Hospital**, a different hospital | ❌ |
| 阿里云 Alibaba Cloud / 智源 BAAI | Nothing found | ❌ |
| 医渡科技 Yidu Tech | **Deep, long-running (since 2015):** T+0 oncology big-data platform, private AI middle platform, DeepSeek-R1 671B assistant, 100+ physician-built agents, co-owned patents | ✅ (https://www.yidutech.com/news-detail.html?id=296, 2025-07-09; https://bydrug.pharmcube.com/news/detail/7a6d0b0ae49654baae1f344e16b71e3f, 2025-05-20) |
| 生物图腾 Bio-totem | Pathology AI co-development: TNBC TIL scoring (*EBioMedicine* 2021); IHC/frozen-section image enhancement (2024) | ✅ (https://sysucc.org.cn/node/4253; https://www.bio-totem.com/list/post/3096704/) |
| 广州实验室 Guangzhou Laboratory | Only a joint PhD program with SYSU (SYSUCC is a host school; ~30 PhDs in 2026). No joint drug project found | ✅ training only |
| 生物岛实验室 Bioland | Co-built a cancer platform with **SYSU Sun Yat-sen Memorial Hospital** (宋尔卫 Song Erwei), not SYSUCC | ❌ for SYSUCC |
| SYSU School of Pharmaceutical Sciences (药学院) | Real computational drug-design groups, all ❌ for any SYSUCC collaboration: 徐峻 (Xu Jun; Drug Molecular Design Research Center, AI/cheminformatics), 罗海彬 (Luo Haibin) / 李哲 (Li Zhe; GA-FEP free-energy method, PNAS 2020), 雷金平 (Lei Jinping; generative and pocket-aware AI design, national key R&D project on AI target discovery and molecule generation 2023–26), 史滔达 (Shi Taoda; synthesizable ultra-large virtual libraries) | ✅ groups exist; ❌ SYSUCC link |
| 广东华南新药创制中心 (Guangdong South China New Drug Creation Center) | Government-guided public platform in Guangzhou Science City: GLP / large-animal tox, biologics bioanalysis (PK/PD/ADA), formulation pilot, registration. Still operating in 2025. No SYSUCC-specific tie found | ✅ exists; ❌ SYSUCC link |

**Interpretation:** inside SYSU, computational chemistry and AI drug design live in the School of Pharmaceutical Sciences, not at SYSUCC. That school (or Ascentage) is the natural partner a SYSUCC chemist would go to today. I found no evidence of a formal pipeline between them.

### 2.3 AI / bioinformatics tools from SYSUCC researchers ✅

**Clinical/imaging AI (mature, deployed):**
- **NPC radiotherapy target/OAR auto-contouring** (69 organs): 3D multi-scale CNN; contouring time 3 h → 0.5 h; 73k internal uses; 361 hospitals in 30 provinces. — https://www.sysu.edu.cn/news/info/2561/1387471.htm (2025-05-06)
- **Brain-metastasis MRI detection software** (谢传淼, Xie Chuanmiao): used in 500+ hospitals. — https://www.sysu.edu.cn/news/info/2171/1390811.htm (2025-07-14)
- **DeepSeek-based oncology assistant** (李超峰 Li Chaofeng, information center director; 孙颖 Sun Ying, vice-president): live since 2025-03, 60k uses. A colorectal-cancer decision LLM is in development, using 70k cases. They openly report 10–20% hallucination rates. — same source.
- **eNPM-DM** NPC endoscopy model (*Cancer Commun* 2018), **MRI deep-learning NPC prognosis models**, and **GRAIDS** upper-GI endoscopy AI (*Lancet Oncol* 2019, 徐瑞华). — https://pubmed.ncbi.nlm.nih.gov/30253801/ ; https://pmc.ncbi.nlm.nih.gov/articles/PMC8096375/ ; https://english.sysucc.org.cn/info_62.aspx?itemid=807
- **Pathology AI** with Bio-totem (孙鹏 Sun Peng, 何洁华 He Jiehua). The pathology chief, 云径平 (Yun Jingping), is publicly cautious about pathology foundation models. — https://www.nbd.com.cn/articles/2025-02-20/3758989.html

**Omics / bioinformatics (research-grade, published tools):**
- **刘泽先 lab**: qPTM (NAR 2023), eKPI (Brief Bioinform 2025), DrugCVar (Bioinformatics 2022), pSAM (Nat Commun 2025), dSCOPE, BodyMeta, iMPI, plus DeepGSH / Deep-PLA / DeepCalpain. Strong PTM/proteomics and variant–drug informatics. — http://lzx.cancerbio.info/database.php
- **Bioinformatics platform (任间 / 赵齐)**: VSOLassoBag biomarker selection (JGG 2023). — http://tbm.cacakp.com/website/article/detail.do?id=486
- **DeepMSProfiler** (*Nat Commun* 2024): end-to-end deep learning on raw LC-MS metabolomics (黄蓬 / 胡寓旻 Hu Yumin with SYSU 李伟忠 Li Weizhong). — https://www.sysu.edu.cn/news/info/2331/1285171.htm
- **徐瑞华 team**: GI-cancer big-data platform and the qPhos database. — https://www.sysu.edu.cn/info/2121/13612.htm
- **Other computational PIs**: 贝锦新, 左志向 (bioinformatics/epigenetics), 岳家兴 (evolutionary genomics), 林东昕 (Lin Dongxin; cancer genomics), 贾卫华 (Jia Weihua; genetics/early screening).

**In-house compute (procurement) ✅:**
- 2020-06: HPC cluster, ¥2.96M, 20× Lenovo SD530. — https://bid.10huan.com/2020/zhb/202006/20/zhb2661794.html
- 2026-09-28: "生信高性能服务平台" (bioinformatics high-performance service platform), budget ¥2.1M, awarded ¥1.3965M: 2× large-memory nodes, **1× GPU node (Lenovo WA5680 G3)**, 1× storage node. — https://www.dingbiao.com/zhaobiao/c4e201f861d14fb9e19e5f8da4f9e83c.html
- 2026-05: molecular-diagnostics data-integration compute platform (market survey). 2026-10: "molecular diagnostics report system intelligent upgrade" project, ¥190k, including a report-recognition model. — https://www.qianlima.com/bid-595994414.html ; http://www.sysucc.org.cn/cggg

### 2.4 Organoids / drug-sensitivity testing / CRO
| Company | Relationship | Status |
|---|---|---|
| 创芯国际 (Guangzhou) | Bought SYSUCC neuro-oncology organoid patents (¥1M, 2023-12) and receives SYSUCC technical support | ✅ |
| 丹望医疗 D1Med | Rectal-cancer organoid chemoradiation paper (*Cell Rep Med* 2025-10); vendor says a SYSUCC author (姚晔, Yao Ye) is a co-author | 🟡 |
| 大橡科技 Daxiang | No SYSUCC link found | ❌ |
| CROs (WuXi, Pharmaron, etc.) | No SYSUCC-specific contracts found. Discovery-stage CRO use by individual labs is likely but not public | ❌ |
| Clinical CRO/SMO | Heavy CRC/SMO use for sponsor trials (the center manages external CRCs) | ✅ (dept page) |

### 2.5 Third-party omics / bioinformatics providers
| Provider | Evidence for SYSUCC use | Status |
|---|---|---|
| 华大 BGI | Co-authored NPC single-cell atlases: *Cell Research* 2020 and *Nature Medicine* 2023 (马骏 Ma Jun, 孙颖, 柳娜 Liu Na); germline CRC panel sequencing by BGI | ✅ https://www.genomics.cn/news/info_itemid_6770.html · https://www.dovepress.com/article/download/45412 |
| 世和 Geneseeq (Nanjing) | Lymphoma cfDNA NGS (*Haematologica*) | ✅ https://haematologica.org/article/view/haematol.2021.279908 |
| 思路迪 3D Medicines | Co-affiliated author on the CRC germline study | ✅ (same Dovepress paper) |
| 基迪奥 Gene Denovo (Guangzhou) | Lists "中山大学附属肿瘤医院" as a partner hospital | 🟡 https://www.genedenovo.com/partner/index.html |
| 景杰 PTM Bio | No SYSUCC-specific record. PTM Bio wins other SYSU proteomics tenders (School of Life Sciences, 2026-10) | ❌ for SYSUCC |
| 中科新生命 APTBIO | Not verified for SYSUCC | ❌ |
| 诺禾 Novogene, 欧易 OE Biotech, 联川 LC-Bio, 百迈客 BMK, 迈维 Metware | Used by sister SYSU hospitals (e.g., SYSU 1st Affiliated Hospital tenders went to LC-Bio and Novogene). No SYSUCC-specific public record found | ❌ |
| Procurement visibility | SYSUCC's procurement page shows equipment and IT tenders, but **no sequencing-service tenders**. Omics services are probably bought per-lab from grant funds, below public-tender thresholds | inference |

---

## 3. Competitive / complementary assessment for BioMate

### Where SYSUCC already has mature alternatives (do not compete head-on)
1. **Clinical data platform and LLM assistant:** Yidu (since 2015) plus DeepSeek-R1 on-prem, 100+ physician-built agents, and co-owned patents. Pitching a "medical LLM assistant" would collide with an embedded incumbent.
2. **Multimodal data infrastructure:** the Huawei AI data lake (storage, cross-campus access, pathology–genomics–imaging alignment, federated learning roadmap).
3. **Imaging/pathology clinical AI:** in-house models with national deployment, plus Bio-totem for pathology.
4. **Clinical trial operations:** the GCP office, Phase I ward, statistics team and RDD data deposit are best-in-class nationally. BioMate adds nothing to trial *conduct*.
5. **Omics data generation:** BGI, Geneseeq, Gene Denovo and others already deliver data plus "standard analysis" reports.

### Where real gaps appear (BioMate is complementary)
1. **Computational chemistry / AI design / ADMET for the med-chem and antibody platforms.** There is no visible computational counterpart at SYSUCC. The SYSU pharmacy groups (徐峻, 罗海彬, 雷金平) are a separate school and are themselves potential collaborators or competitors for this role.
2. **Reproducible, validated omics workflows on-prem.** Vendor analyses are one-off and not rerunnable. The in-house HPC is small (≈20 CPU nodes from 2020, plus 1 GPU node in 2026), and data-export and human-genetic-resource constraints favor on-prem. Versioned workflows over vendor FASTQ/mzML (scRNA-seq, proteomics/PTM, metabolomics, spatial) would directly complement BGI/Geneseeq and PTM-type vendors.
3. **Translational loop from Phase I back to preclinical.** SYSUCC runs 160+ early trials with PK/ADA and biomarker sampling (for example, the RATIONALE-309 gene-expression biomarker analysis). A versioned "assay → model" layer linking trial PK and biomarker data to mechanism and target hypotheses is not visible in any current partner's scope.
4. **Target ID from their cohorts.** Huge, well-annotated cohorts (NPC, GI, lung) feed papers and biomarker patents, but these rarely go on to druggability and design. The NPC TLS model and RX-af01 show they do monetize biomarker IP.
5. **Organoid/assay data modeling.** 创芯国际 holds organoid IP, but there is no visible platform for learning from organoid dose-response data with versioned models.

### Honest caveats
- SYSUCC's identity is clinical. Discovery chemistry is a handful of labs, so the buyer pool for design/ADMET modules may be small. Ascentage (杨大俊) and SYSU's School of Pharmaceutical Sciences may be the stronger design-side users.
- Yidu and Huawei could extend into research workflows; Huawei's EIHealth and Pangu-Drug is a plausible future competitor on the same data lake.
- Lack of public evidence ≠ lack of activity. Per-lab vendor and CRO use, and any NDA-covered AI-pharma pilots, would not be visible.

---

## 4. Questions for the meeting

1. Who owns research computing: the 信息中心 (information center; 李超峰), the 生物信息平台 (bioinformatics platform; 任间 / 赵齐), or the national key lab? What is the GPU capacity after the 2026 procurement, and is there access to Guangzhou supercomputing (广州超算) or Huawei Ascend compute?
2. How do labs analyze vendor omics data today: in-house platform staff, vendor reports, or students' own scripts? How many projects per year, and which modalities (scRNA, spatial, proteomics/PTM, metabolomics)?
3. Can research workflows run inside the Huawei data lake or the Yidu platform, or is a separate research enclave needed? What are the human-genetic-resource and data-export constraints?
4. Do the 药物化学合成平台 and 抗体蛋白平台 have any computational chemistry, docking, FEP or ADMET tools today? Do they collaborate with the SYSU pharmacy groups (徐峻, 罗海彬, 雷金平) or with Ascentage?
5. Is there appetite to turn Phase I PK/ADA/biomarker data into reusable models, and who is the sponsor (临床研究部 clinical research dept, 李苏 Li Su / 赵洪云 Zhao Hongyun)?
6. Has SYSUCC piloted any AI-drug-discovery vendor (XtalPi, Insilico, DP Tech, Huawei Pangu, Tencent iDrug)? If yes, what didn't work?
7. How does the 科研科 (research office) handle IP when a platform helps generate a target, molecule or model? Licence-only, or co-ownership like the Yidu patents?
8. Are organoid drug-screening data (创芯国际 or in-house) being generated at a scale that would justify learned models?
9. Huangpu campus phase II is a "医研产一体化" translation platform. Is there a budget line for discovery and translational informatics there?
10. Procurement path: departmental grant purchase (below tender threshold) vs. a center-level public tender? Required deployment form (on-prem, domestic chips, 信创 domestic-IT compliance)?

---

## 5. Not found / open items
- No public SYSUCC partnership with XtalPi, Insilico, DP Technology, BioMap, Huawei Pangu-Drug, Tencent iDrug, Alibaba Cloud, BAAI, Bioland or 大橡科技.
- Commercial partner for the HCC methylation kit not confirmed.
- No SYSUCC-specific evidence for Novogene, OE, LC-Bio, BMK, Metware, PTM Bio or APTBIO. Next step: mine methods/acknowledgment sections of 2024–26 SYSUCC papers (e.g., PubMed affiliation search + full text) to quantify vendor share.
- No public data on SYSUCC's total GPU count or research-cloud usage beyond the two procurement records above.
