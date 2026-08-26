import sqlite3, json, collections
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
DB='backend/database/galaxy_ai_tools.db'; OUT='docs/figures/anatomy'
c=sqlite3.connect(DB)
TEAL='#1b9e8a'; GREY='#9aa0a6'

# An-1 workflows by domain (top 15)
dom=c.execute("SELECT domain, COUNT(*) n FROM workflows GROUP BY domain ORDER BY n DESC LIMIT 15").fetchall()
labels=[d for d,_ in dom][::-1]; vals=[n for _,n in dom][::-1]
fig,ax=plt.subplots(figsize=(7,5)); ax.barh(labels,vals,color=TEAL)
for i,v in enumerate(vals): ax.text(v+8,i,str(v),va='center',fontsize=8)
ax.set_xlabel('workflows'); ax.set_title('BioMate workflows by domain (top 15 of 39; n=4,057)')
plt.tight_layout(); plt.savefig(f'{OUT}/fig_An1_domains.png',dpi=200); plt.close()

# An-2 steps per workflow distribution (clip at 20)
sc=[min(r[0],20) for r in c.execute("SELECT step_count FROM workflows WHERE step_count>0")]
fig,ax=plt.subplots(figsize=(7,4)); ax.hist(sc,bins=range(1,22),color=TEAL,edgecolor='white')
ax.axvline(3,color='#d33',ls='--',lw=1,label='median = 3'); ax.set_xlabel('steps per workflow (clipped at 20; max=222)')
ax.set_ylabel('workflows'); ax.set_title('Step-depth distribution (n=4,032; mean 4.9)'); ax.legend()
plt.tight_layout(); plt.savefig(f'{OUT}/fig_An2_steps.png',dpi=200); plt.close()

# An-3 enrichment coverage
def pct(sql): return 100*c.execute(sql).fetchone()[0]/12301
cats=[('sci-context v1',pct("SELECT COUNT(*) FROM tools WHERE scientific_context IS NOT NULL AND scientific_context!=''")),
      ('parameters',pct("SELECT COUNT(*) FROM tools WHERE parameters IS NOT NULL AND parameters!=''")),
      ('citations',pct("SELECT COUNT(*) FROM tools WHERE citations IS NOT NULL AND citations!=''")),
      ('usage guide',pct("SELECT COUNT(*) FROM tools WHERE usage_guide IS NOT NULL AND usage_guide!=''")),
      ('sci-context v2 (deep)',pct("SELECT COUNT(*) FROM tools WHERE scientific_context_v2 IS NOT NULL AND scientific_context_v2!=''"))]
labels=[a for a,_ in cats]; vals=[b for _,b in cats]
cols=[TEAL if v>=50 else GREY for v in vals]
fig,ax=plt.subplots(figsize=(7,4)); ax.bar(labels,vals,color=cols)
for i,v in enumerate(vals): ax.text(i,v+1,f'{v:.0f}%',ha='center',fontsize=9)
ax.set_ylabel('% of 12,301 tools'); ax.set_ylim(0,100); ax.set_title('Tool-library enrichment coverage (v2 = the frontier gap)')
plt.xticks(rotation=15,ha='right'); plt.tight_layout(); plt.savefig(f'{OUT}/fig_An3_enrichment.png',dpi=200); plt.close()
print("wrote 3 figures to",OUT)
