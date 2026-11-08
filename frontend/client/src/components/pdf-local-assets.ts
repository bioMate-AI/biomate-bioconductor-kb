/** pdf.js resource names resolve only to build-time bundled public assets.
 * This includes CJK maps and image decoders without allowing document-chosen URLs.
 */
const assets = import.meta.glob<string>('../../../node_modules/pdfjs-dist/{cmaps,standard_fonts,wasm}/*.{bcmap,pfb,ttf,wasm,js}', {eager:true, query:'?url', import:'default'});
const directories: Record<string, string> = {cMapUrl:'cmaps',standardFontDataUrl:'standard_fonts',wasmUrl:'wasm'};
export function pdfAssetUrl(kind: string, filename: string): string {
  const directory=directories[kind];
  const url=directory && assets[`../../../node_modules/pdfjs-dist/${directory}/${filename}`];
  if (!url || /[\\/]/.test(filename)) throw new Error('Unrecognized local PDF resource');
  return url;
}
export class LocalPdfBinaryDataFactory {
  async fetch({kind,filename}: {kind:string;filename:string}) {
    const response=await fetch(pdfAssetUrl(kind,filename),{credentials:'omit'});
    if(!response.ok) throw new Error('Local PDF resource unavailable');
    return new Uint8Array(await response.arrayBuffer());
  }
}
