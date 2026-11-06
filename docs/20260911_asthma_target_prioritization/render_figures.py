"""Reproduce both figures from the saved lane JSONs; no network or inferred data."""
from pathlib import Path
import os
os.environ.setdefault('MPLCONFIGDIR', '/tmp/biomate-asthma-matplotlib')
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap, BoundaryNorm
from matplotlib.ticker import MultipleLocator
import numpy as np

ROOT = Path(__file__).resolve().parent
TARGETS = ['TSLP', 'IL33', 'IL1RL1']
LANES = [('genetics','Human genetics / GWAS'), ('cohorts','Cohort replication / PheWAS'),
         ('disease_context','Target–disease context'), ('clinical','Clinical / regulatory'),
         ('literature','Literature / public datasets'), ('expression','Expression / cell context')]
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':11,
                     'axes.spines.top':False,'axes.spines.right':False})

def save(fig, stem):
    for ext in ('png','svg','pdf'):
        fig.savefig(ROOT/f'{stem}.{ext}',dpi=180,facecolor=fig.get_facecolor())
    plt.close(fig)

def gwas():
    rows=json.loads((ROOT/'genetics.json').read_text())['variants']
    fig,ax=plt.subplots(figsize=(11.5,6.5)); fig.patch.set_facecolor('#f8fafc');ax.set_facecolor('#f8fafc')
    for y,row,color in zip([2,1,0],rows,['#087f8c','#6554a4','#b5682d']):
        x=-np.log10(row['p']); ax.barh(y,x,height=.48,color=color)
        ax.text(x+.65,y,f"{row['p']:.0e}",va='center',fontweight='bold',fontsize=12)
    ax.set_yticks([2,1,0],[f"{v['target']}\n{v['rsid']}" for v in rows]);ax.tick_params(axis='y',length=0,pad=10)
    ax.set_xlim(0,50);ax.set_ylim(-.65,2.7);ax.set_xlabel('Asthma association strength  (−log₁₀ P)',labelpad=10)
    ax.axvline(7.30103,color='#64748b',linestyle='--',linewidth=1)
    ax.text(7.8,2.54,'P = 5 × 10⁻⁸',color='#64748b',fontsize=10)
    ax.xaxis.set_major_locator(MultipleLocator(10));ax.set_axisbelow(True);ax.grid(axis='x',color='#e2e8f0')
    fig.text(.08,.94,'Asthma-linked lead variants',fontsize=23,fontweight='bold',color='#102f40')
    fig.text(.08,.885,'One shared study: Million Veteran Program • Verma et al., 2024 • GCST90480249',fontsize=12,color='#475569')
    fig.text(.08,.145,'Selected catalog associations—not proven causal variants or therapeutic rankings.',fontsize=11,fontweight='bold',color='#334155')
    fig.text(.08,.083,'IL1RL1 locus is also mapped to IL18R1. P-values reflect association and sample size;\nallele directions and effect-scale caveats are retained in genetics.json.',fontsize=10,color='#475569',linespacing=1.5)
    fig.text(.08,.023,'Source: GWAS Catalog associations 226258978 / 226259178 / 226258966 • Retrieved 11 Sep 2026',fontsize=9,color='#64748b')
    fig.subplots_adjust(left=.2,right=.94,bottom=.25,top=.8);save(fig,'gwas_summary')

def heatmap():
    matrix=[]
    for name,label in LANES:
        data=json.loads((ROOT/f'{name}.json').read_text())
        row=data.get('scores') or {t:data['targets'][t]['score'] for t in TARGETS}
        vals=[row[t] for t in TARGETS]
        assert all(isinstance(x,(int,float)) and 1<=x<=5 for x in vals), (name,vals)
        matrix.append(vals)
    matrix=np.array(matrix)
    cmap=ListedColormap(['#eef2f6','#d0e5eb','#93c5d1','#368fa3','#075569'])
    fig,ax=plt.subplots(figsize=(11.5,7.2));fig.patch.set_facecolor('#f8fafc');ax.set_facecolor('#f8fafc')
    im=ax.imshow(matrix,cmap=cmap,norm=BoundaryNorm([.5,1.5,2.5,3.5,4.5,5.5],5),aspect='auto')
    ax.set_xticks(range(3),TARGETS,fontsize=14,fontweight='bold');ax.xaxis.tick_top();ax.tick_params(axis='x',pad=14,length=0)
    ax.set_yticks(range(6),[label for _,label in LANES],fontsize=12);ax.tick_params(axis='y',length=0,pad=12)
    ax.set_xticks(np.arange(-.5,3,1),minor=True);ax.set_yticks(np.arange(-.5,6,1),minor=True)
    ax.grid(which='minor',color='#f8fafc',linewidth=5);ax.tick_params(which='minor',bottom=False,left=False)
    for spine in ax.spines.values():spine.set_visible(False)
    for i in range(6):
        for j in range(3):
            ax.text(j,i,str(int(matrix[i,j])),ha='center',va='center',fontsize=23,fontweight='bold',
                    color='white' if matrix[i,j]>=4 else '#173746')
    fig.text(.065,.94,'Asthma target prioritization',fontsize=24,fontweight='bold',color='#102f40')
    fig.text(.065,.89,'Six evidence lanes • Analyst scores, 1–5 • Direct asthma separated from adjacent atopy',fontsize=11.5,color='#475569')
    cax=fig.add_axes([.48,.145,.4,.027]);cb=fig.colorbar(im,cax=cax,orientation='horizontal',ticks=[1,2,3,4,5]);cb.outline.set_visible(False)
    cb.ax.tick_params(length=0,labelsize=10)
    fig.text(.065,.14,'1  Limited     →     5  Strongest within lane',fontsize=10,color='#475569')
    fig.text(.065,.072,'Scores are ordinal judgments, not approval probabilities. Lanes share underlying studies;\nthe final rank is evidence-led, without summing correlated sources. See each lane report for access gaps.',fontsize=10,color='#475569',linespacing=1.5)
    fig.text(.065,.021,'Life Science Research plugin • Source payloads and scoring rationales retained • 11 Sep 2026',fontsize=9,color='#64748b')
    fig.subplots_adjust(left=.36,right=.92,bottom=.24,top=.78);save(fig,'prioritization_heatmap')
    (ROOT/'score_matrix.json').write_text(json.dumps({'targets':TARGETS,'lanes':[n for n,_ in LANES],
        'scores':matrix.tolist(),'rank':['TSLP','IL33','IL1RL1'],
        'ranking_scope':'Strength of asthma target validation, not commercial novelty or patient treatment selection',
        'scoring':'Ordinal reviewer assessment; correlated lanes are not summed'},indent=2))

if __name__=='__main__':
    gwas();heatmap()
