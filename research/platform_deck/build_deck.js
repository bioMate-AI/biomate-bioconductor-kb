// BioMate Platform Deck — EN + CN. pptxgenjs structured build.
const pptxgen = require("pptxgenjs");

// ---- palette (bioinformatics platform: navy dominant, teal signal, blue continuity) ----
const C = {
  ink:   "0F2A43", // deep navy (dominant / dark slides)
  ink2:  "17395A",
  teal:  "1C8C8C", // science signal
  blue:  "3F6FD1", // continuity w/ existing deck
  slate: "5B6B7C", // muted text
  green: "2BA84A", // QC pass / biology
  amber: "E0922F", // QC halt
  purple:"7E57C2",
  bg:    "FFFFFF",
  bg2:   "F3F6FA", // light card tint
  line:  "DBE3EC",
  white: "FFFFFF",
  faint: "AEBBC9",
};
const HEAD = "Calibri", BODY = "Calibri";
let FF = "Calibri"; // set per-language in buildDeck
const ASSETS = "/Users/kky/biomate-review/docs/user-manual/assets";

// ---------- content (from docs/20261014_PLATFORM_DECK_CONTENT.md) ----------
const EN = {
  tagline: "Search · Run · Verify · Learn",
  sub: "The AI bioinformatics platform — from any instrument and dataset to a reproducible, decision-ready result",
  kick: ["", "The problem", "Why BioMate", "Research domains", "Instruments", "Search & evidence",
         "Product", "Execution + QC", "Engineering", "Value", "Deliverable", "Get started"],
  s2t: "Bioinformatics today is fragmented",
  s2: [["Tools scattered per domain","RNA-seq, variants, proteomics, cryo-EM each need different, separately-licensed software"],
       ["Instruments are islands","A sequencer, flow cytometer, LC-MS or plate reader each writes files someone copies by hand"],
       ["Expert workflows aren't captured","How an analyst chose a method or threshold lives in their head, not the system"],
       ["Results don't accumulate","Runs, QC and negative results aren't fed back into a reusable knowledge base"],
       ["Compute is outsourced & costly","Multiple specialist packages bought and maintained separately"],
       ["Data security & compliance","Research data is core IP; external tools and outsourcing carry leakage risk"]],
  s3t: "One platform, every domain, your environment",
  s3: [["One platform across domains","Search, run and read results for any bioinformatics task in one workspace"],
       ["Instrument connectivity","Real connectors for sequencers, flow cytometers, LC-MS, plate readers, cryo-EM, liquid handlers, ELN/LIMS"],
       ["Search built in","Literature, databases and a 4,210-workflow catalog, routed to the right method"],
       ["Unified execution","Cloud (AWS Batch / Nextflow) or on-prem, with QC gates and a closed loop that learns from each run"],
       ["Private & auditable","Data stays in your environment; deterministic execution; versioned, traceable evidence"]],
  s4t: "42 domains · 4,210 workflows · 12,312 tools",
  s4sub: "Drug discovery is one domain among many",
  s4: [["Transcriptomics","1,695"],["Genomics","756"],["Epigenomics","265"],["Drug discovery","200"],
       ["Proteomics","186"],["Variant calling","181"],["Single-cell","100"],["Cryo-EM","19"],
       ["Metabolomics","·"],["Metagenomics","·"],["Immunology","·"],["Structural biology","·"]],
  s4foot: "1,092 workflows carry clean real-execution evidence (validated subset)",
  s5t: "From the bench instrument to the analysis, in one flow",
  s5: [["Flow cytometer (FCS)","gating → marker-positive subset quantification (immunophenotyping)"],
       ["Plate reader (BMG/BioTek/Tecan)","ELISA standard-curve → titers by group"],
       ["LC-MS (Thermo/Waters/Bruker/SCIEX)","proteomics / metabolomics"],
       ["Sequencers (Illumina / Nanopore)","FASTQ → the matching pipeline"],
       ["Cryo-EM (Thermo EPU)","single-particle reconstruction"],
       ["Liquid handlers · ELN/LIMS","Opentrons (driven from chat) · Benchling"]],
  s5foot: "Real connectors in backend/lib/integrations — residency-aware (on-prem / mount / cloud)",
  s6t: "Find the right method, and the evidence behind it",
  s6: [["Workflow routing","Describe the goal in plain language; BioMate selects from 4,210 workflows and explains why"],
       ["Accession → workflow","Paste a GEO/SRA/EMPIAR accession; it resolves modality and the matching pipeline"],
       ["Literature","Grounded literature Q&A with citations — not fabricated references"],
       ["Databases & structures","Activity/SAR, structure and similarity search; FTO/patent where applicable"]],
  s6foot: "Every routing decision is explained; every number traces to its source file",
  s7t: "A project-centric workspace",
  s7: ["One workspace per project — chats, data, workflows and runs together",
       "The workflow panel — an RNA-seq run: params before it runs, phases live, one merged Results report after",
       "Attach data or bind an instrument/accession; preview every input as an object, not a path string",
       "Pilot a small subset before a full run; override parameters and QC thresholds inline",
       "Results write back to your ELN / data systems"],
  s8t: "Run anywhere, with quality gates and a closed loop",
  s8: [["Execution","AWS Batch + Nextflow DSL2 in the cloud, or on-prem; jobs stream results to storage"],
       ["Phases & steps","Every run is broken into inspectable phases and tool steps"],
       ["QC gates","Automatic mid-run checks that never silently pass a failed result; halt → expert review → resume"],
       ["Auto-loop","On a recoverable failure, remediate parameters and re-run, with the was→now diff shown"],
       ["After-run report","One merged Results view (findings + every output previewed) + a reproducibility record"]],
  s8foot: "Same mechanism across all domains — RNA-seq, variants, proteomics, cryo-EM, ADMET",
  s9t: "Private deployment, auditable, reproducible",
  s9: [["Data stays in your environment","Local / private deployment as the default; compute runs inside your estate"],
       ["Reference data & models localized","Train and fine-tune on your own data"],
       ["Deterministic execution","The same input yields the same output at inference"],
       ["Auditable","Scores shown as formulas and explanation columns; evidence sources traceable"],
       ["Versioned","Production runs only accepted versions, with a change record"],
       ["Permissions & integration","Access by team/project/person; two-way with ELN / compound library / LIMS"]],
  s10t: "What the platform delivers",
  s10: [["Cost","One platform replaces many single-point tools; less compute outsourcing; pilot-before-full-run reduces wasted runs"],
        ["Speed","From data to insight faster; QC gates and auto-loop reduce rework"],
        ["Integration","Instruments, data systems and domains unified; results write back"],
        ["Knowledge","Runs, QC and expert corrections accumulate as reusable, auditable assets"]],
  s11t: "The deliverable is a reproducible result — for any domain",
  s11: [["Findings","A plain-language summary with the key numbers, each traced to its output file"],
        ["Outputs","Every file the run produced, previewed inline by type (table, image, structure, VCF…)"],
        ["Reproducibility record","Workflow, parameters, versions, checksums, methods & citations"],
        ["Next step","What the result supports, and what to run next"]],
  s11foot: "The same package whether the task was RNA-seq, variant calling, an instrument readout, or ADMET",
  s12t: "How we start",
  s12: [["01","Survey & data audit","Your domains, instruments, data systems and goals"],
        ["02","Connect","Wire up instruments / ELN / accessions; bring a representative dataset"],
        ["03","Run","Route to the right workflow, run with QC, read the merged Results report"],
        ["04","Verify","Compare against your established method; retrospective on your historical data"],
        ["05","Deploy","Cloud or on-prem; permissions, versioning and audit configured for your team"]],
  nums: (n)=>n,
};
const CN = {
  tagline: "检索 · 运行 · 验证 · 学习",
  sub: "AI 生物信息平台 — 从任意仪器与数据到可复现、可决策的结果",
  kick: ["", "痛点", "为什么选择 BioMate", "研究领域", "仪器", "检索与证据",
         "产品", "执行与质控", "工程落地", "价值", "交付物", "如何开始"],
  s2t: "当下生物信息分析的痛点",
  s2: [["工具按领域割裂","RNA-seq、变异、蛋白质组、冷冻电镜各需不同且需单独授权的软件"],
       ["仪器成为孤岛","测序仪、流式、液质、酶标仪各自产出文件，需人工搬运"],
       ["专家工作流难沉淀","分析师如何选方法、定阈值只存在脑中，未被系统记录"],
       ["结果不积累","运行、质控与阴性结果未回流到可复用的知识库"],
       ["计算外包且成本高","多套专业软件分别采购与维护"],
       ["数据安全与合规","研发数据是核心知识产权，外部工具与外包存在泄露风险"]],
  s3t: "一个平台，覆盖全领域，部署在你的环境",
  s3: [["一个平台贯通各领域","任意生物信息任务的检索、运行与结果解读，都在同一工作台"],
       ["仪器连接","为测序仪、流式、液质、酶标仪、冷冻电镜、移液机器人及 ELN/LIMS 提供真实连接器"],
       ["内置检索","文献、数据库与 4,210 个工作流目录，智能路由到正确方法"],
       ["统一执行","云端（AWS Batch / Nextflow）或本地部署，带质控门与从每轮运行中学习的闭环"],
       ["私域可审计","数据不出域；确定性执行；结果可版本化、可溯源"]],
  s4t: "42 个领域 · 4,210 个工作流 · 12,312 个工具",
  s4sub: "药物发现只是众多领域之一",
  s4: [["转录组学","1,695"],["基因组学","756"],["表观基因组学","265"],["药物发现","200"],
       ["蛋白质组学","186"],["变异检测","181"],["单细胞","100"],["冷冻电镜","19"],
       ["代谢组学","·"],["宏基因组学","·"],["免疫学","·"],["结构生物学","·"]],
  s4foot: "其中 1,092 个工作流具备干净的真实执行证据（验证子集）",
  s5t: "从实验台仪器到分析，一气呵成",
  s5: [["流式细胞仪（FCS）","圈门 → 标志物阳性亚群定量（免疫表型）"],
       ["酶标仪（BMG/BioTek/Tecan）","ELISA 标准曲线 → 分组滴度"],
       ["液质联用（Thermo/Waters/Bruker/SCIEX）","蛋白质组 / 代谢组"],
       ["测序仪（Illumina / Nanopore）","FASTQ → 对应流程"],
       ["冷冻电镜（Thermo EPU）","单颗粒重构"],
       ["移液机器人 · ELN/LIMS","Opentrons（对话驱动）· Benchling"]],
  s5foot: "真实连接器位于 backend/lib/integrations — 感知数据驻留（本地 / 挂载 / 云）",
  s6t: "找到正确的方法，以及背后的证据",
  s6: [["工作流路由","用自然语言描述目标，BioMate 从 4,210 个工作流中选择并解释原因"],
       ["编号 → 工作流","粘贴 GEO/SRA/EMPIAR 编号，自动识别模态并匹配流程"],
       ["文献","带引用的文献问答 — 不编造参考文献"],
       ["数据库与结构","活性/SAR、结构与相似性检索；适用领域的 FTO/专利"]],
  s6foot: "每个路由决策都有解释；每个数字都可溯源到其来源文件",
  s7t: "以项目为中心的工作台",
  s7: ["每个项目一个工作空间 — 对话、数据、工作流与运行集中在一起",
       "工作流面板 — 一次 RNA-seq 运行：运行前看参数、运行中看阶段、运行后看合并的结果报告",
       "挂载数据或绑定仪器/编号；每个输入都作为对象预览，而非一串路径",
       "全量前可先跑小样试点；参数与质控阈值可就地调整",
       "结果可回写到你的 ELN / 数据系统"],
  s8t: "随处运行，带质控门与闭环",
  s8: [["执行","云端 AWS Batch + Nextflow DSL2，或本地部署；任务将结果流式写入存储"],
       ["阶段与步骤","每次运行拆分为可检视的阶段与工具步骤"],
       ["质控门","运行中自动检查，绝不默默放过失败结果；暂停 → 专家复核 → 恢复"],
       ["自动循环","可恢复失败时自动调整参数重跑，并展示 was→now 差异"],
       ["运行后报告","一个合并的「结果」视图（发现 + 每个输出预览）+ 一份可复现记录"]],
  s8foot: "所有领域共用同一机制 — RNA-seq、变异、蛋白质组、冷冻电镜、ADMET",
  s9t: "私域部署，可审计，可复现",
  s9: [["数据不出域","本地/私有化部署为默认；计算在自有环境内完成"],
       ["参考数据与模型本地化","可在自有数据上训练与微调"],
       ["确定性执行","同一输入在推理阶段得到一致输出"],
       ["可审计","评分以公式与解释列呈现，证据来源可追溯"],
       ["版本化","线上只执行已接受的版本，变更留有记录"],
       ["权限与对接","按团队/项目/人员授权；与 ELN / 化合物库 / LIMS 双向打通"]],
  s10t: "平台能带来什么",
  s10: [["成本","一个平台替代多套单点软件；减少计算外包；先试点后全量，减少无效运行"],
        ["效率","从数据到洞见更快；质控门与自动循环减少返工"],
        ["整合","仪器、数据系统与领域统一；结果回写"],
        ["知识","运行、质控与专家纠正沉淀为可复用、可审计的资产"]],
  s11t: "交付的是可复现的结果 — 适用于任意领域",
  s11: [["发现","自然语言摘要与关键数字，每项溯源到其输出文件"],
        ["输出","运行产出的每个文件，按类型内联预览（表格、图像、结构、VCF…）"],
        ["可复现记录","工作流、参数、版本、校验和、方法与引用"],
        ["下一步","结果支持什么，下一步该运行什么"]],
  s11foot: "无论任务是 RNA-seq、变异检测、仪器读出还是 ADMET，交付同一套结果包",
  s12t: "如何开始",
  s12: [["01","调研与数据审计","你的领域、仪器、数据系统与目标"],
        ["02","连接","接入仪器 / ELN / 编号；带入一份代表性数据"],
        ["03","运行","路由到正确的工作流，带质控运行，查看合并的结果报告"],
        ["04","验证","与你既有方法对比；在历史数据上回顾性评估"],
        ["05","部署","云端或本地；为你的团队配置权限、版本与审计"]],
};

const W = 13.333, H = 7.5, M = 0.7;

function buildDeck(L, isCN, outFile) {
  const p = new pptxgen();
  p.defineLayout({ name: "W", width: W, height: H });
  p.layout = "W";
  FF = isCN ? "PingFang SC" : "Calibri";
  p.theme = { headFontFace: FF, bodyFontFace: FF };
  const BM = isCN ? "BioMate" : "BioMate";

  // ---- helpers ----
  const kicker = (s, n) => {
    s.addText(L.kick[n-1] || "", { x: M, y: 0.34, w: 8, h: 0.3, fontFace: FF, fontSize: 11,
      color: C.teal, bold: true, charSpacing: 2, isTextBox: true, margin: 0, align: "left" });
    s.addText(String(n).padStart(2,"0"), { x: W-1.3, y: 0.3, w: 0.6, h: 0.3, fontFace: FF, fontSize: 11,
      color: C.faint, bold: true, align: "right", isTextBox: true, margin: 0 });
  };
  const title = (s, t) => s.addText(t, { x: M, y: 0.7, w: W-2*M, h: 1.0, fontFace: FF, fontSize: 30,
      bold: true, color: C.ink, isTextBox: true, margin: 0, valign: "top", align: "left" });
  const footer = (s, t) => { if(!t) return; s.addText(t, { x: M, y: H-0.62, w: W-2*M, h: 0.34,
      fontFace: FF, fontSize: 11, italic: true, color: C.slate, isTextBox: true, margin: 0, align: "left" }); };
  const circle = (s, x, y, d, fill, glyph, gcol) => {
    s.addShape(p.ShapeType.ellipse, { x, y, w: d, h: d, fill: { color: fill } });
    if (glyph!=null) s.addText(String(glyph), { x, y: y-0.01, w: d, h: d, align: "center", valign: "middle",
      fontFace: FF, fontSize: 15, bold: true, color: gcol||C.white, isTextBox: true, margin: 0 });
  };

  // ---- Slide 1: title (dark) ----
  let s = p.addSlide(); s.background = { color: C.ink };
  s.addText(BM, { x: M, y: 2.35, w: W-2*M, h: 1.2, fontFace: FF, fontSize: 60, bold: true, color: C.white, isTextBox: true, margin: 0 });
  s.addText(L.sub, { x: M, y: 3.6, w: W-2*M-3, h: 1.1, fontFace: FF, fontSize: 19, color: "CFE0EE", isTextBox: true, margin: 0 });
  // tagline chips
  const tags = L.tagline.split(" · ");
  let tx = M;
  tags.forEach((tg,i)=>{ const w = 0.3 + tg.length*(isCN?0.26:0.11);
    s.addShape(p.ShapeType.roundRect, { x: tx, y: 5.05, w, h: 0.5, rectRadius: 0.1, fill: { color: C.ink2 }, line: { color: C.teal, width: 1 } });
    s.addText(tg, { x: tx, y: 5.05, w, h: 0.5, align: "center", valign: "middle", fontFace: FF, fontSize: 13, bold: true, color: "CFE0EE", isTextBox: true, margin: 0 });
    tx += w + 0.25; });
  s.addText("42 " + (isCN?"领域":"domains") + "  ·  4,210 " + (isCN?"工作流":"workflows") + "  ·  12,312 " + (isCN?"工具":"tools"),
    { x: M, y: 6.25, w: W-2*M, h: 0.4, fontFace: FF, fontSize: 14, color: C.faint, isTextBox: true, margin: 0 });

  // ---- Slide 2: pain points — 2x3 cards (light) ----
  s = p.addSlide(); s.background = { color: C.bg }; kicker(s,2); title(s, L.s2t);
  grid3x2(p, s, L.s2, C.amber);

  // ---- Slide 3: why — 5 icon rows ----
  s = p.addSlide(); s.background = { color: C.bg }; kicker(s,3); title(s, L.s3t);
  iconRows(p, s, L.s3, C.teal);

  // ---- Slide 4: domains ----
  s = p.addSlide(); s.background = { color: C.bg }; kicker(s,4); title(s, L.s4t);
  s.addText(L.s4sub, { x: M, y: 1.55, w: W-2*M, h: 0.35, fontFace: FF, fontSize: 15, italic: true, color: C.slate, isTextBox: true, margin: 0 });
  domainGrid(p, s, L.s4);
  footer(s, L.s4foot);

  // ---- Slide 5: instruments — arrow rows ----
  s = p.addSlide(); s.background = { color: C.bg }; kicker(s,5); title(s, L.s5t);
  instrRows(p, s, L.s5, isCN); footer(s, L.s5foot);

  // ---- Slide 6: search — 2x2 cards ----
  s = p.addSlide(); s.background = { color: C.bg }; kicker(s,6); title(s, L.s6t);
  grid2x2(p, s, L.s6, C.blue); footer(s, L.s6foot);

  // ---- Slide 7: product UI — bullets + screenshot ----
  s = p.addSlide(); s.background = { color: C.bg }; kicker(s,7); title(s, L.s7t);
  bulletsLeft(p, s, L.s7, 6.0);
  try { s.addImage({ path: ASSETS + "/i09-1-three-tabs.png", x: 7.0, y: 1.7, w: 5.6, h: 3.9, sizing: { type: "contain", w: 5.6, h: 3.9 } });
        s.addText(isCN?"合并的「结果」报告 — 发现 + 输出 + 可复现记录":"The merged Results report — findings + outputs + record",
          { x: 7.0, y: 5.65, w: 5.6, h: 0.3, fontFace: FF, fontSize: 10, italic: true, color: C.slate, align: "center", isTextBox: true, margin: 0 }); } catch(e){}

  // ---- Slide 8: execution + QC — 5 numbered blocks + state chips ----
  s = p.addSlide(); s.background = { color: C.bg }; kicker(s,8); title(s, L.s8t);
  numberedBlocks(p, s, L.s8);
  // QC state chips
  const states = isCN ? [["通过",C.green],["暂停·复核",C.amber],["恢复",C.teal]] : [["pass",C.green],["halt · review",C.amber],["resume",C.teal]];
  let qx = M;
  states.forEach(([t,col])=>{ const w=0.3+(isCN?t.length*0.24:t.length*0.1);
    s.addShape(p.ShapeType.roundRect,{x:qx,y:6.25,w,h:0.4,rectRadius:0.08,fill:{color:"FFFFFF"},line:{color:col,width:1.25}});
    s.addText(t,{x:qx,y:6.25,w,h:0.4,align:"center",valign:"middle",fontFace:BODY,fontSize:11,bold:true,color:col,isTextBox:true,margin:0}); qx+=w+0.2; });
  footer(s, L.s8foot);

  // ---- Slide 9: engineering — 2x3 cards ----
  s = p.addSlide(); s.background = { color: C.bg }; kicker(s,9); title(s, L.s9t);
  grid3x2(p, s, L.s9, C.teal);

  // ---- Slide 10: value — 4 big callouts ----
  s = p.addSlide(); s.background = { color: C.bg }; kicker(s,10); title(s, L.s10t);
  valueCallouts(p, s, L.s10);

  // ---- Slide 11: deliverable — 4 rows ----
  s = p.addSlide(); s.background = { color: C.bg }; kicker(s,11); title(s, L.s11t);
  iconRows(p, s, L.s11.map(([a,b])=>[a,b]), C.blue, true); footer(s, L.s11foot);

  // ---- Slide 12: get started (dark) — 5 steps timeline ----
  s = p.addSlide(); s.background = { color: C.ink };
  s.addText(L.kick[11], { x: M, y: 0.34, w: 8, h: 0.3, fontFace: FF, fontSize: 11, color: C.teal, bold: true, charSpacing: 2, isTextBox: true, margin: 0 });
  s.addText(L.s12t, { x: M, y: 0.75, w: W-2*M, h: 0.9, fontFace: FF, fontSize: 30, bold: true, color: C.white, isTextBox: true, margin: 0 });
  stepsTimeline(p, s, L.s12);
  s.addText(L.tagline, { x: M, y: 6.6, w: W-2*M, h: 0.4, fontFace: FF, fontSize: 15, bold: true, color: C.teal, isTextBox: true, margin: 0 });

  return p.writeFile({ fileName: outFile });
}

// ===== layout components =====
function grid3x2(p, s, items, accent) {
  const cols=3, cw=(W-2*M-2*0.35)/cols, ch=1.85, gx=0.35, gy=0.35, y0=1.75;
  items.slice(0,6).forEach((it,i)=>{ const r=Math.floor(i/cols), c=i%cols; const x=M+c*(cw+gx), y=y0+r*(ch+gy);
    s.addShape(p.ShapeType.roundRect,{x,y,w:cw,h:ch,rectRadius:0.07,fill:{color:"F3F6FA"},line:{color:"DBE3EC",width:1}});
    s.addShape(p.ShapeType.ellipse,{x:x+0.28,y:y+0.28,w:0.16,h:0.16,fill:{color:accent}});
    s.addText(it[0],{x:x+0.58,y:y+0.2,w:cw-0.8,h:0.6,fontFace: FF,fontSize:15,bold:true,color:"0F2A43",isTextBox:true,margin:0,valign:"top"});
    s.addText(it[1],{x:x+0.3,y:y+0.85,w:cw-0.6,h:ch-1.0,fontFace: FF,fontSize:12,color:"5B6B7C",isTextBox:true,margin:0,valign:"top"}); });
}
function grid2x2(p, s, items, accent) {
  const cols=2, cw=(W-2*M-0.4)/cols, ch=1.95, gx=0.4, gy=0.4, y0=1.75;
  items.slice(0,4).forEach((it,i)=>{ const r=Math.floor(i/cols), c=i%cols; const x=M+c*(cw+gx), y=y0+r*(ch+gy);
    s.addShape(p.ShapeType.roundRect,{x,y,w:cw,h:ch,rectRadius:0.07,fill:{color:"F3F6FA"},line:{color:"DBE3EC",width:1}});
    s.addShape(p.ShapeType.ellipse,{x:x+0.3,y:y+0.3,w:0.18,h:0.18,fill:{color:accent}});
    s.addText(it[0],{x:x+0.62,y:y+0.22,w:cw-0.9,h:0.5,fontFace: FF,fontSize:17,bold:true,color:"0F2A43",isTextBox:true,margin:0});
    s.addText(it[1],{x:x+0.32,y:y+0.9,w:cw-0.64,h:ch-1.05,fontFace: FF,fontSize:13,color:"5B6B7C",isTextBox:true,margin:0,valign:"top"}); });
}
function iconRows(p, s, items, accent, tight) {
  const y0=1.8, rh=(5.2-(tight?0.2:0))/items.length;
  items.forEach((it,i)=>{ const y=y0+i*rh;
    s.addShape(p.ShapeType.ellipse,{x:M,y:y+0.06,w:0.44,h:0.44,fill:{color:accent}});
    s.addText(String(i+1),{x:M,y:y+0.05,w:0.44,h:0.44,align:"center",valign:"middle",fontFace: FF,fontSize:15,bold:true,color:"FFFFFF",isTextBox:true,margin:0});
    s.addText(it[0],{x:M+0.65,y:y,w:4.1,h:rh-0.1,fontFace: FF,fontSize:16,bold:true,color:"0F2A43",isTextBox:true,margin:0,valign:"middle"});
    s.addText(it[1],{x:M+4.9,y:y,w:W-M-4.9-M,h:rh-0.1,fontFace: FF,fontSize:13,color:"5B6B7C",isTextBox:true,margin:0,valign:"middle"}); });
}
function domainGrid(p, s, items) {
  const cols=4, cw=(W-2*M-3*0.3)/cols, ch=0.95, gx=0.3, gy=0.3, y0=2.15;
  items.forEach((it,i)=>{ const r=Math.floor(i/cols), c=i%cols; const x=M+c*(cw+gx), y=y0+r*(ch+gy);
    const big = it[1]!=="·";
    s.addShape(p.ShapeType.roundRect,{x,y,w:cw,h:ch,rectRadius:0.08,fill:{color: big?"EAF2FB":"F3F6FA"},line:{color: big?"3F6FD1":"DBE3EC",width: big?1.25:1}});
    s.addText(it[0],{x:x+0.2,y:y+0.14,w:cw-0.4,h:0.4,fontFace: FF,fontSize:14,bold:true,color:"0F2A43",isTextBox:true,margin:0});
    s.addText(it[1]==="·"?"":it[1],{x:x+0.2,y:y+0.5,w:cw-0.4,h:0.38,fontFace: FF,fontSize:17,bold:true,color:"3F6FD1",isTextBox:true,margin:0}); });
}
function instrRows(p, s, items, isCN) {
  const y0=1.8, rh=0.82;
  items.forEach((it,i)=>{ const y=y0+i*rh;
    s.addShape(p.ShapeType.roundRect,{x:M,y:y,w:4.6,h:0.64,rectRadius:0.07,fill:{color:"0F2A43"}});
    s.addText(it[0],{x:M+0.2,y:y,w:4.2,h:0.64,fontFace: FF,fontSize:13.5,bold:true,color:"FFFFFF",isTextBox:true,margin:0,valign:"middle"});
    s.addText("→",{x:M+4.75,y:y,w:0.5,h:0.64,align:"center",valign:"middle",fontFace: FF,fontSize:20,bold:true,color:"1C8C8C",isTextBox:true,margin:0});
    s.addText(it[1],{x:M+5.35,y:y,w:W-M-5.35-M,h:0.64,fontFace: FF,fontSize:13,color:"5B6B7C",isTextBox:true,margin:0,valign:"middle"}); });
}
function bulletsLeft(p, s, arr, w) {
  s.addText(arr.map(t=>({text:t,options:{bullet:{code:"2022"},paraSpaceAfter:12,breakLine:true}})),
    { x: M, y: 1.8, w, h: 4.6, fontFace: FF, fontSize: 15, color: "22384C", isTextBox: true, margin: 0, valign: "top" });
}
function numberedBlocks(p, s, items) {
  const y0=1.75, rh=0.86;
  items.forEach((it,i)=>{ const y=y0+i*rh;
    s.addShape(p.ShapeType.ellipse,{x:M,y:y+0.1,w:0.5,h:0.5,fill:{color:"0F2A43"}});
    s.addText(String(i+1).padStart(2,"0"),{x:M,y:y+0.1,w:0.5,h:0.5,align:"center",valign:"middle",fontFace: FF,fontSize:13,bold:true,color:"1C8C8C",isTextBox:true,margin:0});
    s.addText(it[0],{x:M+0.7,y:y,w:3.1,h:0.7,fontFace: FF,fontSize:15,bold:true,color:"0F2A43",isTextBox:true,margin:0,valign:"middle"});
    s.addText(it[1],{x:M+3.9,y:y,w:W-M-3.9-M,h:0.7,fontFace: FF,fontSize:12.5,color:"5B6B7C",isTextBox:true,margin:0,valign:"middle"}); });
}
function valueCallouts(p, s, items) {
  const cols=2, cw=(W-2*M-0.5)/cols, ch=2.0, gx=0.5, gy=0.4, y0=1.8;
  const cols4=["2BA84A","3F6FD1","1C8C8C","7E57C2"];
  items.slice(0,4).forEach((it,i)=>{ const r=Math.floor(i/cols), c=i%cols; const x=M+c*(cw+gx), y=y0+r*(ch+gy);
    s.addShape(p.ShapeType.roundRect,{x,y,w:cw,h:ch,rectRadius:0.08,fill:{color:"F3F6FA"},line:{color:"DBE3EC",width:1}});
    s.addText(it[0],{x:x+0.35,y:y+0.25,w:cw-0.7,h:0.6,fontFace: FF,fontSize:22,bold:true,color:cols4[i],isTextBox:true,margin:0});
    s.addText(it[1],{x:x+0.35,y:y+0.95,w:cw-0.7,h:ch-1.1,fontFace: FF,fontSize:13,color:"5B6B7C",isTextBox:true,margin:0,valign:"top"}); });
}
function stepsTimeline(p, s, items) {
  const n=items.length, cw=(W-2*M-(n-1)*0.3)/n, y=2.3, ch=3.4, gx=0.3;
  items.forEach((it,i)=>{ const x=M+i*(cw+gx);
    s.addShape(p.ShapeType.roundRect,{x,y,w:cw,h:ch,rectRadius:0.08,fill:{color:"17395A"}});
    s.addText(it[0],{x,y:y+0.3,w:cw,h:0.7,align:"center",fontFace: FF,fontSize:28,bold:true,color:"1C8C8C",isTextBox:true,margin:0});
    s.addText(it[1],{x:x+0.18,y:y+1.15,w:cw-0.36,h:0.9,align:"center",fontFace: FF,fontSize:14,bold:true,color:"FFFFFF",isTextBox:true,margin:0,valign:"top"});
    s.addText(it[2],{x:x+0.2,y:y+2.0,w:cw-0.4,h:ch-2.1,align:"center",fontFace: FF,fontSize:11,color:"CFE0EE",isTextBox:true,margin:0,valign:"top"}); });
}

(async () => {
  await buildDeck(EN, false, "/Users/kky/biomate-review/docs/20261014_BioMate_Platform_Deck_EN.pptx");
  await buildDeck(CN, true, "/Users/kky/biomate-review/docs/20261014_BioMate_Platform_Deck_CN.pptx");
  console.log("built EN + CN");
})();
