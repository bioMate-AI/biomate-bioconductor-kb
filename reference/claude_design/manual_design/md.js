// Compact markdown → HTML for the manual. Supports: headings, paragraphs, nested lists, blockquotes
// (typed callouts), GFM tables, fenced code, hr, images-as-figures, links, emphasis, inline code,
// status tokens ([~]/[x]/[ ] and ✅🔧⏳🗺️). Hooks: opts.link(href)->{href,ext}|null, opts.img(src)->url.
(function(){
const esc=s=>s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
const TOK={"✅":["ok","Verified","已核验"],"🔧":["fix","Corrected","已更正"],"⏳":["pend","Pending","待复核"],"🗺️":["road","Roadmap","路线图"],"🗺":["road","Roadmap","路线图"],"⚠️":["warn","Stale","已过时"]};
const BOX={"~":["pend","Drafted","已起草"],"x":["ok","Verified","已核验"]," ":["none","Not started","未开始"]};
function slug(t){return t.toLowerCase().replace(/<[^>]+>/g,"").replace(/&[a-z]+;/g,"").replace(/[^\p{L}\p{N}\s-]/gu,"").trim().replace(/\s+/g,"-").slice(0,80)||"section";}
function inline(s,o){
 const keep=[];const K=h=>"\u0000"+(keep.push(h)-1)+"\u0001";
 s=s.replace(/`([^`]+)`/g,(_,c)=>K("<code>"+esc(c)+"</code>"));
 s=s.replace(/!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g,(_,a,src)=>K('<img src="'+esc(o.img(src))+'" alt="'+esc(a)+'" loading="lazy">'));
 s=s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g,(_,txt,href)=>{const r=o.link(href);const t=inline(txt,o);
  if(!r)return K('<span class="deadlink">'+t+'</span>');
  return K('<a href="'+esc(r.href)+'"'+(r.ext?' target="_blank" rel="noopener"':'')+'>'+t+(r.ext?'<span class="ext">↗</span>':'')+'</a>');});
 s=esc(s);
 s=s.replace(/^\[(~|x| )\](?=\s)/,(_,k)=>{const b=BOX[k];return '<span class="tok '+b[0]+'">'+b[o.zh?2:1]+'</span>';});
 s=s.replace(/\*\*([^*]+?)\*\*/g,"<strong>$1</strong>").replace(/__([^_]+?)__/g,"<strong>$1</strong>");
 s=s.replace(/(^|[^*\w])\*([^*\s][^*]*?)\*(?!\*)/g,"$1<em>$2</em>").replace(/(^|[\s(])_([^_\s][^_]*?)_(?=[\s).,;:!?]|$)/g,"$1<em>$2</em>");
 s=s.replace(/(✅|🔧|⏳|🗺️|🗺|⚠️)/g,m=>{const t=TOK[m];return '<span class="tok '+t[0]+'">'+t[o.zh?2:1]+'</span>';});
 s=s.replace(/ {2,}$/,"<br>");
 return s.replace(/\u0000(\d+)\u0001/g,(_,i)=>keep[+i]);
}
const isList=l=>/^\s*([-*+]|\d+[.)])\s+/.test(l);
const C=(s,m)=>window.mdClean?window.mdClean(s,m):s;
const isTableSep=l=>/^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/.test(l);
function cells(l){l=l.trim().replace(/^\|/,"").replace(/\|$/,"");const out=[];let cur="",tick=false;for(const ch of l){if(ch==="`")tick=!tick;if(ch==="|"&&!tick){out.push(cur);cur="";}else cur+=ch;}out.push(cur);return out.map(c=>c.trim());}
function cjkJoin(s){return s.replace(/([\u2e80-\u9fff\u3000-\u303f\uff00-\uffef）】」』，。：；！？、])\n\s*([\u2e80-\u9fff\u3000-\u303f\uff00-\uffef（【「『*])/g,"$1$2").replace(/([\u2e80-\u9fff\u3000-\u303f\uff00-\uffef])\n\s*(\*\*)/g,"$1$2");}
function callout(first){
 const m=first.match(/^\*\*([^*]+)\*\*/);const k=(m?m[1]:"").toLowerCase();
 if(/pitfall|warning|caveat|hold|陷阱|误区|注意|警告|小心/.test(k))return "rule";
 if(/qc gate|gate|qc 关卡|关卡/.test(k))return "qc";
 if(/tip|提示|小贴士|技巧/.test(k))return "tip";
 if(/in one sentence|一句话/.test(k))return "key";
 return "note";
}
function blocks(lines,o){
 let h="",i=0;
 while(i<lines.length){
  let l=lines[i];
  if(!l.trim()){i++;continue;}
  let m;
  if(m=l.match(/^@@CAP(\d+)@@$/)){o.cap=o.caps[+m[1]];i++;continue;}
  if(/^\s*```/.test(l)){const lang=l.trim().slice(3);let b=[];i++;while(i<lines.length&&!/^\s*```/.test(lines[i]))b.push(lines[i++]);i++;h+='<pre class="code"'+(lang?' data-lang="'+esc(lang)+'"':'')+'><code>'+esc(b.join("\n"))+'</code></pre>';continue;}
  if(m=l.match(/^(#{1,6})\s+(.*?)\s*#*$/)){const n=m[1].length,txt=inline(C(m[2],"head"),o);if(n===1){o.h1=o.h1||m[2];i++;continue;}const id=o.uid(slug(txt));o.heads.push({n,id,t:txt.replace(/<[^>]+>/g,"")});h+='<h'+n+' id="'+id+'"><a class="anchor" href="'+o.self(id)+'" aria-label="Link to section">#</a>'+txt+'</h'+n+'>';i++;continue;}
  if(/^\s*([-*_])(\s*\1){2,}\s*$/.test(l)){h+="<hr>";i++;continue;}
  if(/^\s*\|/.test(l)&&i+1<lines.length&&isTableSep(lines[i+1])){const head=cells(l);i+=2;let rows=[];while(i<lines.length&&/^\s*\|/.test(lines[i]))rows.push(cells(lines[i++]).map(c=>C(c,"cell")));
   const keep=head.map((_,j)=>rows.some(r=>(r[j]||"").trim()));const H=head.filter((_,j)=>keep[j]);const R=rows.map(r=>r.filter((_,j)=>keep[j])).filter(r=>r.some(c=>c.trim()));
   if(!R.length)continue;
   h+='<div class="tbl"><table><thead><tr>'+H.map(c=>"<th>"+inline(c,o)+"</th>").join("")+'</tr></thead><tbody>'+R.map(r=>"<tr>"+H.map((_,j)=>"<td>"+inline(r[j]||"",o)+"</td>").join("")+"</tr>").join("")+'</tbody></table></div>';continue;}
  if(/^\s*>/.test(l)){let b=[];while(i<lines.length&&/^\s*>/.test(lines[i]))b.push(lines[i++].replace(/^\s*>\s?/,""));
   const first=(b.find(x=>x.trim())||"").trim();const typ=callout(first);
   if(b.every(x=>!x.trim()||/^".*"$|^“.*”$|^「.*」$/.test(x.trim()))&&/^["“「]/.test(first)){h+='<blockquote class="ask">'+blocks(b,o)+'</blockquote>';continue;}
   const inner=blocks(b,o);if(!inner.replace(/^<p><strong>[^<]*<\/strong>/,"").replace(/<[^>]+>/g,"").trim())continue;
   h+='<aside class="callout '+typ+'">'+inner+'</aside>';continue;}
  if(isList(l)){
   const base=l.match(/^\s*/)[0].length;const ordered=/^\s*\d/.test(l);let items=[],cur=null;
   while(i<lines.length){const x=lines[i];
    if(!x.trim()){const nx=lines[i+1];if(nx!==undefined&&nx.trim()&&(nx.match(/^\s*/)[0].length>base||(isList(nx)&&nx.match(/^\s*/)[0].length===base))){if(cur)cur.push("");i++;continue;}break;}
    const ind=x.match(/^\s*/)[0].length;
    if(ind===base&&isList(x)){mm=x.match(/^\s*([-*+]|\d+[.)])\s+/);cur=[x.slice(mm[0].length)];cur.w=mm[0].length;items.push(cur);i++;continue;}
    if(ind>base&&cur){cur.push(x.slice(Math.min(ind,cur.w)));i++;continue;}
    if(ind<=base&&!isList(x)&&cur&&!/^\s*(#|>|\||```)/.test(x)&&lines[i-1]&&lines[i-1].trim()){cur.push(x.trim());i++;continue;}
    break;}
   const tag=ordered?"ol":"ul";const st=ordered?parseInt(l.trim(),10):1;
   const lis=items.map(it=>{const inner=it.length===1?inline(C(it[0],"para"),o):blocks(it,o).replace(/^<p>([\s\S]*?)<\/p>/,"$1");return inner.replace(/<[^>]+>/g,"").trim()?"<li>"+inner+"</li>":"";}).join("");
   if(lis)h+="<"+tag+(ordered&&st>1?' start="'+st+'"':"")+">"+lis+"</"+tag+">";continue;}
  let p=[];if(/^\s*!\[[^\]]*\]\([^)\s]+\)\s*$/.test(l)){p.push(l);i++;}else while(i<lines.length&&lines[i].trim()&&!/^\s*(#{1,6}\s|>|```|\|)/.test(lines[i])&&!(p.length&&isList(lines[i]))&&!/^\s*([-*_])(\s*\1){2,}\s*$/.test(lines[i]))p.push(lines[i++]);
  if(!p.length){p.push(lines[i++]);}
  const raw=cjkJoin(p.join("\n").trim());
  const imgOnly=raw.match(/^!\[([^\]]*)\]\(([^)\s]+)\)$/);
  if(imgOnly){let cap="";let j=i;while(j<lines.length&&!lines[j].trim())j++;
   const nx=(lines[j]||"").trim();const capm=nx.match(/^\*([^*].*)\*$/)||nx.match(/^_([^_].*)_$/);
   if(capm){let c=[nx];let k=j+1;while(k<lines.length&&lines[k].trim()&&!/^\s*(#|>|\||!\[)/.test(lines[k]))c.push(lines[k++].trim());const all=cjkJoin(c.join("\n")).replace(/\n/g," ").trim();const mm2=all.match(/^\*([\s\S]*)\*$/)||all.match(/^_([\s\S]*)_$/);if(mm2){cap=mm2[1];i=k;}}
   h+=o.figure(o.img(imgOnly[2]),imgOnly[1],cap?inline(C(cap,"cell"),o):inline(imgOnly[1],o),o.nextId(),takeCap(o));continue;}
  if(/^\*?[（(]\s*(figure to add|待补图|图待补)/i.test(raw)){const t=raw.replace(/^\*|\*$/g,"").replace(/^[（(]\s*/,"").replace(/[)）]\s*$/,"").replace(/^(figure to add|待补图|图待补)\s*[:：]?\s*/i,"");h+=o.pending(inline(C(t,"cell"),o),o.nextId(),takeCap(o));continue;}
  if(/^[_*](verification|companion technical references|核验|配套技术参考|技术参考)/i.test(raw))continue;
  const pc=C(raw.replace(/\n/g," "),"para");if(!pc)continue;
  h+="<p>"+inline(pc,o)+"</p>";
 }
 return h;
}
let mm;
function takeCap(o){const c=o.cap||"";o.cap=null;return c;}
window.renderMarkdown=function(src,o){
 o.caps=[];o.cap=null;let fig=0;const pre=o.idPrefix||"F";o.nextId=()=>pre+"-"+String(++fig).padStart(2,"0");
 src=src.replace(/\r/g,"").replace(/<!--\s*CAPTURE([\s\S]*?)-->/g,(_,s)=>"\n\n@@CAP"+(o.caps.push(s.replace(/\s+/g," ").trim())-1)+"@@\n\n").replace(/<!--[\s\S]*?-->/g,"");
 const used={};o.heads=[];o.uid=s=>{used[s]=(used[s]||0)+1;return used[s]>1?s+"-"+used[s]:s;};
 const html=blocks(src.split("\n"),o);
 return {html,heads:o.heads,h1:o.h1};
};
window.mdSlug=slug;
})();
