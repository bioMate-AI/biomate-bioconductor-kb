from pathlib import Path
from html import escape
out=Path(__file__).resolve().parent
def start(title,subtitle):
 return [f'''<svg xmlns="http://www.w3.org/2000/svg" width="1400" height="960" viewBox="0 0 1400 960" role="img" aria-label="{escape(title)}"><defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto"><path d="M0,0 L0,6 L8,3 z" fill="#526477"/></marker></defs><rect width="1400" height="960" fill="white"/><style>text{{font-family:Arial,Helvetica,sans-serif;fill:#162b40}} .title{{font-size:32px;font-weight:700}} .sub{{font-size:20px;fill:#526477}} .head{{font-size:22px;font-weight:700}} .body{{font-size:20px}} .small{{font-size:18px;fill:#526477}}</style><text x="50" y="57" class="title">{escape(title)}</text><text x="50" y="94" class="sub">{escape(subtitle)}</text>''']
def box(s,x,y,w,h,title,lines,color='#edf4fa'):
 s.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{color}" stroke="#b6c6d4"/>')
 s.append(f'<text x="{x+20}" y="{y+36}" class="head">{escape(title)}</text>')
 for i,line in enumerate(lines): s.append(f'<text x="{x+20}" y="{y+73+29*i}" class="body">{escape(line)}</text>')
def arrow(s,x1,y1,x2,y2):s.append(f'<path d="M{x1},{y1} L{x2},{y2}" stroke="#526477" fill="none" stroke-width="2.5" marker-end="url(#arrow)"/>')
def label(s,x,y,t):s.append(f'<text x="{x}" y="{y}" class="small">{escape(t)}</text>')
def save(s,name): (out/name).write_text('\n'.join(s)+ '</svg>\n')
s=start('Figure 1 | One evidence base, two knowledge interfaces','Study architecture: knowledge conditions proposals; new scores provide feedback.')
box(s,50,135,370,190,'a  Source-qualified evidence',['Statement and source passage','Scaffold, assay and conditions','Comparator and measured endpoint','Evidence ID and source hash'])
box(s,490,135,400,190,'b  Frozen evidence catalogue',['Semantic review and scope checks','Source / compound exclusions','Explicit parent-to-evidence mapping','Unresolved entries excluded'])
box(s,960,135,390,190,'Common task inputs',['Same starting chemical pool','Same hard constraints','Same allowable evidence','Same evaluation budget'])
arrow(s,420,228,490,228);arrow(s,890,228,960,228)
box(s,80,395,590,225,'c  IH-LM: computational knowledge',['Applicability predicates select chemical parents','Selected parent supplies a SMILES prefix','Rule-constrained atom-level decoder proposes','Preference updates use newly obtained scores'],'#e8f3ef')
box(s,730,395,590,225,'d  Claude / GPT / Gemini: textual knowledge',['Scoped evidence enters a structured prompt','Model selects a parent or proposes a molecule','Chemical validity is checked independently','New scores return through the prompt history'],'#f0edfa')
arrow(s,690,325,375,395);arrow(s,690,325,1025,395)
box(s,80,695,590,170,'e  Shared validation and accounting',['Check chemistry, stereochemistry and rules','Count failures, duplicates, calls, time and cost','Score eligible proposals with the train oracle'])
box(s,730,695,590,170,'f  Independent evaluation',['Stop verifier guides stopping only','Held-out assessment follows final selection','No held-out outcomes in evidence or feedback'])
arrow(s,375,620,375,695);arrow(s,1025,620,500,695);arrow(s,670,780,730,780)
label(s,50,915,'Knowledge conditions proposals; feedback updates the policy. Held-out outcomes remain isolated.')
save(s,'method_fig1_knowledge_interfaces.svg')
s=start('Figure 2 | Knowledge utility and generative performance','Matched knowledge conditions distinguish evidence utility from complete-system performance.')
box(s,50,135,635,175,'a  Fixed-pool decision experiment',['Identical eligible molecules and hidden measurements','Select candidates in rounds; reveal selected outcomes','Primary contrast: knowledge on minus knowledge off'])
box(s,715,135,635,175,'b  Generative system experiment',['Shared starting set, rules and oracle-call budget','Different generators and knowledge interfaces','Primary contrast: full system versus strong baselines'])
for x,title,lines,color in [(50,'Knowledge off',['Chemical context retained','No mined-evidence intervention'],'#edf4fa'),(490,'Applicable knowledge',['Reviewed scope matches task','Same underlying evidence'],'#e8f3ef'),(930,'Inapplicable evidence',['Matched topic and packet size','Scope mismatch is explicit'],'#fff2e5')]:
 box(s,x,385,420,155,title,lines,color)
label(s,50,355,'c  Apply all three conditions within IH-LM, Claude, GPT and Gemini')
box(s,50,610,635,190,'d  Evaluate learning and transfer',['Fixed pool: measured yield and selection efficiency','Generation: train-score AUC versus oracle calls','Separate endpoint: final top-10 held-out score','Within-system paired effects and uncertainty'])
box(s,715,610,635,190,'e  Evaluate knowledge use and efficiency',['Scope rejection and evidence-to-proposal trace','Validity, uniqueness and structural diversity','Failures, latency, tokens and monetary cost','Seeds repeat runs; tasks/sources define transfer'])
label(s,320,580,'All three conditions are assessed on both outcome groups below')
label(s,50,855,'Interpretation: better optimisation scores do not establish better biological activity or permeability.')
label(s,50,887,'Final held-out scores and train-objective AUC are separate endpoints, with task-specific effect margins.')
label(s,50,919,'Cross-system contrasts compare complete systems; within-system contrasts isolate the knowledge intervention.')
save(s,'method_fig2_comparison_design.svg')
print('Created two vector study-design figures.')
