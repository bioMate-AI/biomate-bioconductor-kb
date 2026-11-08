import {describe,it,expect} from 'vitest';
import {pdfAssetUrl} from './pdf-local-assets';
describe('bundled PDF resources',()=>{
 it.each([['cMapUrl','Adobe-GB1-UCS2.bcmap'],['standardFontDataUrl','LiberationSans-Regular.ttf'],['wasmUrl','openjpeg.wasm'],['wasmUrl','jbig2.wasm']])('resolves known %s/%s locally',(kind,file)=>{
  const url=pdfAssetUrl(kind,file);expect(url).toBeTruthy();expect(url).not.toMatch(/^https?:\/\//);
 });
 it('rejects arbitrary document URLs, traversal and unknown resource kinds',()=>{
  for(const [kind,file] of [['wasmUrl','https://external.invalid/file'],['cMapUrl','../../private'],['unknown','openjpeg.wasm']])expect(()=>pdfAssetUrl(kind,file)).toThrow('Unrecognized');
 });
});
