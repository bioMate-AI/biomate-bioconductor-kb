/**
 * High-resolution tutorial capture via the Chrome DevTools screencast.
 * Playwright's built-in video is ~1 Mbit/s VP8 at viewport size, which is too
 * soft for UI close-ups; the screencast delivers device-pixel JPEG frames with
 * wall-clock timestamps that build-live-series.py assembles exactly.
 */
import type {Page,CDPSession,Locator} from '@playwright/test';
import fs from 'node:fs';import path from 'node:path';

export type Focus={x:number;y:number;w:number;h:number};
export type TimelineEvent={scene:number;seconds:number;action:string;focus?:Focus|null;[k:string]:unknown};

export class Screencast{
 private cdp!:CDPSession;private frames:{file:string;t:number}[]=[];private n=0;private pending:Promise<void>[]=[];
 start=0;
 constructor(private page:Page,private dir:string){}
 async begin(){
  fs.rmSync(this.dir,{recursive:true,force:true});fs.mkdirSync(this.dir,{recursive:true});
  this.cdp=await this.page.context().newCDPSession(this.page);
  this.cdp.on('Page.screencastFrame',(f:any)=>{
   const file=`f${String(this.n++).padStart(6,'0')}.jpg`;const t=f.metadata.timestamp*1000;
   this.pending.push(fs.promises.writeFile(path.join(this.dir,file),Buffer.from(f.data,'base64')));
   this.frames.push({file,t});
   this.cdp.send('Page.screencastFrameAck',{sessionId:f.sessionId}).catch(()=>{});
  });
  await this.cdp.send('Page.startScreencast',{format:'jpeg',quality:92,everyNthFrame:1});
  this.start=Date.now();
 }
 now(){return (Date.now()-this.start)/1000;}
 async end(){
  await this.cdp.send('Page.stopScreencast');await Promise.all(this.pending);
  const t0=this.start;
  const frames=this.frames.map(f=>({file:f.file,seconds:(f.t-t0)/1000}));
  fs.writeFileSync(path.join(this.dir,'frames.json'),JSON.stringify({startEpochMs:t0,frames},null,1));
  return frames;
 }
}

/** CSS-pixel rect around one or more elements, padded and clamped to the viewport. */
export async function focusOf(page:Page,targets:Locator[],pad=24):Promise<Focus>{
 const vp=page.viewportSize()!;let x0=Infinity,y0=Infinity,x1=-Infinity,y1=-Infinity;
 for(const t of targets){const b=await t.boundingBox();if(!b)throw new Error('Focus target is not visible');x0=Math.min(x0,b.x);y0=Math.min(y0,b.y);x1=Math.max(x1,b.x+b.width);y1=Math.max(y1,b.y+b.height);}
 x0=Math.max(0,x0-pad);y0=Math.max(0,y0-pad);x1=Math.min(vp.width,x1+pad);y1=Math.min(vp.height,y1+pad);
 return {x:Math.round(x0),y:Math.round(y0),w:Math.round(x1-x0),h:Math.round(y1-y0)};
}
