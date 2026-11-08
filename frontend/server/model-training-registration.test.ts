import {afterEach,expect,it,vi} from 'vitest';
import {buildTrainingRegistrationManifest,registerOwnedTrainingRun,readOwnedTrainingVersions,requestInternalModelRegistry,type RegistrationRun} from './model-training-registration';
const run=(overrides:Partial<RegistrationRun>={}):RegistrationRun=>({id:'own-run',userId:'owner',projectId:'project',workflowName:'Training',workflowDefinition:{domain:'ml_training'},execution:{status:'completed',trainingLaunchParameters:{model_name:'Tumor classifier',model_type:'sklearn_tabular',task_type:'classification',metric:'auc',gate_threshold:0.7}},createdAt:'2026-11-07T10:00:00Z',updatedAt:'2026-11-07T10:05:00Z',...overrides});
const outputs=[{s3Uri:'s3://results/own/results/artifact/model.pkl'},{s3Uri:'s3://results/own/results/artifact/metadata.json'},{s3Uri:'s3://results/own/results/metrics.json'}];
const deps=()=>({listOutputs:vi.fn(async()=>outputs),internalRequest:vi.fn(async()=>({status:200,body:{version:1,status:'candidate'}}))});
afterEach(()=>{vi.unstubAllGlobals();vi.unstubAllEnvs();});
it('registers exact owned snapshot and bound output refs without inventing registry identity',async()=>{
 const d=deps();await registerOwnedTrainingRun('owner',run(),d);
 expect(d.internalRequest).toHaveBeenCalledWith('/api/internal/model-training/register',{run:{run_id:'own-run',owner_id:'owner',project_id:'project',status:'completed',model_name:'Tumor classifier',model_type:'sklearn_tabular',task_type:'classification',metric:'auc',gate_threshold:0.7,higher_is_better:true},artifacts:[{s3_uri:outputs[0].s3Uri,relative_path:'model.pkl'},{s3_uri:outputs[1].s3Uri,relative_path:'metadata.json'}],metrics_s3_uri:outputs[2].s3Uri});
});
it('denies unauthenticated and foreign owners before output/admin access',async()=>{
 for(const user of [undefined,'stranger']) {const d=deps();await expect(registerOwnedTrainingRun(user,run(),d)).rejects.toMatchObject({status:user?403:401});expect(d.listOutputs).not.toHaveBeenCalled();expect(d.internalRequest).not.toHaveBeenCalled();}
});
it('does not guess historical launch overrides from workflow defaults',()=>{
 const value=run({workflowDefinition:{domain:'ml_training',parameters:{model_name:'Guess',model_type:'sklearn_tabular',task_type:'classification',metric:'auc'}},execution:{status:'completed'}});
 expect(()=>buildTrainingRegistrationManifest('owner',value,outputs)).toThrow(/not recorded/);
});
it('rejects unrelated, active, incomplete or invalid-threshold runs',()=>{
 for(const value of [run({workflowDefinition:{domain:'transcriptomics'}}),run({execution:{status:'running'}}),run({execution:{status:'completed',trainingLaunchParameters:{metric:'auc'}}}),run({execution:{status:'completed',trainingLaunchParameters:{...run().execution.trainingLaunchParameters,gate_threshold:'bad'}}})])expect(()=>buildTrainingRegistrationManifest('owner',value,outputs)).toThrow();
});
it('rejects ambiguous or missing model metrics/artifact trees',()=>{
 for(const list of [outputs.slice(0,2),[outputs[0],outputs[2],{s3Uri:'s3://results/other/artifact/model.pkl'}],[...outputs,outputs[2]]])expect(()=>buildTrainingRegistrationManifest('owner',run(),list)).toThrow();
});
it('rejects local and network references even if canonical adapter mistakenly returns them',()=>{
 for(const s3Uri of ['file:///private/model.pkl','http://localhost/model.pkl','s3://results/file?path=artifact/model.pkl'])expect(()=>buildTrainingRegistrationManifest('owner',run(),[{s3Uri}])).toThrow();
});
it('reads versions only for server resolved run owner/project',async()=>{
 const d=deps();await readOwnedTrainingVersions('owner',run(),d);
 expect(d.internalRequest).toHaveBeenCalledWith('/api/internal/model-training/versions?owner_id=owner&run_id=own-run&project_id=project');
 await expect(readOwnedTrainingVersions('stranger',run(),d)).rejects.toMatchObject({status:403});expect(d.internalRequest).toHaveBeenCalledTimes(1);
});
it('uses server admin credentials in the private backend bridge',async()=>{
 vi.stubEnv('GALAXY_API_KEY','server-only-test-key');vi.stubEnv('GALAXY_URL','http://backend');
 const f=vi.fn(async()=>({status:200,json:async()=>({version:2,status:'rejected'})}));vi.stubGlobal('fetch',f);
 expect(await requestInternalModelRegistry('/api/internal/model-training/register',{trusted:true})).toEqual({status:200,body:{version:2,status:'rejected'}});
 expect(f).toHaveBeenCalledWith('http://backend/api/internal/model-training/register',expect.objectContaining({method:'POST',headers:{'X-API-Key':'server-only-test-key','Content-Type':'application/json'},body:'{"trusted":true}'}));
});
it('fails closed if central registry credentials are missing',async()=>{
 vi.stubEnv('GALAXY_API_KEY','');const f=vi.fn();vi.stubGlobal('fetch',f);
 await expect(requestInternalModelRegistry('/api/internal/model-training/versions')).rejects.toMatchObject({status:503});expect(f).not.toHaveBeenCalled();
});

it('does not fill incomplete exact snapshots with workflow defaults',()=>{
 const value=run({workflowDefinition:{domain:'ml_training',parameters:{model_name:'Default',model_type:'sklearn_tabular',task_type:'classification',metric:'auc'}},execution:{status:'completed',trainingLaunchParameters:{metric:'auc'}}});
 expect(()=>buildTrainingRegistrationManifest('owner',value,outputs)).toThrow(/model_name is missing/);
});
