import json
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
P=Path(__file__).resolve().parent
r=json.loads((P/'results.json').read_text())['equal_donor_mse']
old=json.loads((P.parent/'downstream_only_evaluation/results.json').read_text())['summary_equal_weight_donors']
names=['No change','Target/condition ridge','Baseline-state ridge','Guide-shrunk target mean']
values=[r['no_change'],old['target_condition']['excluding_perturbed_readout']['mse'],old['baseline_state']['excluding_perturbed_readout']['mse'],r['guide_shrunk_target_condition_mean']]
fig,ax=plt.subplots(figsize=(8,4.7),layout='constrained');colors=['#7e8790','#8fa8c0','#8fa8c0','#237c72']
ax.barh(names,values,color=colors,height=.6)
for i,v in enumerate(values):ax.text(v+.0001,i,f'{v:.5f}',va='center',fontsize=10)
ax.axvline(r['no_change'],color='#444444',ls='--',lw=1);ax.invert_yaxis();ax.set_xlim(0,.018);ax.set_xlabel('Equal-donor downstream MSE (lower is better)');ax.set_title('Exact original benchmark: guide shrinkage lowers MSE',loc='left',pad=14)
ax.spines[['top','right']].set_visible(False)
fig.text(.02,-.035,'Reused 16-target / four-donor development panel. Same 132-gene labels and masks.\n1.27% reduction versus no-change; no significance or model-promotion claim.',fontsize=9,color='#555555')
fig.savefig(P/'benchmark_comparison.png',dpi=160,bbox_inches='tight')
