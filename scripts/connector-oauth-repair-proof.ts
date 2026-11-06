/** Isolated OAuth gateway + candidate npm package against real BioMate APIs. */
import fs from 'node:fs';
import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { FIXTURE_EMAIL, FIXTURE_PASSWORD, E2E_TOKEN } from '../frontend/e2e/_fixture-login';
const root='/private/tmp/biomate-connector-auth-review';
const temp=fs.mkdtempSync('/private/tmp/biomate-oauth-proof-');
const remote=process.env.CONNECTOR_OAUTH_PROOF_ORIGIN;
const origin=remote||'http://127.0.0.1:18849', api='https://dev-public.biomate.ai';
const entry=process.env.CONNECTOR_OAUTH_PROOF_ENTRY || root+'/connectors/mcp-server/dist/index.js';
const packageInfo=JSON.parse(fs.readFileSync(join(dirname(dirname(entry)), 'package.json'),'utf8'));
const results:any[]=[];
const record=(step:string,passed:boolean)=>{results.push({step,passed});console.log(step+': '+(passed?'PASS':'FAIL'));if(!passed)throw new Error(step+' failed');};
async function main(){
 const login=await fetch(api+'/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json','X-E2E-Test-Token':E2E_TOKEN},body:JSON.stringify({email:FIXTURE_EMAIL,password:FIXTURE_PASSWORD})});
 if(!login.ok)throw new Error('Fixture login failed');
 const {token}=await login.json() as any;
 const headers={Authorization:'Bearer '+token};
 const before=await (await fetch(api+'/api/user/api-keys',{headers})).json() as any[];
 const log=fs.openSync(temp+'/service.log','w',0o600);
 const child=remote ? null : spawn('/private/tmp/connector-auth-venv/bin/python',['-m','remote_mcp.run'],{cwd:root,env:{PATH:process.env.PATH!,BIOMATE_API_URL:api,BIOMATE_OAUTH_SIGNING_KEY:randomBytes(64).toString('hex'),BIOMATE_OAUTH_DB:temp+'/oauth.db',BIOMATE_MCP_PORT:'18849',BIOMATE_MCP_REQUIRE_AUTH:'1'},stdio:['ignore',log,log]});
 let client:any;
 try{
  let healthy=false;
  for(let i=0;i<40;i++){try{healthy=(await fetch(origin+'/healthz')).ok;}catch{}if(healthy)break;await new Promise(r=>setTimeout(r,250));}
  record(remote?'deployed-service-reachable':'isolated-service-started',healthy);
  const callback='http://127.0.0.1:53682/callback';
  const registered=await fetch(origin+'/oauth/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({client_name:'Connector repair verification',redirect_uris:[callback],token_endpoint_auth_method:'none'})});
  const {client_id}=await registered.json() as any;
  record('dynamic-client-registration',registered.status===201&&Boolean(client_id));
  const verifier=randomBytes(32).toString('base64url');
  const params={response_type:'code',client_id,redirect_uri:callback,code_challenge:createHash('sha256').update(verifier).digest('base64url'),code_challenge_method:'S256',scope:'runs:read reports:export',state:randomBytes(20).toString('hex')};
  const consent=await fetch(origin+'/oauth/authorize',{method:'POST',redirect:'manual',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({...params,action:'allow',email:FIXTURE_EMAIL,password:FIXTURE_PASSWORD})});
  record('real-account-login-and-consent',consent.status===302);
  const location=new URL(consent.headers.get('location')!);record('oauth-state-preserved',location.searchParams.get('state')===params.state);
  const exchanged=await fetch(origin+'/oauth/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'authorization_code',code:location.searchParams.get('code')!,client_id,redirect_uri:callback,code_verifier:verifier})});
  const tokens=await exchanged.json() as any;record('pkce-code-exchange',exchanged.ok&&Boolean(tokens.access_token)&&Boolean(tokens.refresh_token));
  const credentialFile=temp+'/credential.json';fs.writeFileSync(credentialFile,JSON.stringify({...tokens,clientId:client_id,authBase:origin,expires_at:0}),{mode:0o600});
  const sdk='/private/tmp/biomate-connector-20261009/node_modules/@modelcontextprotocol/sdk/dist/esm/client/';
  const {Client}=await import(pathToFileURL(sdk+'index.js').href);const {StdioClientTransport}=await import(pathToFileURL(sdk+'stdio.js').href);
  async function connect(){const c=new Client({name:'oauth-proof',version:'1'});await c.connect(new StdioClientTransport({command:process.execPath,args:[entry],env:{PATH:process.env.PATH!,BIOMATE_OAUTH_FILE:credentialFile},stderr:'pipe'}));return c;}
  client=await connect();const tools=await client.listTools();record('nineteen-supported-tools',tools.tools.length===19&&!tools.tools.some((t:any)=>t.name==='list_instruments'));
  const read=await client.callTool({name:'get_run',arguments:{run_id:'80992e6c-d483-49ed-a730-b698d2d0f2e0'}},undefined,{timeout:90000});record('oauth-read-real-owned-run',!read.isError&&JSON.parse(read.content[0].text).status==='completed');
  const runData=JSON.parse(read.content[0].text);record('owned-run-output-inventory',Array.isArray(runData.output_files)&&runData.output_files.length>0);
  let report:any;
  for(let i=0;i<12;i++){
   const exported=await client.callTool({name:'export_report',arguments:{run_id:'80992e6c-d483-49ed-a730-b698d2d0f2e0',format:'markdown'}},undefined,{timeout:90000});
   if(exported.isError)throw new Error('Report export failed');
   report=JSON.parse(exported.content[0].text);if(report.status==='ready')break;
   await new Promise(resolve=>setTimeout(resolve,5000));
  }
  record('markdown-report-export',report?.status==='ready'&&report?.content?.includes('80992e6c-d483-49ed-a730-b698d2d0f2e0'));
  const saved=JSON.parse(fs.readFileSync(credentialFile,'utf8'));record('refresh-rotated-and-persisted',saved.refresh_token!==tokens.refresh_token&&saved.expires_at>Date.now());
  const replay=await fetch(origin+'/oauth/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'refresh_token',client_id,refresh_token:tokens.refresh_token})});record('old-refresh-token-rejected',replay.status===400);
  const denied=await client.callTool({name:'run_workflow',arguments:{workflow_id:'never-execute'}});record('write-without-scope-denied',denied.isError===true&&JSON.parse(denied.content[0].text).error==='insufficient_scope');
  if (!remote) {
  const issued=await (await fetch(api+'/api/user/api-keys',{headers})).json() as any[];
  const personal=issued.find(k=>k.name==='BioMate OAuth connector'&&!before.some(b=>b.id===k.id));
  if(!personal)throw new Error('Temporary personal key missing');
  const revoked=await fetch(api+'/api/user/api-keys/'+encodeURIComponent(personal.id),{method:'DELETE',headers});
  record('personal-key-revocation',revoked.ok);
  const blocked=await client.callTool({name:'get_run',arguments:{run_id:'80992e6c-d483-49ed-a730-b698d2d0f2e0'}});record('revoked-personal-key-denied',blocked.isError===true);
  const reconnect=await fetch(origin+'/oauth/authorize',{method:'POST',redirect:'manual',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({...params,action:'allow',email:FIXTURE_EMAIL,password:FIXTURE_PASSWORD})});
  record('reconnect-replaces-revoked-personal-key',reconnect.status===302);
  }
  await client.close();client=await connect();const again=await client.callTool({name:'get_run',arguments:{run_id:'80992e6c-d483-49ed-a730-b698d2d0f2e0'}},undefined,{timeout:90000});record('credentials-survive-client-restart',!again.isError);
 }finally{
  if(client)await client.close();child?.kill();fs.closeSync(log);
  const after=await (await fetch(api+'/api/user/api-keys',{headers})).json() as any[];
  for(const key of after.filter(k=>k.name==='BioMate OAuth connector'&&!before.some(b=>b.id===k.id))){const revoked=await fetch(api+'/api/user/api-keys/'+encodeURIComponent(key.id),{method:'DELETE',headers});results.push({step:'revoke-temporary-personal-key',passed:revoked.ok});}
  fs.writeFileSync('docs/qa/20261009-connector-workflows/compatibility/'+(remote?'oauth-deployed-proof.json':'oauth-repair-proof.json'),JSON.stringify({date:new Date().toISOString(),packageVersion:packageInfo.version,clientEntry:entry,scope:remote?'Deployed OAuth gateway with real test account and existing run; no workflow execution':'Isolated candidate gateway/client with real BioMate fixture account and existing run; no workflow execution',results},null,2)+'\n');
  fs.rmSync(temp,{recursive:true,force:true});
 }
}
main().catch(e=>{console.error(e.message);process.exitCode=1});
