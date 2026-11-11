// Reader-facing sanitizer: removes engineering references from manual prose — source files + line numbers,
// API endpoints, code identifiers (components, functions, DB fields, constants), catalog DB ids, verification tiers.
// mode "para": a sentence that still carries an engineering ref after paren/clause removal is dropped.
// mode "cell"/"head": the reference is removed in place (no sentence drop).
(function(){
const FILE=/^[\w./@*{}-]*\.(py|tsx?|jsx?|nf|ya?ml|json|md|R|sh|sql|toml|cfg)(:[\d,\- ]+)?$/i;
const UI=/^[A-Z][A-Za-z0-9]*(Panel|Display|Card|Pane|Tab|Tabs|Row|Modal|Selector|Browser|Report|Preview|Detail|Viewer|Dialog|Badge|Button|Grid|Banner|Strip|Summary|Client|Agent|Assembler|Evaluator|Monitor|Tuner|Orchestrator|Store|Router|Section|Steps|Generate|Launcher|Chip|Bar|List|Heatmap|Interface|Dashboard|Toggle|Form|Header|Hook|Provider|Context|Executor|Service|Reader|Parser|Bridge|Planner|Composer|Registry|Enforcer|Manifest|Response|Message|Input|Tree|Object|Hub|Pill|Dot|Chart|Detail|Item|Strip|Route|Sidebar|Artifacts|Tracks|Scatter|Note|View|Pipeline|Request|Fact|Evidence|Result|Results|Loop|Step)\d*$/;
const WORDS=new Set(["user_notes","notes_synthesis","project_instruction","project_knowledge","workflow_chains","workflows","knowledgeType","formatted_bibtex","formatted_apa","retrieval_date","corpus_version","locus","stub_reason","source_id","source_file","run_id","research_goal","available:false","available: false","unverified=True","stub: true","property_envelope","instrument_events","not_implemented","connections","description","title","query","research_question","workflow_generation","search_workflow","browse_data","fetch_public_data","run_workflow","resolve_accession","recall_memory","get_workflow_spec","list_instruments","Citation","cloud","instant",'"instant"','"cloud"',"localStorage","boundary","retrieval","conflicts","relevance_score","citations_json","ad_status","passed","action","result","response.boundary","benchmark_evidence","mock_mode","workflow_id","invocation_id","profile.quality","dataset.versions","Number.isFinite","inputs","params","params_template","galaxy_ai_tools.db","qc_evidence","x-e2e-test-token","summary.json","sidecar","research_query","abstract","found","kept","stub","sse","SSE"]);
const OUTEXT=/\.(csv|tsv|png|pdf|html|h5ad|mrc|vcf|txt|bam|gz|fastq|fq|rds|pdb|pdbqt|cif|xlsx|docx|zip|fcs|ab1|raw|mzml|d|sdf|smi|mol2|bed|gtf|gff|fasta|fa|tif|tiff|svs|ndpi|h5|loom|cram)$/i;
function isEng(s){s=s.trim();
 if(FILE.test(s)||/\.(py|tsx?|jsx?|nf)\b/.test(s))return true;
 if(/^\d+(-\d+)?(\s*,\s*\d+(-\d+)?)*$/.test(s))return true;
 if(/\/api\/|^(GET|POST|PUT|PATCH|DELETE)\b/.test(s))return true;
 if(/^_\w+|^\w[\w.]*\(.*\)$/.test(s))return true;
 if(/^[a-z][a-z0-9]*([A-Z][a-z0-9]*)+(\.\w+)*$/.test(s))return true;
 if(UI.test(s))return true;
 if(/^(docs|backend|frontend|reference|evaluation|scripts|lib|src|client|server)\//.test(s))return true;
 if(/^(None|null|undefined|true|false|True|False|\[\]|\{\}|"")$|[=:]\s*(true|false|True|False|None|null)$/.test(s))return true;
 if(/^<[\w_]+>$|^\?[\w=&]+$|^s3:\/\//.test(s))return true;
 if(/^[A-Z][A-Z0-9_]{3,}(\[\d+\])?(\.\w+)?$/.test(s)&&s.includes("_"))return true;
 if(/^\w+(_\w+)*\.\w+$/.test(s)&&!OUTEXT.test(s)&&!/^\d/.test(s))return true;
 if(/^:\d|^\.trackbar$/.test(s))return true;
 if(/^\?|<[a-z]+[A-Z]\w*>|^[a-z]+[A-Z]\w*\s*:|^\w+\s*:\s*["'\w]+\s*(\|\||&&)/.test(s))return true;
 if(/^\w+\s*:\s*"[^"]*"$/.test(s))return true;
 return WORDS.has(s);}
const M="\u0007";
const SENT=/(?<=[.!?](?:\*\*|\*|_)?[)”"]?)\s+(?=[A-Z0-9*_"“(`\[])|(?<=[。！？](?:\*\*)?)/;
function clean(s,mode){
 if(!s)return s;const orig=s.trim();
 // wrap bare file refs so they are classified like code spans
 s=s.replace(/(^|[\s(（,;；*])((?:[\w.-]+\/)*[\w.-]+\.(?:py|tsx?|jsx?|nf|ya?ml|md(?=:\d))(?::\d[\d,\-]*)?)(?=[\s),.;）；，*]|$)/g,"$1`$2`");
 s=s.replace(/(?<![\w`])(onSeed|onAdjustAndRerun|onOpenFullStepView|setDraft)(?![\w`])/g,"`$1`");
 s=s.replace(/\s*\(dev\)|\s+(?:on|from|against) (?:the )?(?:live )?dev\b(?: environment)?/gi,"");
 s=s.replace(/`([^`]+)`/g,(m,c)=>isEng(c)?M:m);
 s=s.replace(BARE,M).replace(/\(\s*:\d[\d,\- ]*\)/g,"");
 s=s.replace(new RegExp(M+"(?:\\s*[,;+&]\\s*(?:"+M+"|`?\\d[\\d,\\- ]*`?(?=[\\s),;])))+","g"),M);
 // catalog / DB ids and verification tiers
 s=s.replace(/\s*\b(?:DB\s+)?ids?\s+\**\d{3,}\**(?:\s*[\/,]\s*\**\d{3,}\**)*/g,"");
 s=s.replace(/\s*\((?:C|L|C ?\+ ?L|C\/L|C \(spec\)|tier [CL][^)]*)\)/g,"").replace(/\btier [CL]\b,?\s*/gi,"");
 // any parenthetical carrying an engineering ref goes entirely
 for(let k=0;k<4;k++)s=s.replace(/\s*[(（]([^()（）]*)[)）]/g,(m,inner)=>inner.includes(M)?"":m);
 // trailing clause "— file.py:12" / "; see X"
 s=s.replace(new RegExp("\\s*(?:—|--|–|;)\\s*(?:see\\s+|in\\s+|via\\s+|at\\s+)?"+M+"[\\s"+M+",;]*(?=[.;。]|$)","g"),"");
 if(s.includes(M)){
  if(mode==="para")s=s.split(SENT).filter(p=>!p.includes(M)).join(" ");
  else s=s.replace(new RegExp("\\s*(?:at|in|via|from|see|by|=|→|->)?\\s*"+M+"\\s*(?:→|->)?","g")," ");
 }
 s=s.replace(/\(\s*[,;]?\s*\)/g,"").replace(/\s+([,.;:。，；])/g,"$1").replace(/([,;])\s*([.;])/g,"$2").replace(/^[,;:\s]+|[,;:]\s*$/g,"").replace(/ {2,}/g," ").replace(/\(\s+/g,"(").replace(/\s+\)/g,")").replace(/:\s*\./g,".").trim();
 if(mode==="para"&&s!==orig&&/^\*\*[^*]+\*\*[.:。：]?$/.test(s))return "";
 if(mode==="cell"&&/^[\s,;:.\-–—/]*$/.test(s))return "";
 if(mode==="cell"&&s!==orig&&!/[\u4e00-\u9fff]/.test(s)&&s.replace(/[^\w\s]/g," ").trim().split(/\s+/).length<2)return "";
 return s.replace(/^[\/·→]\s*/,"");}
const BARE=new RegExp("(?<![\\w`])("+[...WORDS].filter(w=>/_/.test(w)&&/^[\w.]+$/.test(w)).join("|")+")(?![\\w`])","g");
window.mdClean=clean;window.mdIsEng=isEng;
})();
