/* d3 · 中文 — same run as d3, content translated. Load after runs-more.js. */
(function(){const U=window.BMUI;if(!U.runs.d3)return;
const X={'Lead design · seed scaffold':'先导设计 · 种子骨架','REINVENT4 generative lead design':'REINVENT4 生成式先导设计','REINVENT4 · reinforcement learning · qed_sa scoring · 2 phases':'REINVENT4 · 强化学习 · qed_sa 打分 · 2 个阶段',
'Design new candidates around this scaffold — drug-like, easy to make, no PAINS.':'围绕这个骨架设计新的候选分子：类药、易合成、无 PAINS。',
'Plan — validate the seed, run REINVENT4 (qed_sa, 500 steps, batch 128), then filter (QED ≥ 0.4, SA ≤ 5.0, MW ≤ 500, no PAINS) and rank diverse candidates. Review the settings and confirm.':'计划 — 校验种子结构，运行 REINVENT4（qed_sa，500 步，批大小 128），再过滤（QED ≥ 0.4、SA ≤ 5.0、分子量 ≤ 500、无 PAINS）并排序，保持候选分子的多样性。请核对设置后确认。',
'Seed validated · QED, SA and MW computed.':'种子结构已校验 · 已计算 QED、SA 和分子量。','REINVENT4 generation completed · 500 steps.':'REINVENT4 生成已完成 · 500 步。','Candidates filtered and ranked.':'候选分子已过滤并排序。','Report and output files saved.':'报告与输出文件已保存。',
'1 seed · pre-filled':'1 个种子 · 已预填','Seed scaffold':'种子骨架','1 structure · overridable':'1 个结构 · 可修改','Seed':'种子','Seed parsed':'种子已解析','QED · SA · MW':'QED · SA · 分子量','computed in step 1':'在第 1 步中计算',
'Design mode':'设计模式','De novo':'从头设计','Scoring':'打分方式','QED floor':'QED 下限','SA ceiling':'SA 上限','MW ceiling':'分子量上限',
'Generate':'生成','Validate seed':'校验种子结构','REINVENT4 generator':'REINVENT4 生成器','step 312 / 500':'第 312/500 步','before ranking · fails loudly if missing':'排序之前 · 缺失时明确报错','Prior and model loaded':'先验与模型已加载','present':'已就绪',
'Filter and rank':'过滤与排序','Write outputs':'写出结果','per candidate · rejected stay visible':'逐个候选分子 · 被淘汰的仍然可见','Synthetic accessibility':'可合成性','1 rejected':'1 个被淘汰','no alert':'无警示',
'Phase B · Filter and rank':'阶段 B · 过滤与排序','Phase B · Write outputs':'阶段 B · 写出结果','Candidate':'候选分子','Score':'得分','Verdict':'结论','accepted':'入选','rejected · PAINS':'淘汰 · PAINS',
'REINVENT4 reinforcement-learning generator, qed_sa reward, medicinal-chemistry filters.':'REINVENT4 强化学习生成器，qed_sa 奖励，药物化学过滤条件。','REINVENT4 · RDKit — versions not recorded':'REINVENT4 · RDKit — 版本未记录','routed → seed validated → generation → filter and rank → outputs saved':'路由 → 校验种子 → 生成 → 过滤与排序 → 保存输出',
'Candidate design — REINVENT4 around the seed scaffold':'候选分子设计 — 围绕种子骨架的 REINVENT4',
'Three candidates (BM-0001, BM-0002, BM-0003) pass the filters; BM-0014 is rejected on QED, SA and a PAINS alert. Scores are the qed_sa reward, not measured affinity.':'三个候选分子（BM-0001、BM-0002、BM-0003）通过过滤；BM-0014 因 QED、SA 和 PAINS 警示被淘汰。得分是 qed_sa 奖励，不是实测亲和力。',
'Input':'输入','Role':'用途','Rows':'行数','starting structure':'起始结构',
'REINVENT4 (reinforcement learning, qed_sa scoring, 500 steps, batch 128) generated candidates, which were filtered on QED, SA, MW and PAINS alerts and ranked for diversity by Murcko scaffold.':'REINVENT4（强化学习，qed_sa 打分，500 步，批大小 128）生成候选分子，再按 QED、SA、分子量和 PAINS 警示过滤，并按 Murcko 骨架保持多样性后排序。',
'<b>Three candidates are accepted; BM-0014 is rejected.</b> BM-0001 leads on score. The rejected candidate stays listed with its reasons.':'<b>三个候选分子入选，BM-0014 被淘汰。</b>BM-0001 得分最高；被淘汰的候选分子连同原因仍然列出。',
'4 candidates after filtering · REINVENT4 (qed_sa) · the score is the reward you set, not a measured affinity':'过滤后共 4 个候选分子 · REINVENT4（qed_sa）· 得分是你设定的奖励，而非实测亲和力',
'Score (qed_sa)':'得分（qed_sa）','SA score':'SA 评分','Structural alert':'结构警示','meets the QED floor':'满足 QED 下限','below the QED floor':'低于 QED 下限','within the SA ceiling':'在 SA 上限之内','above the SA ceiling — hard to make':'高于 SA 上限 — 难以合成','no alert':'无警示','PAINS match — removed from the top-N':'命中 PAINS — 已从前 N 名中移除',
'workflow default · FILTER_RANK':'工作流默认 · FILTER_RANK','row by candidate id':'按候选分子编号定位','The ranking is only as good as the scoring function; candidates are a hypothesis queue for the lab.':'排序的可靠程度取决于打分函数；候选分子是交给实验室验证的假设清单。','Filter and rank':'过滤与排序','Loeffler 2024':'Loeffler 2024'};
const KEEP=new Set(['from your message','recommended','default','pass','flag','adv','ne','unav','Table','Figure','Report','Log','Structure','BioMate','none','PAINS']);
const SK=new Set(['o','type','kind','key','region','_region','id','provenanceRef','scope','flag','evidenceClass','identitySource','scheme','comparator','entityType','outputRef','locator','file','qcRegion','origin','source','execution','x','name']);
const walk=(v,k)=>{if(typeof v==='string'){if(KEEP.has(v)||(SK.has(k)&&k!=='name'&&k!=='source'&&k!=='file'))return v;if(k==='name'&&(/\./.test(v)||/^BM-/.test(v)))return v;return X[v]!=null?X[v]:v;}
 if(Array.isArray(v))return v.map(x=>walk(x));if(v&&typeof v==='object'){const o={};for(const kk in v)o[kk]=walk(v[kk],kk);return o;}return v;};
const z=walk(U.runs.d3);z.id='d3zh';U.runs.d3zh=z;
if(U.findings&&U.findings.d3)U.findings.d3zh=z.summary[0].doc;})();
