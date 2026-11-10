// Recommended ADDITIONAL screenshots (design layer — the markdown is not edited).
// Each entry is inserted as a "Screenshot to be captured" placeholder after the first block under the h2 with that 1-based ordinal.
// id: stable slot id → expected file assets/<id>.png. cand: an existing asset that may already fit (verify before using).
window.MANUAL_SHOTS = {
 "overview/03-first-analysis-5min":[
  {h2:3,id:"O03-A1",en:"The workflow card in chat and the pre-run panel — parameters filled in, Confirm & Run.",zh:"对话中的工作流卡片与运行前面板——参数已填好，以及 Confirm & Run 按钮。",spec:"route=/ ; state=proposal card + run panel pre-run ; focus=workflow-panel",cand:"r1-prerun-param-strip.png"},
  {h2:4,id:"O03-A2",en:"A run in progress — phase cards with live status.",zh:"运行进行中——各阶段卡片显示实时状态。",spec:"route=/ ; state=run RUNNING ; focus=phase cards",cand:"r2-running.png"},
  {h2:5,id:"O03-A3",en:"The after-run report — Results tab with findings.",zh:"运行后报告——Results 标签页及主要发现。",spec:"route=/ ; state=run COMPLETED ; focus=AfterRunReport Results tab",cand:"t3-2-after-run-summary.png"}],
 "modules/I02-composer-talking-to-biomate":[
  {h2:2,id:"I02-A1",en:"The composer — paperclip, Database icon, Instructions, Experts and the lane chip.",zh:"消息框——回形针、数据库图标、Instructions、Experts 与通道标签。",spec:"route=/ ; state=empty chat, composer focused ; focus=chat-input toolbar",cand:"t11-1-composer-goal.png"},
  {h2:3,id:"I02-A2",en:"The dataset browser opened from the Database icon (This session / Project / History / URL).",zh:"从数据库图标打开的数据集浏览器（本次会话 / 项目 / 历史 / URL）。",spec:"route=/ ; state=GalaxyDatasetBrowser open ; focus=dataset browser tabs",cand:""}],
 "modules/I03-search-and-evidence":[
  {h2:2,id:"I03-A1",en:"The Search & evidence card on the cold start with its four tracks.",zh:"起始页上的「检索与证据」卡片及其四个方向。",spec:"route=/ ; state=cold start ; focus=COLD_MODULES[0] card",cand:"m1-1-search-module.png"},
  {h2:5,id:"I03-A2",en:"A cited answer — numbered markers, the source list with open ▸, and the boundary block.",zh:"一个带引用的回答——编号标记、带 open ▸ 的来源列表，以及边界说明。",spec:"route=/ ; state=research answer rendered ; focus=CitationPanel + boundary",cand:""},
  {h2:5,id:"I03-A3",en:"The source reader pane with next / previous navigation.",zh:"来源阅读面板，可前后切换。",spec:"route=/ ; state=SourceReaderPane open ; focus=reader pane",cand:""}],
 "modules/I04-projects-instructions-collaboration":[
  {h2:4,id:"I04-A1",en:"Standing instructions and Notes side by side on the project page.",zh:"项目页上并列的常驻指令与笔记。",spec:"route=/projects/:id ; focus=instructions + notes",cand:"t7-1-standing-instructions.png"},
  {h2:6,id:"I04-A2",en:"Members and roles — Owner, Editor, Viewer.",zh:"成员与角色——Owner、Editor、Viewer。",spec:"route=/projects/:id ; focus=members card",cand:"t7-2-members-roles.png"}],
 "modules/I06-running-an-analysis":[
  {h2:3,id:"I06-A1",en:"The run panel before Confirm & Run.",zh:"点击 Confirm & Run 之前的运行面板。",spec:"route=/ ; state=pre-run ; focus=nextflow-workflow-viewer",cand:"r1-prerun-param-strip.png"},
  {h2:5,id:"I06-A2",en:"Live progress — phase cards and QC gates while running.",zh:"实时进度——运行中的阶段卡片与 QC 关卡。",spec:"route=/ ; state=RUNNING ; focus=phase cards data-status",cand:"r2b-running-metrics.png"},
  {h2:6,id:"I06-A3",en:"A completed run with the after-run report in the panel.",zh:"已完成的运行及面板中的运行后报告。",spec:"route=/ ; state=COMPLETED ; focus=AfterRunReport",cand:"r8-completed-chat-and-panel.png"}],
 "modules/I14-instruments-and-lab-connectivity":[
  {h2:2,id:"I14-A1",en:"The Instruments tab in Connectors, with a registered instrument.",zh:"连接器中的 Instruments 标签页，含一台已注册的仪器。",spec:"route=/ ; state=Connectors → Instruments ; focus=instrument list",cand:"t6-1-instruments-tab.png"}],
 "data/II01-workflow-catalog-and-routing":[
  {h2:4,id:"II01-A1",en:"The disambiguation card when a request matches more than one workflow.",zh:"一个请求匹配多个工作流时出现的消歧卡片。",spec:"route=/ ; state=ambiguous request ; focus=disambiguation card",cand:""}],
 "data/II02-public-datasets-accession-resolver":[
  {h2:5,id:"II02-A1",en:"An accession resolved into a run — GEO/SRA id in the request, fetch step in the pre-run panel.",zh:"登录号被解析为一次运行——请求中的 GEO/SRA 编号，以及运行前面板中的获取步骤。",spec:"route=/ ; state=GEO accession request → pre-run ; focus=param strip + fetch step",cand:""}],
 "appendix/C-qc-gate-reference":[
  {h2:10,id:"AppC-A1",en:"A QC gate row in a report — metric, threshold, verdict (PASS / ADVISORY / HALT).",zh:"报告中的一行 QC 关卡——指标、阈值与判定（PASS / ADVISORY / HALT）。",spec:"route=/ ; state=COMPLETED run with gates ; focus=QC gate list",cand:""}],
 "tutorials/instruments/microscopy-pathology-imaging":[
  {h2:5,id:"microscopy-pathology-imaging-A1",en:"Segmentation output — mask overlay and per-cell measurement table.",zh:"分割输出——掩膜叠加图与逐细胞测量表。",spec:"route=/ ; state=COMPLETED imaging run ; focus=Outputs",cand:""}],
 "tutorials/instruments/sample-qc-instruments":[
  {h2:4,id:"sample-qc-instruments-A1",en:"A sample-QC verdict (Good / Watch / Blocked) on an uploaded instrument export.",zh:"上传的仪器导出文件上的样本质控判定（Good / Watch / Blocked）。",spec:"route=/files ; state=QC export uploaded ; focus=dataset header quality pill",cand:"i05-2-dataset-header.png"}]
};
// Domains: one pre-run card under "Tools & workflows behind this" (h2 4) and one output viewer under "Outputs & visualization" (h2 7).
[["drug-discovery-ind","Drug discovery → IND","药物发现 → IND","ADMET screen","IND workspace (5 steps) with the assembled sections",""],
 ["transcriptomics","Transcriptomics","转录组学","bulk_rnaseq_de_analysis","volcano plot + DE table viewer","rnaseq-results.png"],
 ["cryo-em","Cryo-EM","冷冻电镜","cryosparc_standard_spa","FSC curve + map viewer","domain-cryo-em-prerun.png"],
 ["single-cell","Single-cell","单细胞","scrnaseq_standard_endtoend","UMAP / cluster / marker panel","domain-single-cell-prerun.png"],
 ["variant-calling","Variant calling","变异检测","sarek germline","VCF viewer + annotation table","domain-variant-calling-prerun.png"],
 ["structural-biology","Structural biology","结构生物学","Boltz-2 / docking","3Dmol structure + pLDDT chart","domain-structural-biology-prerun.png"],
 ["pharmacology-clinical","Pharmacology & clinical","药理与临床","NCA (PKNCA)","concentration–time curve + NCA table",""],
 ["multi-omics","Multi-omics","多组学","MOFA2","factor plot + variance explained",""],
 ["epigenomics","Epigenomics","表观基因组学","ChIPseeker → clusterProfiler","peak annotation + enrichment","domain-epigenomics-prerun.png"],
 ["proteomics","Proteomics","蛋白质组学","MSnbase → limma","differential-abundance table + volcano","domain-proteomics-prerun.png"],
 ["metabolomics","Metabolomics","代谢组学","xcms → CAMERA → biosigner","feature table + signature plot","domain-metabolomics-prerun.png"],
 ["metagenomics","Metagenomics","宏基因组学","CONCOCT → MMseqs2 → PathoStat","taxonomic profile / bins",""],
 ["cro-regulatory","CRO & regulatory","CRO 与法规","CRO campaign","exported regulatory document",""]].forEach(([k,en,zh,wf,out,cand])=>{
 window.MANUAL_SHOTS["domains/"+k]=[
  {h2:4,id:k+"-A1",en:en+" — the pre-run workflow card ("+wf+") with its parameters.",zh:zh+"——运行前的工作流卡片（"+wf+"）及其参数。",spec:"route=/ ; state=pre-run "+wf+" ; focus=workflow-panel param strip",cand:cand&&/prerun/.test(cand)?cand:""},
  {h2:7,id:k+"-A2",en:en+" — the in-app output viewer: "+out+".",zh:zh+"——应用内输出查看器："+out+"。",spec:"route=/ ; state=COMPLETED "+wf+" run ; focus=StepOutputPreview",cand:cand&&!/prerun/.test(cand)?cand:""}];});
window.shotCode=function(r){const b=r.split("/").pop();let m;
 if(r.startsWith("overview/")&&(m=b.match(/^(\d\d)-/)))return "O"+m[1];
 if(r.startsWith("appendix/"))return "App"+b[0];
 if(m=b.match(/^(T\d+|M\d|S\d|W\d|I\d+|II\d+)-/))return m[1];
 return b;};
