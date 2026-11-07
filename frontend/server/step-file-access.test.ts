import { mkdtempSync, mkdirSync, writeFileSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { isRunFilePathAllowed } from './step-file-access';
const own = 's3://shared-bucket/runs/own/results.csv';
const other = 's3://shared-bucket/projects/other/private.csv';
const run = {execution:{outputs:{result:own},nextflowStatus:{outdir:'/tmp/nextflow_runs/own',s3_output_files:[{s3_uri:own}]}}};
describe('run-scoped step-file access', () => {
 it('allows an owned run output but rejects another private object in the same bucket', () => {
  expect(isRunFilePathAllowed(own,run)).toBe(true);
  expect(isRunFilePathAllowed(other,run)).toBe(false);
 });
 it('allows an exact canonical output only when registered to this run', () => {
  const canonical='s3://shared-bucket/legacy/own.csv';
  expect(isRunFilePathAllowed(canonical,run,[{s3Uri:canonical}])).toBe(true);
  expect(isRunFilePathAllowed(other,run,[{s3Uri:canonical}])).toBe(false);
 });
 it('checks local path boundaries and traversal rather than broad /tmp prefixes', () => {
  expect(isRunFilePathAllowed('/tmp/nextflow_runs/own/a.tsv',run)).toBe(true);
  for(const value of ['/tmp/private.txt','/tmp/nextflow_runs/own-neighbor/a.tsv','/tmp/nextflow_runs/own/../other/a.tsv']) expect(isRunFilePathAllowed(value,run)).toBe(false);
 });
 it('rejects broad shared roots and unregistered storage references', () => {
  expect(isRunFilePathAllowed('/tmp/a.csv',{execution:{nextflowStatus:{outdir:'/tmp'}}})).toBe(false);
  expect(isRunFilePathAllowed(other,{})).toBe(false);
 });
 it('rejects a symlink inside the run directory that points outside it', () => {
  const temp=mkdtempSync(path.join(tmpdir(),'biomate-output-scope-'));
  try {
   const ownDir=path.join(temp,'own');mkdirSync(ownDir);
   const privateFile=path.join(temp,'other-private.csv');writeFileSync(privateFile,'synthetic');
   const link=path.join(ownDir,'escape.csv');symlinkSync(privateFile,link);
   expect(isRunFilePathAllowed(link,{execution:{nextflowStatus:{outdir:ownDir}}})).toBe(false);
  } finally { rmSync(temp,{recursive:true,force:true}); }
 });
});
