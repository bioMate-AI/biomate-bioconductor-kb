/** Real published npm MCP journey. No mocked responses; no recording on failure. */
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {createServer} from 'node:http';
import {createConnectorRunTools} from '../frontend/server/connector-run-tools';
import {FIXTURE_EMAIL,FIXTURE_PASSWORD,E2E_TOKEN} from '../frontend/e2e/_fixture-login';
async function main(){
 const root=process.cwd(), pkg=process.env.CONNECTOR_TEST_PREFIX || '/private/tmp/biomate-connector-20261009';
 const base=process.env.BIOMATE_URL || 'https://dev-public.biomate.ai';
 const out=path.resolve(root,process.env.CONNECTOR_PROOF_DIRECTORY || 'docs/qa/20261009-connector-workflows');fs.mkdirSync(out,{recursive:true});
 const {Client}=await import(pathToFileURL(path.join(pkg,'node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js')).href);
 const {StdioClientTransport}=await import(pathToFileURL(path.join(pkg,'node_modules/@modelcontextprotocol/sdk/dist/esm/client/stdio.js')).href);
 const entry=path.join(pkg,'node_modules/@biomate/mcp-server/dist/index.js');
 const previous=process.env.CONNECTOR_RUN_ID&&fs.existsSync(path.join(out,'npm-workflow-proof.json'))?JSON.parse(fs.readFileSync(path.join(out,'npm-workflow-proof.json'),'utf8')):null;
 const report:any={date:new Date().toISOString(),base,package:'@biomate/mcp-server@0.1.0',entrySha256:createHash('sha256').update(fs.readFileSync(entry)).digest('hex'),auth:'shared fixture JWT; installer OAuth NOT verified',checks:[],recordingGate:'HOLD'};
 if(previous)report.previousAttempt=previous;
 let token='';
 function safe(value:any):any{if(typeof value==='string')return value.replaceAll(token||'__NO_TOKEN__','[REDACTED]').replace(/https?:\/\/[^\s"<>]+/g,u=>u.split('?')[0]);if(Array.isArray(value))return value.map(safe);if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,/token|password|authorization|cookie/i.test(k)?'[REDACTED]':safe(v)]));return value;}
 function save(){fs.writeFileSync(path.join(out,'npm-workflow-proof.json'),JSON.stringify(safe(report),null,2)+'\n');}
 const login=await fetch(base+'/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json','X-E2E-Test-Token':E2E_TOKEN},body:JSON.stringify({email:FIXTURE_EMAIL,password:FIXTURE_PASSWORD}),signal:AbortSignal.timeout(30000)});
 if(!login.ok)throw new Error('Fixture login HTTP '+login.status);
 token=(await login.json() as any).token;if(!token)throw new Error('Fixture login returned no token');
 let adapter:any;let connectorBase=base;
 if(process.argv.includes('--local-patch')){
   // Integration harness for the exact patched module, calling real dev APIs.
   // This does not establish that the deployed /tools route has been updated.
   const patched=createConnectorRunTools(base,{Authorization:'Bearer '+token});
   adapter=createServer(async(req,res)=>{try{
     if(req.headers.authorization!=='Bearer '+token){res.writeHead(401);res.end();return;}
     const chunks=[];for await(const chunk of req)chunks.push(chunk);
     const body=JSON.parse(Buffer.concat(chunks).toString()||'{}');let result:any;
     if(req.url==='/tools/get_run'||req.url==='/tools/watch_run')result=await patched.getRun(body.run_id,body.include_findings!==false);
     else if(req.url==='/tools/export_report')result=await patched.exportReport(body.run_id,body);
     else {const upstream=await fetch(base+req.url,{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body)});res.statusCode=upstream.status;result=await upstream.json();}
     res.setHeader('Content-Type','application/json');res.end(JSON.stringify(result));
   }catch(e:any){res.writeHead(500,{'Content-Type':'application/json'});res.end(JSON.stringify({error:e.message}));}});
   await new Promise<void>(r=>adapter.listen(0,'127.0.0.1',r));connectorBase='http://127.0.0.1:'+adapter.address().port;
   report.testMode='Patched local adapter + published npm MCP + real dev APIs; NOT a deployed-route test';
 }
 const transport=new StdioClientTransport({command:process.execPath,args:[entry],env:{PATH:process.env.PATH!,BIOMATE_API_BASE:connectorBase,BIOMATE_API_KEY:token},stderr:'pipe'});
 const client=new Client({name:'biomate-workflow-proof',version:'1.0.0'});
 try{
 await client.connect(transport);
 const listed=await client.listTools();report.checks.push({step:'initialize/list',passed:listed.tools.some((t:any)=>t.name==='run_workflow'),tools:listed.tools.map((t:any)=>t.name)});report.checks.push({step:'published-package-vs-docs-tool-count',passed:listed.tools.length===19,expected:19,actual:listed.tools.length});save();console.log('Listed '+listed.tools.length+' tools');
 async function call(name:string,args:any){const r=await client.callTool({name,arguments:args},undefined,{timeout:150000});const raw=r.content?.find((c:any)=>c.type==='text')?.text;let data;try{data=JSON.parse(raw);}catch{data=raw;}const passed=!r.isError&&!data?.error;report.checks.push({step:name,args,passed,result:data});save();console.log(name+': '+(passed?'PASS':'FAIL'));if(!passed)throw new Error(name+' failed; see sanitized evidence');return data;}
 const search=await call('search_workflow',{query:'Predict ADMET Properties',limit:3});
 const wf=search.workflow_ga || search.workflows?.[0] || search.results?.[0];
 if(!wf)throw new Error('Search returned no workflow definition');
 const id=wf.id || wf.workflow_id || wf.name;if(!id)throw new Error('Workflow identifier missing');
 const spec=await call('get_workflow_spec',{workflow_id:String(id)});
 if(spec.workflow_ga?.nextflow_path!==wf.nextflow_path)throw new Error('Search/spec workflow mismatch');
 if(process.argv.includes('--run')){
 const launch=await call('run_workflow',{workflow_id:String(id),params:{smiles_list:JSON.stringify(['CC(=O)OC1=CC=CC=C1C(=O)O','CN1C=NC2=C1C(=O)N(C(=O)N2C)C','CC(C)CC1=CC=C(C=C1)C(C)C(=O)O']),ADMET_model_type:'MPNN'}});
 report.runId=launch.run_id||launch.runId||launch.id||launch.run?.id;save();
 if(!report.runId)throw new Error('Launch returned no run ID');
 }
 if(report.runId||process.env.CONNECTOR_RUN_ID){
 report.runId=report.runId||process.env.CONNECTOR_RUN_ID;
 let run:any;const deadline=Date.now()+12*60*1000;
 do{run=await call('get_run',{run_id:report.runId});report.runState=run.status||run.execution?.status||run.run?.status;save();console.log('Run state: '+report.runState);if(!['running','pending','queued'].includes(report.runState))break;if(Date.now()>=deadline)throw new Error('Run has not finished within bounded observation window');await new Promise(r=>setTimeout(r,30000));}while(true);
 if(['failed','error','cancelled'].includes(report.runState))throw new Error('Workflow ended '+report.runState);
 if(['completed','success','succeeded'].includes(String(report.runState).toLowerCase())){
 report.checks.push({step:'get-run-output-contract',passed:Array.isArray(run.output_files)&&run.output_files.length>0,reason:'Published preview_file instructs users to copy s3_uri from get_run.output_files'});save();
 if(process.argv.includes('--analyze'))await call('analyze_results',{run_id:report.runId,question:'Summarize the actual outputs for the three input compounds, identify the prediction model used and its limitations. Do not infer clinical safety.'});
 let exported:any;
 for(let attempt=0;attempt<15;attempt++){
   exported=await call('export_report',{run_id:report.runId,format:'markdown'});
   if(exported.status!=='pending')break;
   await new Promise(r=>setTimeout(r,5000));
 }
 if(exported.status!=='ready'||exported.format!=='markdown'||!exported.content?.includes(report.runId))throw new Error('Export did not return a ready Markdown report for the requested run');
 report.checks.push({step:'report-content',passed:true,characters:exported.content.length});save();
 const outputs=run.output_files||run.outputs||run.run?.output_files||[];
 const file=outputs.find((f:any)=>f.s3_uri&&/results\.json$/.test(f.name||''));
 if(file){
 const preview=await call('preview_file',{run_id:report.runId,s3_key:file.s3_uri});
 const result=JSON.parse(preview.preview_text||'null');
 const compounds=String(result?.result||'').match(/^Compound:/gm)||[];
 const values=[...String(result?.result||'').matchAll(/DILI probability\s*:\s*([0-9.]+)/g)].map(m=>m[1]);
 const passed=result?.success===true&&compounds.length===3&&values.length===3&&values.every(v=>exported.content.includes(v));
 report.checks.push({step:'preview-report-scientific-consistency',passed,compoundCount:compounds.length,scope:'Numeric consistency only, not biological validation'});save();
 if(!passed)throw new Error('Report/preview scientific output check failed');
 }
 else report.checks.push({step:'preview-file-discovery',passed:false,reason:'No result output with s3_uri in get_run'});
 }
 }
 report.workflowJourneyPassed=['get-run-output-contract','report-content','preview_file'].every(step=>report.checks.some((c:any)=>c.step===step&&c.passed));
 report.nextStep='Recording held pending package/docs consistency, client OAuth and bilingual UI checks';save();
 if(report.checks.some((c:any)=>!c.passed))process.exitCode=1;
 }catch(e:any){report.failure=e.message;save();process.exitCode=1;}finally{await client.close();if(adapter)await new Promise<void>(r=>adapter.close(()=>r()));}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
