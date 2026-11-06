# SYSUCC Information Center — IT / AI Platform, Vendors & Priorities (BD pre-meeting research)

**Subject:** Information Center (信息中心) of Sun Yat-sen University Cancer Center (中山大学肿瘤防治中心 / 中山大学附属肿瘤医院, SYSUCC, Guangzhou)
**Compiled:** 2026-10-30, from public web sources only (Chinese + English). No paid bidding-database access, so some winning bidders / amounts on aggregator sites were masked.
**Confidence legend:** **[Confirmed]** = primary source (SYSUCC site, official procurement notice, vendor HKEX-linked press release, or named quote). **[Reported]** = secondary media / vendor marketing. **[Inferred]** = my reasoning, not stated anywhere. **[Not found]** = searched, no public evidence.

---

## 1. Summary

- **Director: 李超峰 (Li Chaofeng)** — Director of the Information Center, senior engineer (高级工程师). He has a research background: published in *Lancet Oncology*, *JNCI*, *Clin Cancer Res*; PI on NSFC grants; works on deep learning for nasopharyngeal carcinoma (NPC). He also holds a joint professorship at the SYSU School of Software and chairs the Medical Informatics branch of the Guangdong Medical Equipment Society. He is the public face of SYSUCC's LLM program. Deputy directors are 任忠敏 and 何仲廉. The last official department profile (updated 2020) listed 22 staff in four groups, one of which is a 2-person AI Lab. **[Confirmed]**
- **The AI platform is Yidu Tech (医渡科技) end-to-end.** On 2025-02-27 Yidu privately deployed its AI middle platform (AI中台) with **DeepSeek-R1 671B (full model) plus Yidu's own YiduCore**. It sits on the oncology big-data platform Yidu has built with SYSUCC since 2015 (2M+ patients, T+0 real-time updates, 43 disease-specific databases). The June 2025 market survey "基于大模型的智慧医院建设项目 (incl. AI中台底座建设)" was followed by a public tender: **Yidu Cloud (医渡云(北京)) won the "智慧临床及结算服务升级建设项目" for ¥9.08M (result 2026-02-03; announced by Yidu on HKEX 2026-05-11)**. That project covers a unified model library, SFT of small task-specific models, and agent APIs for all business systems. **[Confirmed]**
- **Other AI and infrastructure vendors:**
  - Huawei: multi-campus "融合医疗AI数据湖" on all-flash distributed storage; about 10 PB of new data per year; pathology–genomics–imaging alignment. Named an innovation case in Oct 2025.
  - Tencent Health: precise bed and appointment booking on the internet hospital.
  - DingTalk: 30+ business systems integrated.
  - Neusoft: integration-platform CDR (2018).
  - Smaller AI items, each capped at ¥190k and bought by in-hospital negotiation: AI medical-record coding (Jan 2025); AI agent desktop workbench, won by 广州米听, ¥180,576 (Sept 2026); AI management platform plus LLM service, won by 广州讯中, ¥182k (Sept 2026). **[Confirmed]**
- **Research computing exists and is still growing, and this is BioMate's opening.**
  - A 2020 HPC cluster (¥2.96M, 20× Lenovo SD530) for the research side.
  - A **"生信高性能服务平台 (2026)" tender, ¥2.1M budget, won for ¥1.3965M on 2026-09-28**: Lenovo large-memory nodes, a GPU node and a storage node, all hardware only.
  - Two open server market surveys from the Information Center: a **GPU server procurement for an "AI计算平台"** (Apr 2026) and a **"分子诊断数据整合分析计算平台"** (molecular-diagnostics bioinformatics integration compute platform, May 2026). No award has been found for either.
  - There is a bioinformatics centre in 徐瑞华's (Xu Ruihua's) group (1 PB storage, clusters) and a "生物信息学和超级计算平台" listed among the State Key Lab's public platforms.
  - **No public evidence of a workflow / bioinformatics *software* layer** (pipelines, ADMET, PK) on top of this hardware. **[Confirmed for hardware; Not found for software]**
- **AI drug discovery: no public partnership found** with 晶泰 (XtalPi), 英矽 (Insilico), 深势 (DP Technology), 百图生科 (BioMap), 华为云盘古药物, 腾讯 iDrug or 阿里云 for drug discovery. SYSUCC does run a 药物化学合成平台 (medicinal-chemistry synthesis platform) and 抗体蛋白平台 (antibody/protein platform). **[Not found]**
- **IT maturity:**
  - EMR rating (电子病历评级): **Level 5, achieved 2021**. Level-6 work began in 2021–22, and the Apr 2025 一体化三期 tender mentions "电子病历七级专题建设". No public list shows SYSUCC passing level 6.
  - Interoperability rating (互联互通): not found on the 2021–2023 national lists.
  - Cybersecurity classification (等保): core systems passed 2017; a 2025–2027 等保 assessment survey was issued in 2024.
  - Internet hospital: "云诊室" since 2018, with an internet-hospital service award in 2020.
- **2025–26 priorities, as stated:**
  - "Every scenario is worth redoing with LLMs" (Li, Mar 2025), 120+ planned LLM scenarios, and about 170 doctor-built agents.
  - The colorectal-cancer decision model **"天枢" (Tianshu)**, launched 2025-12-06 (crcai.sysucc.org.cn), to be extended to gastric and lung cancer and to multimodal (vision–language).
  - Hallucination control and traceability.
  - Data classification and grading (全院临床数据分类分级, Aug 2025).
  - Clinical-trial IT: EDC, GAMP5 validation, central randomization.
  - Molecular-diagnostics AI: sequencing-report recognition models, plus the bioinformatics compute platform.

---

## 2. Detailed findings

### 2.1 Director and the Information Center's structure

| Item | Finding | Source / date |
|---|---|---|
| Director | **李超峰 (Li Chaofeng)**, 主任 | SYSUCC dept page http://sysucc.org.cn/xxzx and https://sysucc.org.cn/department/introduction/88 (page footer "更新时间 2020.9.29") |
| Deputies | 任忠敏, 何仲廉 | same |
| Staffing (2020) | 22 people: software group (11), hardware group (8), **AI Lab (2)**, library (1). *Likely outdated, since the AI program has grown a lot.* | same |
| Bio (2021) | Director, senior engineer; hospital IT, medical big data and AI; NPC research; NSFC and provincial grants; papers in *Lancet Oncology*, *JNCI*, *CCR* | http://m.gdpmaa.com/home/Meeting/cententshow/action/speakers/meetingid/305/id/3077 (2021-03-16) |
| Bio (2022) | Leads 2 NSFC grants and 2 provincial grants; participant in 3 national key R&D programs; 20+ papers incl. *AI in Medicine* | http://tool.kunbocs.cn/2022bssf/index.php?name=李超峰 |
| Bio (2026) | Also **joint professor, SYSU School of Software**; **chair (主任委员), Medical Informatics Branch, Guangdong Medical Equipment Society**; vice-chair, Hospital IT Committee, Guangdong Hospital Association; standing member, China Anti-Cancer Association Information Management Committee and Guangdong Medical Association AI Branch | http://m.gdpmaa.com/home/Meeting/cententshow/action/speakers/meetingid/3723/id/52736 (2026-09-17) |
| Academic profile | Co-author on SYSUCC NPC deep-learning papers, e.g. an MRI 3D-CNN + XGBoost prognostic system (JNCI 2021, with Ping An); the profile lists h-index ~37 | https://pmc.ncbi.nlm.nih.gov/articles/PMC8096375/ |
| History | Founded 1993 as 信息科 and renamed 信息中心 in 2020. Accenture 5-year IT blueprint (2015); active-active data centre (2015); integration platform and HRP (2016); integrated system (2017); **big-data platform and AI Lab (2018)**; in-house AI diagnosis and RT contouring (2019+) | dept page above |
| Office / contacts | 1号楼9楼, 东风东路651号; xxk@sysucc.org.cn. Procurement contacts seen in notices: 冯晨阳 (LLM / AI follow-up), 刘少堃 (EMR / integrated system), 李工 libin@ (GPU / compute platforms), 廖老师 (EDC / clinical research DB), 孙老师 (data classification) | various notices below |

Mission statement: no formal mission text was found. The department page frames the goal as "智慧医院建设". Li's own framing (Mar 2025, 中新经纬 via Tencent News) is that "every scenario in patient care and diagnosis is worth redoing with LLMs". He also said SYSUCC was "the first hospital in China to use LLMs" (for administrative assistance, before DeepSeek). Source: https://news.qq.com/rain/a/20250317A06JE100

### 2.2 Current AI platform, DeepSeek deployment and winning vendors

**a) Yidu Tech AI middle platform + DeepSeek (core platform) [Confirmed]**
- 2025-02-27: Yidu completed a private deployment of its **AI中台**. The engines are **DeepSeek-R1 671B (full model)** and **YiduCore**, Yidu's own medical model and knowledge graph. It is embedded in the doctor workstation, with three use cases: consultation and query, medical-record generation, and decision support (TNM staging, treatment-plan lists with evidence). The deployment took about 3 weeks.
  - https://bydrug.pharmcube.com/news/detail/91d0550e4d31e0e041c8ad73aad65337 (2025-02-28)
  - https://news.qq.com/rain/a/20250317A06JE100 (2025-03-17)
- Usage and impact: 26k patient-visits served Feb–Jun 2025 (Yidu, 2025-07-09); **60k uses by July 2025, record-writing time down 80%, record review 5× faster** (Li, Guangzhou Daily via SYSU news, 2025-07-14); record drafting cut from 5 min to 30 s.
  - https://www.yidutech.com/news-detail.html?id=296
  - https://www.sysu.edu.cn/news/info/2171/1390811.htm
- "我的智能助手" (My Assistant) lets doctors build their own agents (name it, write a prompt, pick a data scope): 100+ agents within 60 days (CHIMA, May 2025), **about 170 doctor-built agents by May 2026**.
  - https://bydrug.pharmcube.com/news/detail/89f34e7308e92c6e3fb42e78327a6ac5
  - https://news.qq.com/rain/a/20260513A02Q2P00
- Hallucination: Li reported 10–20% hallucination in their oncology decision model during development, and that they are continuously training to cut it (2025-07-14). VTE risk scoring: 50 of 59 human–AI disagreements were adjudicated in the AI's favour (2026-05).
- Yidu said it plans 120+ LLM scenarios with SYSUCC across clinical care, research and management.

**b) Procurement trail for the "AI platform base" [Confirmed]**
| Date | Notice | Outcome |
|---|---|---|
| 2025-06-04 | **基于大模型的智慧医院建设项目市场调研公告**: LLM-based decision support, smart medical records, personalized medical assistant, smart billing, **AI中台底座建设**. Contact 冯工 (fengcy1@). | Market survey only. https://www.sysucc.org.cn/node/10113 (the site redirects some crawlers; content confirmed via search snippet) |
| 2025-11-14 → 2025-12-25 | 智慧临床及结算服务升级建设项目 public tender, run via Bank of China Guangdong's procurement platform (中银智采) | First round failed (流标) 2025-12-25 |
| 2026-02-03 | Same project, result | **医渡云（北京）技术有限公司, ¥9,082,080** https://www.yiliaozhaobiao.com/news-ba5b0b6dd330f5d6c76222d0750b77e1/ |
| 2026-05-11 | Yidu Tech (02158.HK) voluntary announcement. Scope: unified AI management system, **unified algorithm and model library on open-source + medical-domain LLM bases, SFT training of task-specific small models, AI capabilities exposed as agent APIs to all business systems**, covering clinical, research, management and patient service. | https://www.zhitongcaijing.com/content/detail/1439978.html ; https://news.qq.com/rain/a/20260511A02INV00 |

*Inference:* this ¥9.08M award is the follow-on to the June 2025 "AI中台底座" survey (the scope matches). It is not stated explicitly. *Note:* the Zhitong article dates the AI middle-platform deployment to "Feb 2026". Every 2025 source says 2025-02-27, so treat "2026" as a reporting error.

**c) Other AI / LLM procurements (small, in-hospital) [Confirmed]**
| Date | Project | Budget / award | Vendor |
|---|---|---|---|
| 2025-01-06 | 人工智能辅助病案编码系统 (AI medical-record coding), XM2401196 | ¥190k cap | Winner not found. https://sysucc.org.cn/node/9053 |
| 2025-06-26 | AI智能语音随访 (AI voice follow-up: outbound calls, NLP Q&A, auto data entry, risk triage) partner call | — | Winner not found. http://www.sysucc.org.cn/node/10243 |
| 2025-07-04 | 多模态影像三维重建系统 (segmentation, 3D reconstruction, surgical planning) survey, 2nd round | — | Winner not found. https://sysucc.org.cn/node/10306 |
| ~2026-09-18 | **AI智能体桌面工作台服务** (AI agent desktop workbench), XM2600950 | **¥180,576** | **广州米听信息技术有限公司**. http://www.sysucc.org.cn/cgjggg ; https://bid360.com.cn/zbgs/U-vzcz3gF.html |
| 2026-09-07 / 09-19 | **AI管理平台及智能大模型服务** (AI management platform + LLM service), ¥190k cap; delivery at the Information Center, 1号楼9楼 | Platform ¥2,000 + **LLM service ¥180,000** | **广州讯中信息科技有限公司** (also sells "AI management platform + LLM API service" to other Guangzhou buyers, so it is likely an LLM API reseller/integrator) https://www.dingbiao.com/zhaobiao/d9e0de1644121a932f25eca6cd61a9b3.html ; https://www.anfangzhaobiao.com/news-ffe672500dab0e0378a6446188778ae9/ |
| 2026-10 | 分子诊断报告系统智能化改造 (molecular-diagnostics reporting: sequencing-report **recognition-model build and tuning**, specimen management) | ¥190k cap | Open. http://www.sysucc.org.cn/cggg |

*Pattern [Inferred]:* many AI items are bought at or just under **¥190k through in-hospital negotiation or quotation (院内谈判/询价)**. This is a fast, low-friction route for a scoped pilot. The large platform items go to public tender.

**d) Compute / GPU [Confirmed unless noted]**
- 2026-04-17: **GPU服务器采购（2025）** market survey: "为了建设人工智能应用需求…采购一批服务器用于计算平台建设". Contact 李工, libin@sysucc.org.cn, 020-87345390. **No award found.** https://sysucc.org.cn/node/12424
- 2026-10-01: Experimental Research Dept is bidding on **NVIDIA DGX Spark GB10** "AI科研计算工作站" (¥45k). https://gd.zhiliaobiaoxun.com/article/114781444
- 2026-05: Hadoop big-data-platform server disk expansion (small purchase XM2600277). https://www.guangsuzb.com/succeed_v_2052216748955848708.html
- **The GPU hardware behind the DeepSeek-R1 671B deployment is not publicly disclosed.** No DeepSeek 一体机, Ascend or H20 procurement found. **[Not found]**

**e) Vendors checked with no SYSUCC AI-platform award found:** 浪潮 (Inspur), 腾讯 for LLMs (Tencent appears only for the booking system), 阿里, 百度, 科大讯飞 (iFlytek), 零氪 (LinkDoc), 森亿 (Synyi), 惠每, 嘉和美康, 卫宁, 创业慧康, 联影智能, 深睿, 推想, 数坤, 智谱, 百川. Lenovo appears only as HPC hardware. Huawei appears for the storage/data lake (2.3).

### 2.3 Research data platforms

| Platform | What | Vendor | Source |
|---|---|---|---|
| **Oncology big-data platform** (肿瘤专科大数据平台, T+0 real-time) | Since 2015; built 2018. 30–56 source systems (the figure grows across sources); 3,000 governed fields growing to **8,000+ structured fields**; **2M+ patients' full disease course**; patient timeline embedded in 20+ systems (45k visits/day) | **Yidu (YiduCore)** | pharmcube 2025-02-28; CHIMA talk 2025-05-20; Tencent News 2026-05-13 |
| **Research platform / disease-specific databases** (全瘤种科研平台 / 专病库) | **43 disease-specific databases**, 2M+ searches/yr; supported 2,045 projects (2024), 3,600 (May 2025), **5,000+ studies and 500+ papers (May 2026)**; NPC, CRC and liver-cancer data standards. The NPC database was acknowledged in a 2024 *Lancet* paper (马骏's group). | **Yidu (医渡云)** | https://www.yidutech.com/news-detail.html?id=236 (2024-06-04) |
| NPC big-data intelligence platform (academic description) | 54,703 NPC patients, 981 variables, 13 EHR systems, weekly refresh (BJR 2019; co-authors from YiduCloud) | Yidu | https://pmc.ncbi.nlm.nih.gov/articles/PMC6774598/ |
| Big-data platform phase 2 (大数据平台二期) | 2020 public tender, ¥6.6M: data access, governance, data services, AI application system | Winner not found (very likely Yidu **[Inferred]**) | https://bid.10huan.com/2020/xm/202101/03/xm2923139.html |
| CDR (integration platform) | 2018 tender, ¥448k | **东软 Neusoft** | https://bid.10huan.com/2018/zhb/201807/10/bid_8841cd74c89d0aa50bfe598de4ae809b.html |
| **AI data lake** (融合医疗AI数据湖) | All-flash distributed storage plus a unified data space across 3 campuses; ~10 PB/yr of new data; "data stays in-domain, usable but not visible" (数据不出域、可用不可见); **pathology–genomics–imaging alignment for multi-omics AI training**; plans for federated learning; validating storage for gene-sequencing workloads. 2025 China Computing Power Conference innovation case. | **Huawei** | https://www.odcc.org.cn/news/p-1978991561917935617.html (2025-10-17) |
| Clinical-research DB registration platform (临床研究数据库备案平台) | Maintenance 2025–2028, ¥25k | not found | https://www.sysucc.org.cn/node/10105 |
| EDC (IIT trials) | Survey (2nd round) 2025-06-24: eCRF, E2E auto capture, query management, auto-coding, links to follow-up and randomization | **No award found** | http://www.sysucc.org.cn/node/10220 |
| Clinical-trial systems GAMP5 validation | Survey 2026-06-10 (IQ/OQ/PQ for trial-data, imaging-response, AE and e-prescription systems) | open | https://sysucc.org.cn/scdygg?page=0 |
| Central randomization system | Listed as live on the Information Center page | not found | http://sysucc.org.cn/xxzx |
| Biobank (生物资源库, since 2002) | SYSU Precision Medicine Center model biobank at SYSUCC; −80 °C automated storage; SYSU-level biobank information-sharing system. Sample-processing equipment bought 2026 (¥980k). | Biobank **informatics** vendor not found | http://www.sysucc.org.cn/department/introduction/185 ; https://www.sysu.edu.cn/news/info/2161/513171.htm |
| Pathology + molecular information system | Maintenance 2026–2028, ¥572k | Masked ("广州****公司") | https://biaoxun.shuidi.cn/detail/d1193befd83b1b99cd2c036ef92c6f91.html |
| Data classification and grading (全院临床数据分类分级) | Partner call 2025-08-12, under the Data Security Law and the health-sector data classification guideline | open/unknown | http://www.sysucc.org.cn/node/10554 |
| Operations data-analysis platform | Tender result 2024-08-29 | masked | http://gd.czhaobiao.com/zb-164480211-2.html |

### 2.4 Research AI, bioinformatics and scientific computing for faculty

- **2020 HPC cluster:** "中山大学肿瘤防治中心高性能计算集群", bought via SYSU; ¥2.96M; **广州成翔计算机有限公司**; 20× **Lenovo SD530** compute nodes. https://bid.10huan.com/2020/zhb/202006/20/zhb2661794.html **[Confirmed]**
- **2026 bioinformatics HPC service platform (生信高性能服务平台, GC-HGX260773):** public tender via the Central Government Procurement Center; budget ¥2.1M; tender 2026-08-24; **award 2026-09-28 for ¥1.3965M**. Items: 2× Lenovo WR5220 G3 large-memory compute nodes (¥365k each), 1× **Lenovo WA5680 G3 GPU node** (¥400k), 1× WR5220 G3 high-performance storage node; 10-year service. The winner's name is masked. Its address (广州市黄埔区科学大道48号2216-2218) matches the 2020 winner 成翔's address **[Inferred: same reseller]**. https://www.dingbiao.com/zhaobiao/c4e201f861d14fb9e19e5f8da4f9e83c.html ; https://www.hangnian.com/info-6a8c1fc6c36500001d0079c2.html
- **2026-05-11: 分子诊断数据整合分析计算平台** (molecular-diagnostics data integration and analysis compute platform) market survey from the Information Center, "为了建设分子诊断科生信数据整合分析应用". Contact 李工 libin@. **No award found.** https://www.qianlima.com/bid-595994414.html
- **Bioinformatics centre** in Xu Ruihua's (徐瑞华) team, led by 刘泽先 (Liu Zexian): 1 PB storage, several clusters and workstations. https://show.eqxiu.com/s/86ZN0Y0c
- **State Key Laboratory of Oncology in South China** (107 PIs) public platforms include a tumour sample bank and medical big-data platform, multi-omics, **bioinformatics and supercomputing**, a medicinal-chemistry synthesis platform, an antibody/protein platform, high-throughput sequencing and single-molecule sequencing. https://mp.weixin.qq.com/s/hzk5j0zWXeuRuSwfOmdWfA (2025); http://www.sysucc.org.cn/department/introduction/185
- At SYSU level, the Precision Medicine Science Center has an AI medical platform and access to the Tianhe-2 supercomputer (2020 interview). https://pm.sysu.edu.cn/article/140
- **AI drug discovery partnerships: none found** (XtalPi, Insilico, DP Technology, BioMap, Huawei Pangu Drug, Tencent iDrug, Alibaba Cloud). **[Not found]**. Absence of evidence is not proof; individual PIs may have ties.

### 2.5 IT maturity indicators

| Indicator | Finding | Source |
|---|---|---|
| EMR functional rating (电子病历) | **Level 5 (2021)**. Level-6 upgrade program launched in 2021–22 (VTE, ECG, ultrasound, pathology, EMR phase 4). **2025-04 一体化三期 upgrade lists "电子病历七级专题建设"**, so they are targeting level 7. No public evidence of passing level 6 (not in the 2024 new-level-6 list). | https://sysucc.org.cn/node/1331 ; /node/1351 ; https://xunbiaobao.baidu.com/biddingDetail/bid_808da077731bc90e6190d04f89884eedabd64f7a ; http://www.cn-witmed.com/list/13/15821.html |
| Interoperability (互联互通) | **Not found** on the 2021, 2022 or 2023 national result lists | NHC PDFs; https://www.gdhealth.net.cn/html/2025/xinxijianshe_0120/4484.html |
| Smart service (智慧服务) rating | Level not found. Internet hospital "云诊室" since 2018-05; precise appointments (2018); Guangzhou internet-hospital excellence award (2020). | http://www.sysucc.org.cn/node/2589 ; https://healthcare.tencent.com/case/60 |
| Cybersecurity classification (等保) | HIS, website, HRP and OA passed the national 等保 assessment in 2017; a 等保 assessment service (2025–2027) market survey was issued 2024-04 | dept page; search snippet |
| Infrastructure | Active-active data centres (2015) plus disaster-recovery room; 3 campuses (越秀, 黄埔, 天河 under construction); 56 systems integrated into the data/AI platform | dept page; Tencent News 2026-05-13 |
| Recognition | Guangdong Health Commission's first batch of "AI+医疗卫生" scenario cases (2025-07); Yidu case named a Beijing AI-empowerment exemplar (2025-07); Huawei data lake named an innovation case (2025-10); Tencent booking system named a CHIMA 2024 typical case | sources above |

### 2.6 Stated priorities for 2025–2026

1. **Full-scenario LLM adoption.** Li Chaofeng (2025-03): integrate the assistant into workflows proactively ("被动变主动"), keep adding expert experience and consensus to the knowledge base, and strengthen oncology-specialty ability. Plan: 120+ scenarios.
2. **Oncology-specialty models.** **"天枢" (Tianshu) colorectal-cancer decision model**, launched 2025-12-06 and led by President Xu Ruihua (徐瑞华, CAE academician), with Li Chaofeng presenting the technology. It is trained on about 3M real-world records and offers Q&A, individualized treatment plans, similar-case retrieval and **clinical-trial matching**. Roadmap: vision–language multimodal, extension to gastric and lung cancer and a cross-cancer platform, multi-centre validation, and a lightweight version for primary-care hospitals. It is described as self-developed (Yidu's role in it is not stated). https://news.sciencenet.cn/htmlnews/2025/12/556588.shtm ; https://static.nfnews.com/content/202512/06/c11971973.html
3. **Unified AI management, model library and agent APIs** (Yidu ¥9.08M project, 2026).
4. **Data governance and security:** data classification and grading (2025-08), private deployment, de-identification, "data stays in-domain" (数据不出域).
5. **Multimodal / multi-omics:** Huawei data lake for pathology–genomics–imaging; federated learning next.
6. **Clinical-trial and research IT:** EDC, GAMP5 validation, randomization.
7. **Bioinformatics compute:** bioinformatics HPC service platform (awarded), molecular-diagnostics bioinformatics integration platform and GPU compute platform (both in survey stage).
8. **Investment signal:** at a May 2026 investor visit hosted by SYSUCC and Yidu, the hospital said its AI-related spending share keeps rising; budgets are becoming annual and "infrastructure-like" (Yidu-sourced and promotional, so discount accordingly). https://news.qq.com/rain/a/20260513A02Q2P00
9. Context: Guangdong's 8-department **《广东省加快"人工智能+医疗卫生"发展行动方案（2025—2027年）》** (2025-06). The 2026-09-06 SYSU seminar "AI赋能医疗数据资源管理与利用" covered data assets (数据要素资产化), data lakes and valuation; SYSUCC's own participation was not detailed. https://www.sysu.edu.cn/news/info/1901/1418081.htm
10. **Data elements (数据要素), trusted data spaces (可信数据空间), data asset accounting (数据资产入表) at SYSUCC: [Not found].**

---

## 3. Implications for BioMate positioning

**Where we would overlap with an entrenched vendor (avoid leading with these):**
- **Clinical LLM assistant, EMR generation, TNM staging, CDSS, doctor agent builder, AI middle platform and model library.** Yidu has 10+ years of embedded co-development, owns the data foundation (8,000+ fields, 43 disease-specific databases) and has just won ¥9.08M for exactly the "AI中台/model library/agent API" layer. Pitching a competing clinical AI platform would be seen as a direct challenge to Yidu and to the Director's flagship program.
- **Generic LLM API / agent workbench.** Already bought cheaply (讯中 ¥180k, 米听 ¥180k).
- **Data lake / storage / HPC hardware.** Huawei and Lenovo (via reseller) already hold these.

**Where BioMate complements the stack (lead with these):**
1. **A software layer for the bioinformatics compute they are buying right now.** The ¥1.4M bioinformatics HPC platform is hardware only. The molecular-diagnostics integration platform and the GPU compute platform are still in survey. BioMate's 4,000+ indexed Nextflow / nf-core / Bioconductor workflows (RNA-seq, WGS/sarek variant calling, single-cell, epigenomics), natural-language → workflow routing, parameter prefill, QC gates with auto-remediation and auto-generated findings/methods reports could make that hardware usable by clinicians and PIs without bioinformatician bottlenecks. This fits the 分子诊断科 sequencing-report needs and the Huawei data lake's genomics alignment.
2. **Research-side AI, as opposed to the clinic-side AI Yidu covers.** Faculty-facing analysis: multi-omics, survival / real-world-evidence statistics on de-identified exports from the disease-specific databases, reproducible pipelines with audit trails. Position it as **a consumer of the Yidu research platform's data**, not a replacement.
3. **Drug discovery and translational work** (no incumbent found): ADMET screening, PBPK, BOIN / dose-escalation design support, and IND §2.6.1 narrative drafting. These fit SYSUCC's medicinal-chemistry, antibody and Phase I / IIT activity and the EDC / GAMP5 trial-IT push.
4. **CRO / compliance outputs:** traceable reports matching their "可溯源" requirement and GAMP5 validation mindset.

**Hard constraints to address up front:**
- **"Data stays in-domain" (数据不出域) and private deployment are non-negotiable.** Everything SYSUCC runs (Yidu, DeepSeek, Huawei) is on-prem. BioMate's default AWS Batch execution would not be acceptable for patient or genomic data. We need an **on-prem / private-cloud deployment story**: Nextflow on their Lenovo HPC (Slurm or local executor) or their GPU platform, local LLM endpoints (they already host DeepSeek-R1 671B), and no data egress. If that is not productized yet, say so and propose a de-identified or public-data pilot.
- **Domestic-model preference:** routing to their in-house DeepSeek (or Yidu's model APIs) instead of foreign LLM APIs is likely required.
- **Procurement path:** a pilot scoped at or under **¥190k via 院内谈判/询价** run by the Information Center is the observed fast lane. Larger platform deals go to public tender. Notices are issued by the Information Center (李工 for compute platforms, 冯工 for LLM projects).
- **Integration rather than rip-and-replace:** offer to expose BioMate as an agent or tool inside Yidu's agent-API framework, or to consume data from the research platform. A partner or co-bid with Yidu (or the Lenovo reseller) may be smoother than a solo bid. **[Inferred]**

---

## 4. Questions for the meeting

**Strategy and roadmap**
1. Of the 120+ LLM scenarios, which research-side scenarios (not clinical) are planned, and who owns them: the Information Center, the Research Office (科研处) or the State Key Lab?
2. Tianshu is going multimodal and expanding to gastric and lung cancer. Is genomic or molecular data in scope, and what is the compute plan?
3. How does the Information Center split responsibility with the State Key Lab's bioinformatics and supercomputing platform and Xu Ruihua's bioinformatics centre?

**Compute and bioinformatics**
4. Now that the bioinformatics HPC service platform has been awarded: what software stack and scheduler will it run (Slurm? containers?), who are its users, and is there a workflow or pipeline layer planned?
5. What is the status and scope of the GPU computing-platform and molecular-diagnostics bioinformatics integration platform surveys: which assays (panels, WES/WGS, RNA), what volumes, what turnaround targets?
6. What GPU capacity serves DeepSeek-R1 671B today, and is there headroom for research workloads?

**Data access and governance**
7. How do faculty access research-platform and disease-specific database data for analysis today (export, in-platform statistics, sandbox)? Is there a sanctioned "data stays in-domain" compute environment for third-party tools?
8. How does the data classification and grading project affect which data tiers can feed AI or bioinformatics tools?
9. Requirements for any new vendor: on-prem only? domestic LLM only? 等保 level? GAMP5 or CSV validation?

**Drug discovery and trials**
10. Are there current AI drug-discovery or computational-chemistry needs (medicinal-chemistry synthesis platform, antibody platform, Phase I unit)? Any existing partners we should know about?
11. EDC / IIT: was the EDC awarded? Would ADMET, PBPK or trial-design support (BOIN) or regulatory narrative drafting be useful for investigator-initiated trials (IITs)?

**Commercial path**
12. Preferred pilot format and size (院内谈判 ≤¥190k?), the evaluation criteria, and whether integration via Yidu's agent-API layer is preferred or required.

---

## 5. Gaps / not found (for follow-up)

- Winners for: AI medical-record coding (2025-01), AI voice follow-up, 3D reconstruction, EDC, GPU servers (2025 batch), molecular-diagnostics compute platform, big-data platform phase 2 (2020).
- GPU and accelerator hardware behind the DeepSeek deployment.
- Whether EMR level 6 or 7, interoperability, or smart-service ratings have been achieved (nothing on public lists through the 2024 EMR / 2023 interoperability cycles).
- Formal mission statement and current headcount of the Information Center (the official profile is from 2020).
- Any AI drug-discovery collaborations.
- The SYSUCC site redirects automated fetches (HTTP 302), so some notices were read only through search-engine snippets or bidding aggregators. The facts cited match across multiple aggregators.
