# GWAS Catalog Local Index

This directory contains a local GWAS Catalog snapshot for fast, rate-limit-free variant lookups.

## Files

- `gwas-catalog-download-associations-alt-full.tsv` (653MB) — Full GWAS Catalog associations (gitignored)
- `rsid_index.pkl` (varies) — Pre-built rsID lookup index (gitignored)
- `associations.zip` (60MB) — Compressed download (gitignored)

## Regenerating

```bash
# Download latest associations
wget -O associations.zip \
  "https://ftp.ebi.ac.uk/pub/databases/gwas/releases/latest/gwas-catalog-associations_ontology-annotated-full.zip"
unzip associations.zip

# Build rsID index (run once, takes ~15 seconds)
python -c "
import pandas as pd, pickle, re

df = pd.read_csv(
    'gwas-catalog-download-associations-alt-full.tsv',
    sep='\t',
    usecols=['DISEASE/TRAIT', 'SNPS', 'P-VALUE', 'PVALUE_MLOG', 'MAPPED_TRAIT'],
    dtype=str, low_memory=False
)
df['pval_f'] = pd.to_numeric(df['P-VALUE'], errors='coerce')
df['pval_mlog'] = pd.to_numeric(df['PVALUE_MLOG'], errors='coerce')

index = {}
for _, row in df.iterrows():
    snps_str = str(row['SNPS'])
    rsids = [s.strip() for s in snps_str.replace(';', ' ').replace('x', ' ').split() if s.startswith('rs')]
    entry = (str(row['DISEASE/TRAIT']), row['pval_f'], row['pval_mlog'], str(row['MAPPED_TRAIT']))
    for rsid in rsids:
        index.setdefault(rsid, []).append(entry)

with open('rsid_index.pkl', 'wb') as f:
    pickle.dump(index, f, protocol=4)
print(f'Index: {len(index):,} rsIDs')
"
```

## Notes

- ~1.1M association rows, 423K unique rsIDs
- Loaded once per process, shared across parallel threads
- Fallback to live GWAS Catalog API if index unavailable
