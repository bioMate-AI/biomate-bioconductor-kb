"""Render paper-1 figures from frozen, already aggregated results; performs no fitting.
Run on a worker: python paper1_review.py --data INPUT_DIR --out OUTPUT_DIR.
INPUT_DIR contains cluster.json, gate.json, transfer.json and sources.json.
"""
import argparse,json,hashlib
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
import numpy as np
p=argparse.ArgumentParser();p.add_argument('--data',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
sources=json.loads((a.data/'sources.json').read_text())
for name,meta in sources.items():
 assert hashlib.sha256((a.data/name).read_bytes()).hexdigest()==meta['sha256'],name
D={name:json.loads((a.data/name).read_text()) for name in sources}
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':9,'axes.titlesize':10,'axes.labelsize':9,'xtick.labelsize':8,'ytick.labelsize':8,'axes.spines.top':False,'axes.spines.right':False,'pdf.fonttype':42,'savefig.dpi':300})
blue='#0072B2';orange='#D55E00';green='#009E73';purple='#AA4499';grey='#777777'
legends={};records={}
def save(fig,name,legend,values):
 fig.savefig(a.out/(name+'.pdf'),bbox_inches='tight',metadata={'CreationDate':None})
 fig.savefig(a.out/(name+'.png'),bbox_inches='tight');plt.close(fig)
 legends[name]=legend;records[name]=values

def box(ax,x,y,w,h,text,color='#E8F2F8'):
 ax.add_patch(FancyBboxPatch((x,y),w,h,boxstyle='round,pad=0.014',facecolor=color,edgecolor='#667788',linewidth=.7))
 ax.text(x+w/2,y+h/2,text,ha='center',va='center',fontsize=9)
def arrow(ax,xy,xytext,color=grey):ax.annotate('',xy=xy,xytext=xytext,arrowprops={'arrowstyle':'->','color':color,'lw':1.2})
f,ax=plt.subplots(figsize=(7.2,4.4));ax.set_xlim(0,1);ax.set_ylim(0,1);ax.axis('off')
ax.text(0,.97,'a  Retrospective selection and learning',weight='bold',va='top')
for x,t in [(.02,'Initial measured\nlabels'),(.27,'Gradient-boosted\nmodel'),(.52,'Select from fixed\ncandidate pool'),(.77,'Reveal selected\nmeasurements')]:box(ax,x,.69,.20,.15,t)
for x in [.23,.48,.73]:arrow(ax,(x+.025,.765),(x-.012,.765))
ax.annotate('Refit after acquisition',xy=(.37,.68),xytext=(.81,.57),ha='center',fontsize=8,arrowprops={'arrowstyle':'->','connectionstyle':'angle,angleA=180,angleB=-90,rad=8','color':blue})
box(ax,.02,.37,.95,.12,'Reported permeability runs use source standardisation from all source labels.\nThese are transductive estimates; prospective bias remains unquantified.','#FFF1E8')
ax.text(0,.27,'b  Distinct questions require distinct controls',weight='bold')
box(ax,.02,.06,.29,.15,'Acquisition benefit\nLoop versus frozen fit\nand matched random')
box(ax,.355,.06,.29,.15,'Generalisation\nHeld-out ranking;\nsource-cluster uncertainty')
box(ax,.69,.06,.28,.15,'Benchmark validity\nNo-target controls;\nnull-calibrated gate')
save(f,'paper1_fig1_design','Figure 1 | Separating acquisition, generalisation and benchmark validity. a, Retrospective replay reveals measurements after selection and refits a gradient-boosted learner. The reported permeability replay nevertheless uses full-source label statistics for normalisation; it is not a demonstrated causal, revealed-label-only normalisation experiment. b, Acquisition yield, held-out ranking and benchmark validity answer different questions and are assessed with separate controls. This is a protocol schematic, not an experimental result.',{})

rows=D['cluster.json']['rows']; groups=[('gbm_aware','Chirality-aware GBM'),('gbm_blind','Chirality-blind GBM')]
def row(g,m):
 x=[r for r in rows if r['analysis']=='L7' and r['group']==g and r['regime']=='L' and r['contrast']=='loop-frozen' and r['metric']==m];assert len(x)==1;return x[0]
yields=[row(g,'yield (hits)') for g,_ in groups];ranks=[row(g,'E source-rho (within lab)') for g,_ in groups]
assert yields[0]['estimate']==47.3 and yields[0]['cluster_t']==[-53.011,147.611]
f,axs=plt.subplots(1,3,figsize=(10.4,3.6),gridspec_kw={'width_ratios':[1.3,1,1]},layout='constrained')
for i,(g,label) in enumerate(groups):
 y=1-i;r=yields[i]
 for offset,key,color,lab in [(.09,'seed_t',blue,'Seed-t interval'),(-.09,'cluster_t',orange,'Source-cluster t interval')]:
  lo,hi=r[key];axs[0].errorbar(r['estimate'],y+offset,xerr=[[r['estimate']-lo],[hi-r['estimate']]],fmt='o',ms=4,color=color,capsize=3,label=lab if i==0 else None)
 axs[1].scatter(r['estimate'],y+.09,color=blue,label='All sources' if i==0 else None)
 axs[1].scatter(r['est_without_top'],y-.09,color=orange,marker='s',label='Largest contribution subtracted' if i==0 else None)
 axs[1].text(r['estimate']+2,y+.09,f"{r['estimate']:+.1f}",fontsize=8,va='center')
 axs[1].text(r['est_without_top']+2,y-.09,f"{r['est_without_top']:+.1f}",fontsize=8,va='center')
 rr=ranks[i];lo,hi=rr['cluster_t'];axs[2].errorbar(rr['estimate'],y,xerr=[[rr['estimate']-lo],[hi-rr['estimate']]],fmt='o',color=green,capsize=3)
for ax in axs:
 ax.axvline(0,color=grey,lw=.8,ls='--');ax.set_ylim(-.5,1.5)
axs[0].set_yticks([1,0],[x[1] for x in groups]);axs[1].set_yticks([]);axs[2].set_yticks([])
axs[0].set(title='a  Yield uncertainty',xlabel='Loop − frozen fit (hits)');axs[0].legend(loc='lower center',fontsize=7,frameon=False)
axs[1].set(title='b  Source sensitivity',xlabel='Loop − frozen fit (hits)',xlim=(-3,65));axs[1].legend(loc='lower center',fontsize=7,frameon=False)
axs[2].set(title='c  Held-out ranking',xlabel='Change in within-source Spearman ρ')
save(f,'paper1_fig2_feedback','Figure 2 | Seed replication does not establish cross-source yield gain. Regime L, full-protocol replay, 10 seeds per learner. a, Loop-minus-frozen yield with 95% t intervals across seeds (blue) or source clusters (orange; 14 aware and 16 blind). b, Descriptive omission of the largest contributing source: 2020_Townsend for the aware learner (88.7% of absolute source contributions), 2021_Kelly for the blind learner (53.7%). Shares divide the absolute contribution of that source by the sum of absolute source contributions. Omission subtracts the observed contribution; it is not a rerun without that source. Omission points have no plotted uncertainty and are not independent tests. c, Full-pool loop-minus-frozen change in held-out within-source Spearman correlation, with 95% t intervals across 11 evaluable sources. Yield is measured in the acquisition pool; ranking is evaluated separately. All plotted values are read from the frozen source-cluster summary.',{'yield':yields,'ranking':ranks})

gate=D['gate.json'];cells=gate['cells'];keys=['VM2|14|None|None','V3|20|None|None','VI|25|None|None','V3|26|None|None','V3|47|None|None'];labels=['14\nM2-like','20\nthree controls','25\nI-like','26\nthree controls','47\nthree controls']
f,axs=plt.subplots(1,2,figsize=(10.2,4),gridspec_kw={'width_ratios':[1.1,1]},layout='constrained')
for j,(key,color,label) in enumerate([('reg_biased',grey,'Registered gate'),('cal_biased',blue,'Calibrated gate')]):
 for i,k in enumerate(keys):
  v=cells[k][key];mean=v['p']*100;lo,hi=np.array(v['ci'])*100
  axs[0].errorbar(i+(j-.5)*.20,mean,yerr=[[mean-lo],[hi-mean]],fmt='o',color=color,capsize=3,label=label if i==0 else None)
axs[0].axhline(10,color=orange,ls='--',lw=.8,label='10% point-rate criterion');axs[0].set_xticks(range(5),labels);axs[0].set(title='a  False alarms on clean benchmarks',ylabel='Benchmarks flagged biased (%)',xlabel='Number of families and benchmark design',ylim=(0,45));axs[0].legend(frameon=False,fontsize=7)
r=gate['real']['I']['calibrated'];features=[('C1_atomlm_typicality','Atom-LM typicality'),('C2_multiproxy_leave_fold_out','Multiproxy'),('C3_morgan_fp_leave_fold_out','Fingerprint'),('C4_censored_label','Censoring indicator'),('C5_assay_has_Ki_or_Kd','Ki/Kd assay indicator'),('o_frac','Oxygen fraction')]
for i,(k,label) in enumerate(features):axs[1].barh(5-i,abs(r['z_std'][k]),color=orange if k in r['flagged'] else blue,height=.6)
axs[1].axvline(r['q'],color=grey,ls='--');axs[1].set_yticks(range(6),[s for _,s in features][::-1]);axs[1].set(title='b  What flags analysis I?',xlabel='Absolute null-standardised control statistic');axs[1].text(.98,.98,f"Critical value {r['q']:.2f}",transform=axs[1].transAxes,ha='right',va='top',fontsize=8,bbox={'facecolor':'white','edgecolor':'none','alpha':.9,'pad':2})
save(f,'paper1_fig3_gate','Figure 3 | Calibration reduces false alarms and identifies the basis of the real-benchmark verdict. a, Registered and calibrated rules are evaluated on the same planted-valid null benchmarks (permuted real benchmark structures and synthetic family structures) within each displayed design (200 replicates at 14 families; 400 otherwise). Bars are 95% binomial intervals from the stored calibration evaluation. These matched comparison rates differ from the earlier, independent gate-positive-control experiment. Acceptance also requires an upper 95% bound no greater than 15%; it does not establish a population rate below 10%. The 14-family setting remains too weak to establish certification despite reduced false alarms. b, Absolute null-standardised statistics for selected analysis-I controls; dashed line is the calibrated critical value. Orange bars exceed the threshold: censoring, the Ki/Kd assay indicator and oxygen fraction. No primary compound-only control exceeds it. A gate verdict is not evidence of a model advantage.',{'clean_cells':{k:cells[k] for k in keys},'analysis_I':r,'n_validation_records':gate['n_records']})

t=D['transfer.json'];f,axs=plt.subplots(1,2,figsize=(10.0,4.1),layout='constrained')
models=[('nn_q3','Nearest neighbour',grey),('gp','Tanimoto GP',blue),('d_q6_l0.3','Prior + correction',green),('f0_1000','Meta-learned predictor',orange),('g_a1000_q6_l0.3','Embedding retrieval',purple)]
ks=[3,5,10,25]
for key,label,color in models:
 vals=[t['learning_curves'][key][str(k)]['hard'][0] for k in ks];axs[0].plot(ks,vals,'o-',color=color,label=label,ms=4)
axs[0].set(title='a  Ranking away from close analogues',xlabel='Revealed labels per target',ylabel='Family-equal Spearman ρ (hard stratum)',xticks=ks);axs[0].legend(frameon=False,fontsize=7)
grows=[]
for j,key in enumerate(['f0_1000','g_a1000_q6_l0.3']):
 for i,k in enumerate([3,5,10]):
  v=t['gate'][key+'|k'+str(k)];m=v['diff_hard'];lo,hi=v['ci97_5'];y=5-(j*3+i)
  axs[1].errorbar(m,y,xerr=[[m-lo],[hi-m]],fmt='o',color=orange if j==0 else purple,capsize=3);grows.append(v)
axs[1].set_yticks(range(6),['Embedding, k=10','Embedding, k=5','Embedding, k=3','Meta-learned, k=10','Meta-learned, k=5','Meta-learned, k=3']);axs[1].axvline(0,color=grey,ls='--',lw=.8);axs[1].set(title='b  Registered screening contrasts',xlabel='Hard-stratum ρ − best test baseline')
save(f,'paper1_fig4_transfer','Figure 4 | Few-label transfer remains unresolved beyond strong lookup controls. Exact-potency benchmark, test half: 86 targets in 21 families, equal weight per family. a, Descriptive hard-stratum learning curves; uncertainty is omitted from this panel for readability. b, Registered screening contrasts against the best baseline on the test half, with 97.5% family-cluster intervals at k=3,5,10. All six intervals include zero. These underpowered screening results do not establish equivalence or absence of benefit; they are distinct from the censoring-biased analysis-I classification benchmark.',{'n_test_targets':t['n_test_targets'],'n_test_families':t['n_test_families'],'contrasts':grows,'curves':{key:{str(k):t['learning_curves'][key][str(k)]['hard'] for k in ks} for key,_,_ in models}})
(a.out/'figure_legends.json').write_text(json.dumps(legends,indent=2)+'\n');(a.out/'plotted_values.json').write_text(json.dumps(records,indent=2)+'\n');(a.out/'sources.json').write_text(json.dumps(sources,indent=2)+'\n')
print('Rendered four figures from verified frozen inputs.')
