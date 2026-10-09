/** Verify real personal API-key authorization through the published MCP package. */
import fs from 'node:fs';import {pathToFileURL} from 'node:url';
import {FIXTURE_EMAIL,FIXTURE_PASSWORD,E2E_TOKEN} from '../frontend/e2e/_fixture-login';
async function main(){
 const base='https://dev-public.biomate.ai',prefix='/private/tmp/biomate-connector-20261009/node_modules';
 const out='docs/qa/20261009-connector-workflows/api-key-proof.json';const checks:any[]=[];
 const save=()=>fs.writeFileSync(out,JSON.stringify({date:new Date().toISOString(),checks},null,2)+'\n');
 const login=await fetch(base+'/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json','X-E2E-Test-Token':E2E_TOKEN},body:JSON.stringify({email:FIXTURE_EMAIL,password:FIXTURE_PASSWORD})});
 if(!login.ok)throw new Error('Fixture login HTTP '+login.status);const {token}=await login.json() as any;
 const headers={'Content-Type':'application/json',Authorization:'Bearer '+token};
 const created=await fetch(base+'/api/user/api-keys',{method:'POST',headers,body:JSON.stringify({name:'connector-verification-20261009-temporary'})});
 checks.push({step:'create-personal-key',status:created.status,passed:created.ok});save();
 if(!created.ok)throw new Error('Personal key creation failed HTTP '+created.status);
 const key=await created.json() as any;let client:any;let revoked=false;
 try{
 const {Client}=await import(pathToFileURL(prefix+'/@modelcontextprotocol/sdk/dist/esm/client/index.js').href);
 const {StdioClientTransport}=await import(pathToFileURL(prefix+'/@modelcontextprotocol/sdk/dist/esm/client/stdio.js').href);
 client=new Client({name:'biomate-key-proof',version:'1.0.0'});
 await client.connect(new StdioClientTransport({command:process.execPath,args:[prefix+'/@biomate/mcp-server/dist/index.js'],env:{PATH:process.env.PATH!,BIOMATE_API_BASE:base,BIOMATE_API_KEY:key.key},stderr:'pipe'}));
 const runId='85e8bae6-8836-4abc-a062-44dd2fde30c2';
 const before=await client.callTool({name:'get_run',arguments:{run_id:runId}},undefined,{timeout:30000});
 const body=JSON.parse(before.content[0].text);checks.push({step:'read-owned-run-with-personal-key',passed:!before.isError&&body.runId===runId});save();
 const r=await fetch(base+'/api/user/api-keys/'+encodeURIComponent(key.id),{method:'DELETE',headers});revoked=r.ok;checks.push({step:'revoke-temporary-key',status:r.status,passed:revoked});save();
 if(!revoked)throw new Error('Key revocation failed');
 const after=await client.callTool({name:'get_run',arguments:{run_id:runId}},undefined,{timeout:30000});
 checks.push({step:'revoked-key-denied',passed:after.isError===true&&/401|403|unauthoriz|invalid.*token|invalid.*key/i.test(JSON.stringify(after))});save();
 }finally{if(!revoked){const r=await fetch(base+'/api/user/api-keys/'+encodeURIComponent(key.id),{method:'DELETE',headers});checks.push({step:'cleanup-revoke',passed:r.ok});save();}if(client)await client.close();}
 console.log(JSON.stringify(checks));if(checks.some(c=>!c.passed))process.exitCode=1;
}
main().catch(e=>{console.error(e.message);process.exitCode=1});
