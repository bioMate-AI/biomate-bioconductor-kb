import React from 'react';
import {render,screen,fireEvent,waitFor} from '@testing-library/react';
import {afterEach,describe,it,expect,vi} from 'vitest';
import {RunFileDownload,runFileUrl} from './run-file-download';
vi.mock('@/lib/i18n',()=>({tOr:(_k:string,f:string,v?:Record<string,string>)=>f.replace('{{error}}',v?.error||'')}));
afterEach(()=>{vi.restoreAllMocks();});
describe('owned run output download',()=>{
 it('encodes identity and uses same-origin authorized route, never a signed output URL',()=>{
  const url=runFileUrl('run/id',{name:'report #1.json',path:'s3://bucket/a b/report #1.json'},true);
  expect(url.startsWith('/api/workflows/runs/run%2Fid/step-file?')).toBe(true);
  const query=new URL(url,'https://biomate.invalid').searchParams;
  expect(query.get('path')).toBe('s3://bucket/a b/report #1.json');expect(query.get('name')).toBe('report #1.json');expect(query.get('download')).toBe('1');
 });
 it('downloads actual response bytes with filename and cookie authentication',async()=>{
  const fetcher=vi.spyOn(globalThis,'fetch').mockResolvedValue({ok:true} as Response);
  const click=vi.spyOn(HTMLAnchorElement.prototype,'click').mockImplementation(function(this:HTMLAnchorElement){expect(this.download).toBe('result.json');expect(this.getAttribute('href')).toBe(runFileUrl('owned',{name:'result.json',path:'/owned/result.json'},true));});
  render(<RunFileDownload runId="owned" file={{name:'result.json',path:'/owned/result.json'}}/>);
  fireEvent.click(screen.getByRole('button',{name:'Download result.json'}));
  await waitFor(()=>expect(click).toHaveBeenCalledOnce());expect(fetcher).toHaveBeenCalledWith(expect.stringContaining('/api/workflows/runs/owned/step-file?'),{credentials:'include',method:'HEAD'});
 });
 it('reports permission failure instead of downloading an error document',async()=>{
  vi.spyOn(globalThis,'fetch').mockResolvedValue({ok:false,status:403} as Response);const click=vi.spyOn(HTMLAnchorElement.prototype,'click');
  render(<RunFileDownload runId="owned" file={{name:'private.json'}}/>);fireEvent.click(screen.getByRole('button',{name:'Download private.json'}));
  expect(await screen.findByRole('alert')).toHaveTextContent('HTTP 403');expect(click).not.toHaveBeenCalled();expect(screen.getByRole('button')).toBeEnabled();
 });
});
