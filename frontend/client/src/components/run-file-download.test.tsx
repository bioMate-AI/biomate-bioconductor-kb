import React from 'react';
import {render,screen,fireEvent} from '@testing-library/react';
import {afterEach,describe,it,expect,vi} from 'vitest';
import {RunFileDownload,runFileUrl} from './run-file-download';
vi.mock('@/lib/i18n',()=>({tOr:(_k:string,f:string)=>f}));
afterEach(()=>{vi.restoreAllMocks();});
describe('native owned run output download',()=>{
 it('encodes run identity, exact output path and attachment request',()=>{
  const url=runFileUrl('run/id',{name:'report #1.json',path:'s3://bucket/a b/report #1.json'},true);
  expect(url.startsWith('/api/workflows/runs/run%2Fid/step-file?')).toBe(true);
  const query=new URL(url,'https://biomate.invalid').searchParams;
  expect(query.get('path')).toBe('s3://bucket/a b/report #1.json');expect(query.get('name')).toBe('report #1.json');expect(query.get('download')).toBe('1');
 });
 it('exposes an actual native attachment link with the intended filename',()=>{
  render(<RunFileDownload runId="owned" file={{name:'result.json',path:'/owned/result.json'}}/>);
  const link=screen.getByRole('link',{name:'Download result.json'});
  expect(link).toHaveAttribute('href',runFileUrl('owned',{name:'result.json',path:'/owned/result.json'},true));
  expect(link).toHaveAttribute('download','result.json');
  expect(screen.queryByRole('button')).not.toBeInTheDocument();
 });
 it('never substitutes a payload external URL or adds an asynchronous request before navigation',()=>{
  const fetcher=vi.spyOn(globalThis,'fetch');
  render(<RunFileDownload runId="owned" file={{name:'plot.png',path:'s3://owned/plot.png',download_url:'https://untrusted.invalid/file'} as any}/>);
  const link=screen.getByRole('link',{name:'Download plot.png'});
  expect(link.getAttribute('href')).toMatch(/^\/api\/workflows\/runs\/owned\/step-file\?/);
  expect(link.getAttribute('href')).not.toContain('untrusted.invalid');
  // Prevent jsdom navigation only; the app itself uses the anchor default action.
  link.addEventListener('click',event=>event.preventDefault());fireEvent.click(link);
  expect(fetcher).not.toHaveBeenCalled();
 });
});
