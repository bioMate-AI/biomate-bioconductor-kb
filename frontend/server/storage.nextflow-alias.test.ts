import { expect, it, vi } from 'vitest';
vi.mock('./db', () => ({db:{select:()=>({from:()=>({where:()=>({limit:async()=>[]})})})}}));
import { MemStorage } from './storage';
it('resolves Nextflow aliases to the original owned run rather than treating an unknown id as authorized',async()=>{
 const storage:any=new MemStorage();
 const run={id:'canonical-run',userId:'owner',execution:{nextflowRunId:'nf-run-123'}};
 storage.executionRuns.set(run.id,run);
 expect(await storage.getExecutionRunByNextflowId('nf-run-123')).toBe(run);
 expect(await storage.getExecutionRunByNextflowId('unknown-run')).toBeUndefined();
});
