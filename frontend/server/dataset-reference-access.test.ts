import { describe, expect, it, vi } from 'vitest';
import { authorizeDatasetReference, projectDatasetKey } from './dataset-reference-access';
const key='projects/project-a/inputs/counts.csv';
describe('private dataset profiling/metadata authorization', () => {
 it('allows the exact registered key for its owner or project member', async () => {
  const lookup=vi.fn(async(k,u)=>k===key && ['owner','member'].includes(u));
  for(const user of ['owner','member']) expect(await authorizeDatasetReference('s3://files/'+key,user,'files',lookup)).toEqual({allowed:true,key});
  expect(await authorizeDatasetReference(key,'stranger','files',lookup)).toEqual({allowed:false,status:403});
 });
 it('rejects anonymous requests before storage lookup', async () => {
  const lookup=vi.fn();expect(await authorizeDatasetReference(key,null,'files',lookup)).toEqual({allowed:false,status:401});expect(lookup).not.toHaveBeenCalled();
 });
 it.each(['/etc/passwd','/tmp/private.csv','s3://other-bucket/'+key,'projects/a/../private.csv',undefined])('rejects arbitrary/unbound references %s',ref=>{
  expect(projectDatasetKey(ref,'files')).toBeNull();
 });
 it('fails closed when an owned file is absent from the registry', async()=>{
  expect(await authorizeDatasetReference(key,'owner','files',async()=>false)).toEqual({allowed:false,status:403});
 });
});
