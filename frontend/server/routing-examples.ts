/**
 * Classifier-prompt routing examples — the knowledge of the removed post-classifier regex overrides,
 * moved INTO the classifier (docs/20261110_ROUTING_CLASSIFIER_AUTHORITY.md). One line per example:
 * message → type · execution · needsWorkflowGeneration. Each group mixes Chinese and English and
 * includes a boundary case. The held-out replay set (scripts/routing_replay/cases.json) must never
 * reuse these wordings.
 */
export interface RoutingExample { text: string; type: string; execution: 'pipeline' | 'direct_compute' | null; nwg: boolean; constraint?: 'no_workflow' | 'no_launch' }
export interface RoutingExampleGroup { key: string; title: string; replaces: string; examples: RoutingExample[]; flag?: string }

const wf = (text: string, constraint?: 'no_launch'): RoutingExample => ({ text, type: 'workflow_generation', execution: 'pipeline', nwg: true, constraint });
const dc = (text: string, constraint?: 'no_workflow'): RoutingExample => ({ text, type: 'workflow_generation', execution: 'direct_compute', nwg: false, constraint });
const no = (text: string, type = 'research_question', constraint?: 'no_workflow'): RoutingExample => ({ text, type, execution: null, nwg: false, constraint });

export const ROUTING_EXAMPLE_GROUPS: RoutingExampleGroup[] = [
  { key: 'direct_compute', title: 'Ad-hoc computation on data already in the conversation / explicit "no workflow"', replaces: '_isDirectCodeExecutionQuery, isAdhocAnalysisOfAttachedData, isSimpleSequencePropertyRequest, inline-table short-circuit, parseActions mustGenerateWorkflow', examples: [
    dc('"按第3步继续" (an earlier turn attached sales_table.csv and you proposed numbered analysis steps)'),
    dc('"别建流程了，写段代码直接把每个类别的数量数出来" (table attached earlier)', 'no_workflow'),
    dc('"Execute steps 1–3 of that plan and save the outputs as files I can download" (table attached in an earlier turn)'),
    dc('"Just do it in Python — mean and SD per group, no pipeline" + attached xlsx', 'no_workflow'),
    dc('"把这个表按年份汇总并画柱状图" + attached CSV'),
    dc('"Translate this ORF and report the protein length: ATGAAACGCATTAGCACC"'),
    dc('A pasted 4-gene × 4-sample count table + "DESeq2 this" (tiny inline table — a pipeline needs files)'),
    wf('"Run nf-core/sarek germline calling on the BAMs I uploaded" (named pipeline + raw inputs)'),
    no('"How would I compute a fold change in R?"', 'teaching_explanation'),
  ] },
  { key: 'ml_training', flag: 'ML_TRAINING_ROUTING', title: 'Model training (ml_training card)', replaces: 'ml_training intent override', examples: [
    wf('"Train an XGBoost classifier on my attached assay table to predict active vs inactive"'),
    wf('"用这批分子的 pIC50 数据训练一个回归模型"'),
    wf('"Fine-tune a protein language model on my labelled sequences"'),
    no('"什么情况下应该用 GNN 而不是随机森林？"'),
  ] },
  { key: 'target_evidence', title: 'Target evidence / genetic association for a named target (target_evidence_positioning)', replaces: 'Target-evidence override', examples: [
    wf('"Assemble genetic and tractability evidence for IL23R as a Crohn\'s target"'),
    wf('"评估 CD40 作为系统性红斑狼疮靶点的证据强度"'),
    wf('"Rank BAFF, APRIL and CD19 by target evidence in myasthenia gravis"'),
    no('"什么是靶点可成药性（tractability）？"'),
  ] },
  { key: 'trial_feasibility', title: 'Trial recruitment feasibility / power (patient_recruitment_feasibility, rare_disease_power_calculator)', replaces: 'Trial-feasibility override', examples: [
    wf('"Project patient accrual for a 120-patient phase 2 lupus nephritis trial at 25 sites"'),
    wf('"这个罕见病三期试验每组需要多少例？主要终点下降30%，标准差20%"'),
    wf('"Power calculation for a phase 2 ALS trial, ALSFRS-R slope difference 0.3 points/month"'),
    no('"What usually drives slow enrollment in rare-disease trials?"'),
  ] },
  { key: 'pathway_enrichment', title: 'Pathway / GO / KEGG enrichment on a gene list (clusterProfiler workflows, not a run_code script)', replaces: 'Pathway-enrichment override, _isClusterProfilerQuery', examples: [
    wf('"Run Reactome over-representation on the genes in column symbol of my DEG file"'),
    wf('"用 clusterProfiler 对这些基因做 GO 富集：IL6, CXCL8, CCL2, IL1B"'),
    wf('"GSEA on my ranked fold-change list against the Hallmark sets"'),
    no('"为什么富集分析需要多重检验校正？"'),
  ] },
  { key: 'gwas_chain', title: 'GWAS → eQTL → cell-type evidence chain (gwas_scrna_eqtl_target_chain)', replaces: 'GWAS→eQTL chain override', examples: [
    wf('"Trace IL7R\'s genetic signal through GWAS, eQTL colocalization and cell-type expression across MS and T1D"'),
    wf('"看看 CTLA4 位点的 GWAS 关联和 eQTL 是否共定位"'),
    wf('"Indication expansion for TYK2 — pull GWAS evidence across autoimmune diseases"'),
    no('"How is colocalization different from Mendelian randomization?"'),
  ] },
  { key: 'multi_omics', title: 'Integration of two or more omics layers (multi-omics integration workflows)', replaces: 'Multi-omics override', examples: [
    wf('"Combine my proteomics intensity table with the matched RNA-seq counts and find concordant changes"'),
    wf('"整合 ATAC-seq 峰和 RNA 表达数据，找调控关系"'),
    wf('"MOFA2 on methylation beta values plus expression from the same cohort"'),
    no('"多组学整合有哪些常见方法？"'),
  ] },
  { key: 'macrophage', title: 'Macrophage state / polarization / metabolism in the user\'s scRNA-seq (macrophage_metabolic_state_scrna)', replaces: 'Macrophage metabolic override', examples: [
    wf('"Score glycolysis vs OXPHOS in the macrophage clusters of my synovium scRNA-seq"'),
    wf('"在我的肿瘤单细胞数据里区分 M1/M2 样巨噬细胞亚群"'),
    wf('"Trajectory of the monocyte-to-macrophage transition in my sciatic nerve 10x data"'),
    no('"TREM2 在巨噬细胞中的功能是什么？"'),
  ] },
  { key: 'canonical_fixture', title: 'Built-in example datasets (airway, pasilla, pbmc3k…) are resolved inputs', replaces: 'Canonical-fixture override', examples: [
    wf('"Run the airway example: dexamethasone vs control differential expression"'),
    wf('"用 pasilla 示例数据跑一下差异表达"'),
    wf('"Cluster the PBMC 3k demo set and annotate cell types"'),
    no('"pbmc3k 数据集是从哪里来的？"'),
  ] },
  { key: 'named_docking', title: 'Site-directed docking with AutoDock Vina (docking_autodock_vina)', replaces: 'Named docking tool override (single + multi-intent), named decomposition override', examples: [
    wf('"Dock the attached ligands into the hinge-binding site of EGFR (PDB 4HJO) with Vina, box centred on Met793"'),
    wf('"用 Vina 对 5R82 的蛋白酶口袋做定点对接"'),
    wf('"Site-directed docking of my SDF library against the BRD4 acetyl-lysine pocket"'),
    no('"Vina 和 Glide 的打分函数有什么区别？"'),
  ] },
  { key: 'epitope_codon_pocket', title: 'Epitope prediction, codon optimization, pocket detection (named workflows)', replaces: 'Plan A epitope / Plan B codon / pocket-detection overrides (single + multi-intent + decomposition)', examples: [
    wf('"Run epitope prediction (MHCnuggets) on this antigen FASTA for HLA-A*02:01"'),
    wf('"对这段序列做大肠杆菌密码子优化"'),
    wf('"Detect pockets and score druggability on my uploaded receptor PDB"'),
    wf('"对 4DKL 结构做口袋检测和成药性打分"'),
    no('"How is druggability estimated from pocket geometry?"'),
  ] },
  { key: 'admet', title: 'ADMET / toxicity prediction for given molecules (predict_admet_properties)', replaces: 'ADMET screening override (single + multi-intent)', examples: [
    wf('"Check Ames mutagenicity and BBB penetration for c1ccc(cc1)C(=O)N"'),
    wf('"这几个分子的 hERG 风险如何：CCN(CC)CCOC(=O)c1ccc(N)cc1"'),
    wf('A follow-up turn that only pastes SMILES after an earlier turn set the goal "profile ADMET liabilities"'),
    no('"为什么 hERG 抑制会导致 QT 间期延长？"'),
  ] },
  { key: 'hpo_ensg', title: 'Phenotype codes + candidate gene IDs → causal-gene reasoning (no pipeline)', replaces: 'HPO+ENSG override', examples: [
    no('"表型 HP:0002066、HP:0001251；候选 ENSG00000105974、ENSG00000141510，哪个是致病基因？"', 'clinical_genomics'),
    no('"Given HP:0000365 and HP:0001263, which of ENSG00000134982 / ENSG00000171862 is causal?"', 'clinical_genomics'),
    no('"Which candidate best explains ataxia + hearing loss: ENSG00000105974, ENSG00000196712?"', 'clinical_genomics'),
  ] },
  { key: 'paper_question', title: 'Questions about an attached paper vs reproducing it', replaces: 'Paper-question guard', examples: [
    no('"用一段话概括这篇文章" + [Attached files: x.pdf]'),
    no('"What sample sizes did they use?" + [Attached files: methods.pdf]'),
    wf('"Apply their variant-calling pipeline to my BAMs" + [Attached files: study.pdf]'),
  ] },
  { key: 'data_attach', title: 'Adding/attaching files is dataset management, not analysis', replaces: 'Data-attach guard', examples: [
    no('"把剩下的文件也附上"', 'dataset_inquiry'),
    no('"Also include sample_C.csv and sample_D.csv"', 'dataset_inquiry'),
    wf('"Attach the other runs and align them all with STAR"'),
  ] },
  { key: 'user_constraint', title: 'Explicit user constraints → "user_constraint"', replaces: 'Execution-prohibition guard (kept as a gate; now consumes user_constraint)', examples: [
    no('"只做解读，不要跑模拟：AUC 120 mg·h/L，Cmax 8 mg/L"', 'data_interpretation', 'no_workflow'),
    wf('"Draft the ChIP-seq workflow for these FASTQs but hold off on launching"', 'no_launch'),
    dc('"不用工作流，直接写代码算每组均值" (data attached)', 'no_workflow'),
  ] },
];

export function routingExamplesPrompt(env: Record<string, string | undefined> = process.env): string {
  const groups = ROUTING_EXAMPLE_GROUPS.filter(g => !g.flag || env[g.flag] === '1');
  const fmt = (e: RoutingExample) =>
    `- ${e.text} → ${e.type} · execution=${e.execution ?? 'null'} · needsWorkflowGeneration=${e.nwg}${e.constraint ? ` · user_constraint=${e.constraint}` : ''}`;
  return `## Routing examples by domain (decide by what the request NEEDS, in any language)

You are the only component that decides workflow vs direct computation vs answer — nothing downstream
re-decides it, so classify these patterns yourself. Consistency rule: execution=direct_compute ⇒
needsWorkflowGeneration=false; a knowledge/explanation question about a domain ⇒ no execution at all.

${groups.map(g => `**${g.title}**\n${g.examples.map(fmt).join('\n')}`).join('\n\n')}
`;
}
