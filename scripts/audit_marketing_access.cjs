#!/usr/bin/env node
// Read-only public HTTP checks. Synthetic user agents do not verify real crawlers.
const fs = require('node:fs');
const { JSDOM } = require('../frontend/node_modules/jsdom');
async function request(url, userAgent) {
  const r = await fetch(url, { redirect:'manual', signal:AbortSignal.timeout(20000), headers:userAgent ? {'user-agent':userAgent} : {} });
  return { status:r.status, location:r.headers.get('location'), contentType:r.headers.get('content-type'), xRobotsTag:r.headers.get('x-robots-tag'), body:await r.text() };
}
function summarizeAudit(out) {
  return {
    pagesChecked:out.pages.length,
    non200:out.pages.filter(p=>p.status!==200).length,
    noindex:out.pages.filter(p=>/\bnoindex\b|\bnone\b/i.test([p.robots,p.xRobotsTag].join(' '))).length,
    missingCanonical:out.pages.filter(p=>!p.canonical).length,
    syntheticAgentRequests:out.syntheticAgents.length,
    syntheticAgentBlocked:out.syntheticAgents.filter(p=>p.status!==200||p.challenge).length
  };
}
async function main() {
  const robots = await request('https://biomate.ai/robots.txt');
  const sitemap = await request('https://biomate.ai/sitemap.xml');
  const urls = [...sitemap.body.matchAll(/<loc>([^<]+)<\/loc>/g)].map(m => m[1]);
  if (!urls.length || urls.some(u => new URL(u).hostname !== 'biomate.ai')) throw Error('Unexpected sitemap contents');
  const out = { capturedAt:new Date().toISOString(), scope:'Public HTTP responses, not webmaster indexing or verified crawler IPs', robots:{status:robots.status,text:robots.body}, sitemap:{status:sitemap.status,urls:urls.length}, variants:[], syntheticAgents:[], pages:[] };
  for (const url of ['http://biomate.ai/','http://www.biomate.ai/','https://www.biomate.ai/','https://biomate.ai/','https://biomate.ai/index.html']) {
    const r = await request(url); const d = new JSDOM(r.body).window.document;
    out.variants.push({url,status:r.status,location:r.location,canonical:d.querySelector('link[rel=canonical]')?.getAttribute('href') || null});
  }
  for (const agent of ['Googlebot','bingbot','OAI-SearchBot','ChatGPT-User','Claude-SearchBot','Claude-User','PerplexityBot','Perplexity-User']) {
    for (const pathname of ['/','/drug-discovery.html','/benchmarks.html','/robots.txt']) {
      const r = await request('https://biomate.ai'+pathname,agent);
      out.syntheticAgents.push({agent,path:pathname,status:r.status,contentType:r.contentType,xRobotsTag:r.xRobotsTag,challenge:/cf-chl-|Just a moment\.\.\.|verify you are human/i.test(r.body)});
    }
  }
  let next = 0;
  await Promise.all(Array.from({length:5},async()=>{
    while(next<urls.length) {
      const url=urls[next++];
      try {
        const r=await request(url),d=new JSDOM(r.body).window.document;
        out.pages.push({url,status:r.status,location:r.location,canonical:d.querySelector('link[rel=canonical]')?.getAttribute('href') || null,robots:d.querySelector('meta[name=robots]')?.getAttribute('content') || null,xRobotsTag:r.xRobotsTag,h1:d.querySelectorAll('h1').length,title:d.title});
      } catch(e) {out.pages.push({url,error:e.message});}
    }
  }));
  out.pages.sort((a,b)=>a.url.localeCompare(b.url));
  out.summary=summarizeAudit(out);
  if (process.argv[2]) fs.writeFileSync(process.argv[2],JSON.stringify(out,null,2)+'\n');
  console.log(JSON.stringify({...out.summary,variants:out.variants},null,2));
}
if (require.main === module) main().catch(e=>{console.error(e.message);process.exitCode=1;});
module.exports = {summarizeAudit};
