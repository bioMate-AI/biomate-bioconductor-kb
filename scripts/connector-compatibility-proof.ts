/** Read-only live compatibility checks against the published npm connector. */
import fs from 'node:fs';import {pathToFileURL} from 'node:url';
import {FIXTURE_EMAIL,FIXTURE_PASSWORD,E2E_TOKEN} from '../frontend/e2e/_fixture-login';
async function main(){
 const base='https://dev-public.biomate.ai',prefix='/private/tmp/biomate-connector-20261009/node_modules';
 const directory='docs/qa/20261009-connector-workflows/compatibility';fs.mkdirSync(directory,{recursive:true});
 const checks:any[]=[];const report:any={date:new Date().toISOString(),scope:'Published npm connector, existing run, no new workflow or instrument execution',checks};
 const save=()=>fs.writeFileSync(directory+'/results.json',JSON.stringify(report,null,2)+'\n');
 const login=await fetch(base+'/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json','X-E2E-Test-Token':E2E_TOKEN},body:JSON.stringify({email:FIXTURE_EMAIL,password:FIXTURE_PASSWORD})});
 if(!login.ok)throw Error('Fixture login HTTP '+login.status);const {token}=await login.json() as any;
 const {Client}=await import(pathToFileURL(prefix+'/@modelcontextprotocol/sdk/dist/esm/client/index.js').href);
 const {StdioClientTransport}=await import(pathToFileURL(prefix+'/@modelcontextprotocol/sdk/dist/esm/client/stdio.js').href);
 async function connect(key:string){const client=new Client({name:'compatibility-proof',version:'1.0'});await client.connect(new StdioClientTransport({command:process.execPath,args:[prefix+'/@biomate/mcp-server/dist/index.js'],env:{PATH:process.env.PATH!,BIOMATE_API_BASE:base,BIOMATE_API_KEY:key},stderr:'pipe'}));return client;}
 const client=await connect(token);const run_id='80992e6c-d483-49ed-a730-b698d2d0f2e0';
 async function test(c:any,name:string,args:any,label:string,assert:(result:any,error:boolean)=>boolean){
  const r=await c.callTool({name,arguments:args},undefined,{timeout:90000});const data=JSON.parse(r.content[0].text);const error=r.isError===true;
  const summary={label,tool:name,passed:assert(data,error),isError:error,status:data.status,fields:Object.keys(data),error:error?String(data.error||'').replaceAll(token,'[REDACTED]').slice(0,300):undefined};checks.push(summary);save();console.log(label+': '+(summary.passed?'PASS':'FAIL'));return data;
 }
 try{
 const tools=await client.listTools();report.toolNames=tools.tools.map((t:any)=>t.name);save();
 await test(client,'get_run',{run_id,include_findings:false},'exclude-findings', (d,e)=>!e&&!('findings' in d)&&d.output_files?.length>0);
 await test(client,'get_run',{run_id},'default-findings-and-outputs',(d,e)=>!e&&d.findings?.status==='ready'&&d.output_files?.every((f:any)=>f.s3_uri?.startsWith('s3://')));
 await test(client,'watch_run',{run_id},'watch-run-snapshot',(d,e)=>!e&&d.status==='completed'&&d.output_files?.length>0);
 await test(client,'export_report',{run_id,format:'markdown',sections:['findings']},'explicit-findings-markdown',(d,e)=>!e&&d.status==='ready'&&d.content?.includes(run_id));
 for(const format of ['pdf','docx'])await test(client,'export_report',{run_id,format},'reject-unsupported-'+format,(d,e)=>e&&/Unsupported report format/.test(d.error));
 await test(client,'export_report',{run_id,format:'markdown',sections:['methods']},'reject-unsupported-section',(d,e)=>e&&/Unsupported report sections/.test(d.error));
 await test(client,'get_run',{run_id:'connector-nonexistent-run'},'missing-run-fails',(d,e)=>e&&/404/.test(d.error));
 // Published read-only instrument tools: no protocol execution is attempted.
 await test(client,'list_instruments',{},'advertised-instrument-list-supported',(_d,e)=>!e);
 await test(client,'get_instrument_status',{instrument_id:'connector-nonexistent-instrument'},'instrument-status-route-exists',(d,e)=>!e||!/Unknown operationId/.test(d.error));
 }finally{await client.close();}
 const unauthorized=await connect('invalid-connector-test-credential');try{await test(unauthorized,'get_run',{run_id},'invalid-auth-denied',(d,e)=>e&&/401|403|unauthoriz|invalid.*token/i.test(d.error));}finally{await unauthorized.close();}
 report.passes=checks.filter(c=>c.passed).length;report.failures=checks.filter(c=>!c.passed).length;save();if(report.failures)process.exitCode=1;
}
main().catch(e=>{console.error(e.message);process.exitCode=1});
