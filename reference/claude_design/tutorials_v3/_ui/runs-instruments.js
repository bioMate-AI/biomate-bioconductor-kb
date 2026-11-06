/* Instrument tutorials on the one screen kit. Flow cytometry first. Load after runs-more.js and runs-zh-more.js. */
(function(){const U=window.BMUI,F=U.fd;U.findings=U.findings||{};
const X={};const T=(en,zh)=>{X[en]=zh;return en};
const ids=[['lym',T('Lymphocytes','淋巴细胞'),'62',T('Singlets','单个细胞')],['cd3',T('CD3+ T cells','CD3+ T 细胞'),'71',T('Lymphocytes','淋巴细胞')],['cd4',T('CD4+ T cells','CD4+ T 细胞'),'43',T('CD3+ T cells','CD3+ T 细胞')],['cd8',T('CD8+ T cells','CD8+ T 细胞'),'29',T('CD3+ T cells','CD3+ T 细胞')]];
const recs=F.table([{key:'pct',name:T('% of parent','占上级群体的 %'),units:'%',order:1},{key:'parent',name:T('Parent gate','上级门'),order:2}],ids.map(r=>[r[0],r[2],r[3]]),'gate');
const fd={status:'ready',entityType:'sample',
 summary:T('<b>Lymphocytes are 62% of singlets; 71% of those are CD3+ T cells, which split into CD4+ 43% and CD8+ 29%.</b> Every percentage is of the gate directly above it.','<b>淋巴细胞占单个细胞的 62%；其中 71% 是 CD3+ T 细胞，再分为 CD4+ 43% 和 CD8+ 29%。</b>每个百分比都是相对于其上一级门而言的。'),
 scopeLine:T('4 populations · threshold gating from your strategy · one .fcs file','4 个细胞群 · 按你提供的策略做阈值门控 · 一个 .fcs 文件'),
 entityRoster:ids.map(r=>F.E(r[0],r[1],'','','output_column')),records:recs,
 provenance:{gate:U.PROV('gate','population_percentages.csv','Count and report','threshold gating','Table','row by population')},citations:[],
 caveats:[T('Gating is threshold-based from the strategy you supply, and the compensation matrix is yours. Unsupervised clustering is not part of this workflow.','门控是根据你提供的策略做阈值划分，补偿矩阵也由你提供；无监督聚类不属于这个工作流。'),T('Check the first run against your own manual analysis before relying on it.','首次运行请先与你自己的手动分析对照，再依赖结果。')]};
const tb=U.tbl;
U.mkRun({id:'flow',runId:'tutorial-flow',project:T('Immunology · T-cell panel','免疫学 · T 细胞检测组合'),title:T('Flow cytometry immunophenotyping','流式细胞免疫表型分析'),method:T('Analyze Flow Cytometry Immunophenotyping · 1 phase','流式细胞免疫表型分析 · 1 个阶段'),fd,
 user:{text:T('Immunophenotype this FCS file: gate lymphocytes on FSC and SSC, then CD3+ T cells, then CD4 against CD8, and report the population percentages.','对这个 FCS 文件做免疫表型分析：先按 FSC 和 SSC 圈出淋巴细胞，再圈出 CD3+ T 细胞，然后区分 CD4 和 CD8，并报告各细胞群的百分比。')},
 plan:T('Plan — remove debris and doublets, gate the lineages from your strategy using your compensation matrix, then count each population against its parent. Review the settings and confirm.','计划——去除碎片和粘连细胞，按你的门控策略并结合你的补偿矩阵划分细胞谱系，再统计每个细胞群占上级群体的比例。请检查设置后确认。'),
 updates:[[1,T('Debris and doublets removed.','已去除碎片和粘连细胞。')],[2,T('Lineages gated.','已划分细胞谱系。')],[3,T('Populations counted and the report saved.','已统计各细胞群并保存报告。')]],runningAt:2,
 inputsAside:T('1 file + strategy + matrix','1 个文件 + 策略 + 矩阵'),
 inputs:[{file:'sample.fcs',meta:T('events · FSC, SSC and marker channels','事件 · FSC、SSC 与标志物通道'),origin:'from your message',checks:[[T('File parsed','文件已解析'),'sample.fcs','pass'],[T('Channels found','找到的通道'),'FSC-A · SSC-A · CD3 · CD4 · CD8','pass']]},
  {file:'gating_strategy',meta:T('4 gates · pre-filled, edit to your panel','4 个门 · 已预填，请按你的检测组合修改'),origin:'recommended',checks:[[T('Channel names match the file','通道名称与文件一致'),'4 / 4','pass']]},
  {file:'compensation_matrix',meta:T('required · from your single-stain controls','必填 · 来自你的单染对照'),origin:'from your file',checks:[[T('Matrix supplied','已提供矩阵'),T('required','必填'),'pass']]}],
 params:[['fcs_file_path','sample.fcs','from your message'],['gating_strategy',T('4 gates: FSC/SSC → CD3 → CD4 and CD8','4 个门：FSC/SSC → CD3 → CD4 与 CD8'),'recommended',1],['compensation_matrix',T('from single-stain controls','来自单染对照'),'from your file']],
 phases:[{letter:'A',name:T('Gating','门控'),steps:[{name:T('Remove debris and doublets','去除碎片和粘连细胞'),tool:T('threshold gating','阈值门控')},{name:T('Gate lineages by marker','按标志物划分谱系'),tool:T('threshold gating','阈值门控'),params:[['compensation','applied','from your file']],live:T('gate 2 of 4','第 2 个门，共 4 个')},{name:T('Count and report','统计并报告'),tool:T('threshold gating','阈值门控')}],qc:{aside:T('gate check','门控检查'),rows:[[T('Lymphocyte gate keeps most events','淋巴细胞门保留了大多数事件'),T('most of the singlets','大部分单个细胞'),{o:'pass'},'finding']]}}],
 outputs:[{name:'population_percentages.csv',type:'Table',size:'—',step:T('Step 3 · Count and report','第 3 步 · 统计并报告'),preview:[tb([['c','Population','entity'],['p','% of parent','mono'],['g','Parent gate']],ids.map(r=>[r[1],r[2]+' %',r[3]]))]},{name:'versions.yml',type:'Log',size:'—',step:T('Run · execution','运行 · 执行')}],
 methodShort:T('Threshold gating from the strategy you supply, using the compensation matrix you supply.','按你提供的策略做阈值门控，并使用你提供的补偿矩阵。'),software:T('biomni_local runtime — version not recorded','biomni_local 运行环境 — 未记录版本'),trajectory:T('routed → inputs resolved → gating → count and report → outputs saved','已路由 → 输入已确认 → 门控 → 统计并报告 → 输出已保存'),
 reportFile:'immunophenotyping_report.md',reportTitle:T('Immunophenotyping — T-cell panel','免疫表型分析 — T 细胞检测组合'),answer:T('Lymphocytes are 62% of singlets. Of those, 71% are CD3+ T cells, and the T cells split into CD4+ 43% and CD8+ 29%. Each percentage is of its parent gate.','淋巴细胞占单个细胞的 62%；其中 71% 是 CD3+ T 细胞，T 细胞再分为 CD4+ 43% 和 CD8+ 29%。每个百分比都相对于其上一级门。'),
 data:[tb([['f','File','mono'],['r','Role'],['n','Entries','mono']],[['sample.fcs',T('events to gate','待门控的事件'),'1'],['gating_strategy',T('population definitions','细胞群定义'),'4'],['compensation_matrix',T('spillover correction','荧光溢出校正'),'1']])],
 methodText:T('Debris and doublets were removed, then lineages were gated from the supplied strategy using the supplied compensation matrix. Each population is reported as a percentage of its parent gate.','先去除碎片和粘连细胞，再按所提供的策略并结合所提供的补偿矩阵划分谱系。每个细胞群以占其上级门的百分比报告。'),caveats:fd.caveats,citations:[]});
{const f=U.runs.flow.outputs.find(o=>o.preview&&o.preview[0]&&o.preview[0].k==='table');if(f&&!f.preview[0].region)f.preview[0].region='pv-t';}
Object.assign(X,{'Population':'细胞群','compensation':'补偿','applied':'已应用'});
if(U.regZh)U.regZh('flow',Object.assign({},U.ZHC||{},X));
})();
