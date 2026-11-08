import React from 'react';
import {render,screen,fireEvent,waitFor} from '@testing-library/react';
import {afterEach,beforeEach,describe,it,expect,vi} from 'vitest';
const mocked=vi.hoisted(()=>({getDocument:vi.fn(),getPage:vi.fn(),destroy:vi.fn(),cancel:vi.fn(),worker:{workerSrc:''}}));
vi.mock('pdfjs-dist',()=>({GlobalWorkerOptions:mocked.worker,getDocument:mocked.getDocument}));
vi.mock('@/lib/i18n',()=>({t:()=> 'Loading…',tOr:(_k:string,f:string,v?:Record<string,unknown>)=>f.replace(/{{(\w+)}}/g,(_,k)=>String(v?.[k]??''))}));
import {PdfCanvasViewer} from './pdf-canvas-viewer';
beforeEach(()=>{
 vi.clearAllMocks();
 vi.spyOn(HTMLCanvasElement.prototype,'getContext').mockReturnValue({} as CanvasRenderingContext2D);
 mocked.getPage.mockResolvedValue({getViewport:()=>({width:600,height:800}),render:()=>({promise:Promise.resolve(),cancel:mocked.cancel})});
 mocked.getDocument.mockReturnValue({promise:Promise.resolve({numPages:2,getPage:mocked.getPage}),destroy:mocked.destroy});
});
afterEach(()=>{vi.restoreAllMocks();});
describe('safe local PDF canvas preview',()=>{
 it('renders authorized bytes without iframe/plugin/CDN and exposes all pages',async()=>{
  const bytes=new Uint8Array([37,80,68,70]);
  render(<PdfCanvasViewer name="report.pdf" data={bytes}/>);
  await waitFor(()=>expect(screen.getByRole('button',{name:'Next page'})).toBeEnabled());
  expect(screen.getByRole('img')).toBeVisible();expect(document.querySelector('iframe')).toBeNull();
  expect(mocked.getDocument.mock.calls[0][0].data).toEqual(bytes);expect(mocked.getDocument.mock.calls[0][0].data).not.toBe(bytes);
  expect(mocked.worker.workerSrc).not.toMatch(/^https?:/);
  fireEvent.click(screen.getByRole('button',{name:'Next page'}));
  await waitFor(()=>expect(mocked.getPage).toHaveBeenCalledWith(2));
  expect(screen.getByText('Page 2 of 2')).toBeInTheDocument();
 });
 it('reports invalid PDFs instead of leaving a blank embed',async()=>{
  mocked.getDocument.mockReturnValue({promise:Promise.reject(new Error('invalid PDF')),destroy:mocked.destroy});
  render(<PdfCanvasViewer name="invalid.pdf" data={new Uint8Array([0])}/>);
  expect(await screen.findByRole('alert')).toHaveTextContent('Could not render this PDF.');
  expect(document.querySelector('iframe')).toBeNull();
 });
 it('destroys the document and cancels rendering when the panel closes',async()=>{
  const view=render(<PdfCanvasViewer name="report.pdf" data={new Uint8Array([37])}/>);
  await waitFor(()=>expect(mocked.getPage).toHaveBeenCalled());view.unmount();
  expect(mocked.destroy).toHaveBeenCalledOnce();expect(mocked.cancel).toHaveBeenCalled();
 });
});
