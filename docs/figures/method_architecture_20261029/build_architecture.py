"""Render a source-audited architecture schematic; no model execution or data analysis."""
from pathlib import Path
from html import escape
import math
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parent
W,H,S=1800,1540,2
im=Image.new('RGB',(W*S,H*S),'white'); d=ImageDraw.Draw(im)
svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">', '<rect width="1800" height="1540" fill="white"/>']
C={'ink':'#183146','gray':'#536a7b','line':'#8495a2','blue':'#edf4fa','green':'#eaf6ed','amber':'#fff4df','purple':'#f2edfa'}
def text(x,y,s,size=24,bold=False,color=None):
 color=color or C['ink']; font=ImageFont.truetype(('/System/Library/Fonts/Supplemental/Arial Bold.ttf' if bold else '/System/Library/Fonts/Supplemental/Arial Unicode.ttf'),size*S)
 d.text((x*S,y*S),s,font=font,fill=color,anchor='ls')
 svg.append(f'<text x="{x}" y="{y}" font-family="Arial, sans-serif" font-size="{size}" font-weight="{700 if bold else 400}" fill="{color}">{escape(s)}</text>')
def box(x,y,w,h,fill='blue',stroke=None):
 fill=C.get(fill,fill); stroke=stroke or C['line']
 d.rounded_rectangle((x*S,y*S,(x+w)*S,(y+h)*S),radius=12*S,fill=fill,outline=stroke,width=2*S)
 svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')
def arrow(points,color=None):
 color=color or C['gray']; p=[(x*S,y*S) for x,y in points];d.line(p,fill=color,width=3*S)
 x,y=points[-1];px,py=points[-2];a=math.atan2(y-py,x-px);sz=11
 tip=[(x,y),(x-sz*math.cos(a)+5*math.sin(a),y-sz*math.sin(a)-5*math.cos(a)),(x-sz*math.cos(a)-5*math.sin(a),y-sz*math.sin(a)+5*math.cos(a))]
 d.polygon([(i*S,j*S) for i,j in tip],fill=color)
 svg.append('<polyline points="'+' '.join(f'{x},{y}' for x,y in points)+f'" fill="none" stroke="{color}" stroke-width="3"/>')
 svg.append('<polygon points="'+' '.join(f'{x},{y}' for x,y in tip)+f'" fill="{color}"/>')
def lines(x,y,seq,size=24,step=32):
 for j,s in enumerate(seq):text(x,y+j*step,s,size)
text(45,53,'IH-LM: computational knowledge conditioning and constrained adaptation',35,True)
text(45,91,'Architecture and information flow. Symbols denote model components; experimental values are specified separately.',24,color=C['gray'])
# A
box(30,120,1740,270,'#fafcfd')
text(55,156,'a  Fixed evidence memory and shared chemical input',28,True)
box(55,180,410,170,'purple');text(75,216,'Reviewed evidence catalogue K',25,True)
lines(75,249,['Source lineage + quotation + scope','Explicit learned-conditioning approval','Frozen molecular + typed features'],22,30)
box(525,180,550,170,'purple');text(545,216,'Scope masks and learned projection',25,True)
lines(545,249,['Match task, assay, scaffold, closure and solvent','Fixed raw memory K; learned projection Z = P(K)','Null slot + evidence slots; padding is masked'],22,30)
box(1135,180,610,170,'blue');text(1155,216,'Chemical parent → token prefix c',25,True)
lines(1155,249,['Reviewed parent map; selection is a separate factor','Tokenise SMILES; retain a parent prefix','Preference candidates share prefix and memory'],22,30)
arrow([(465,265),(525,265)])
# B
box(30,420,1740,650,'#fafcfd');text(55,458,'b  Autoregressive decoder and symbolic constraint interface',28,True)
arrow([(800,350),(800,405),(575,405),(575,500)])
arrow([(1440,350),(1440,395),(170,395),(170,500)])
# high-level row
box(55,500,245,130,'blue');text(75,535,'Tokens c, y<t',25,True);lines(75,570,['Embedding E','Hidden state h⁰'],23,30)
box(360,500,430,130,'blue');text(380,535,'L causal decoder blocks',25,True);lines(380,570,['Self-attention → evidence bridge','Pre-norm gated MLP + residual'],23,30)
box(850,500,330,130,'blue');text(870,535,'Final RMSNorm',25,True);lines(870,570,['Language-model head','Token logits zθ ∈ R^|V|'],23,30)
box(1240,500,505,130,'amber');text(1260,535,'Masked categorical distribution',25,True);lines(1260,570,['Softmax over admitted tokens only','Sample y[t]; update prefix and rule state'],22,30)
for a,b in [(300,360),(790,850),(1180,1240)]:arrow([(a,565),(b,565)])
# insets
box(55,685,535,300,'blue');text(75,722,'At each selected bridge layer',25,True)
lines(75,760,['h′ = h + causal self-attention(RMSNorm(h))','Qe = LN(h′) WQe;  Ke = Z WKe;  Ve = Z WVe','a = softmax(Qe Ke^T / √dh + Me) Ve','h″ = h′ + a WOe','hnext = h″ + MLP(RMSNorm(h″))','WOe starts at zero; Me masks padded slots','Evidence is fixed across the candidate group'],22,30)
box(625,685,555,300,'green');text(645,722,'Policy and frozen reference branches',25,True)
lines(645,763,['WQ,V = W⁰Q,V + (α/r) AB','Train: LoRA A, B + projector + evidence bridge','Freeze: backbone, embeddings and LM head','Reference: LoRA off + initial frozen bridge','Reference projector is independently frozen','Both branches consume identical raw memory'],22,35)
box(1240,685,505,300,'amber');text(1260,722,'Prefix-state rule automaton',25,True)
lines(1260,760,['s[t] = update(s[t−1], y[t−1])','Prefix-admissibility mask m[t](v) ∈ {0,1}','Optional admitted soft potential b[t](v)','ℓ[t](v) = zθ[t](v)/τ + b[t](v)','pθ,C(v) ∝ m[t](v) exp[ℓ[t](v)]','EOS requires an exact molecular-rule check'],22,33)
arrow([(1490,685),(1490,630)])
text(60,1024,'The same mask, temperature and admitted soft potential define sampling and training likelihoods.',24,True)
text(60,1052,'Completion tokens include EOS; prefix tokens condition the policy but are not preference-loss targets.',22,color=C['gray'])
# C
box(30,1100,1740,395,'#fafcfd');text(55,1138,'c  Preference adaptation and separated evaluation channels',28,True)
box(55,1165,390,195,'blue');text(75,1202,'Completed molecules',25,True)
lines(75,1238,['Chemical validation and deduplication','Training oracle → ranked candidates','Pair (y⁺, y⁻): same prefix and memory','No successful completion: no pair'],22,32)
box(505,1165,720,195,'green');text(525,1202,'Masked sequence likelihood and DPO',25,True)
lines(525,1238,['log πθ,C(y|c,K) = Σ_t log pθ,C(y[t]|c,K,y<t)','Δθ = log πθ,C(y⁺|c,K) − log πθ,C(y⁻|c,K)','LDPO = −log σ[β(Δθ − Δref)]','Backpropagate to LoRA + projector + bridge'],24,32)
arrow([(445,1260),(505,1260)])
box(1285,1165,460,195,'#f2f4f6');text(1305,1202,'Evaluation has separate access',25,True)
lines(1305,1238,['Stop verifier: stopping decision only','Final held-out: final selected molecules','Neither supplies preference labels','No held-out gradient or parent update'],22,32)
text(55,1402,'Feedback loop: generated candidates → training-oracle scores → preference pairs → policy update.',24,True)
text(55,1440,'Matched comparisons: bridge off / null memory / qualified evidence. Parent selection is an independent factor.',23)
text(55,1472,'The diagram describes the implemented architecture; scientific gains and full-checkpoint acceptance remain unmeasured.',23)
svg.append('</svg>')
(ROOT/'method_architecture.svg').write_text('\n'.join(svg))
im.save(ROOT/'method_architecture.png')
print(ROOT/'method_architecture.png')
