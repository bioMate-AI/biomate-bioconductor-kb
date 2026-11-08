import {describe, it, expect} from 'vitest';
import {buildFullReportMarkdown} from './AfterRunReport';
const args = {runId:'owned-run', workflowName:'Integration', methods:'', qcEvents:[], parameters:{input:'samplesheet.csv',profile:'test,aws'}, outputs:[{name:'umap.png',ext:'png',path:'s3://owned/umap.png',step:'integration',size:100},{name:'metrics.tsv',ext:'tsv',path:'s3://owned/metrics.tsv',step:'integration',size:384}], findings:{status:'ready',summary:'Source scores',key_results:[{metric:'Bio conservation',value:'0.5',source_file:'metrics.tsv'}]}} as any;
describe('concise report with source-backed figures',()=>{
  it('keeps quantitative cells and source columns, renders saved figure inline and avoids duplicate inventory in the panel',()=>{
    const md=buildFullReportMarkdown({...args,includeFileInventory:false});
    expect(md).toContain('| Bio conservation | 0.5 | metrics.tsv |');
    expect(md).toContain('![umap.png](/api/workflows/runs/owned-run/step-file?');
    expect(md).toContain('2 scientific output files');
    expect(md).not.toContain('## Output files');
    expect(md).not.toContain('| `profile` | test,aws _(value)_ |');
    expect(md).not.toContain('Bytes are intentionally not');
  });
  it('retains full file inventory in the downloadable document',()=>{
    const md=buildFullReportMarkdown(args);
    expect(md).toContain('## Output files');
    expect(md).toContain('[metrics.tsv](/api/workflows/runs/owned-run/step-file?');
    expect(md).not.toContain('**Run ID**');
  });
});
