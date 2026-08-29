#!/usr/bin/env python3
"""Assemble data_v2.jsonl from harvest/*.jsonl + the original v1 items. Dedup by accession
(harvest record wins — richer fields). Unified schema + fine-grained modality + method map."""
import json, glob, os
HERE=os.path.dirname(os.path.abspath(__file__))

METHOD={
 "microarray":"limma","bulk_rnaseq":"DESeq2","scrna_seq":"scran_seurat_scanpy","snrna_seq":"scran_seurat_scanpy",
 "spatial_transcriptomics":"squidpy_seurat_spatial","chip_seq":"MACS2","atac_seq":"MACS2","scatac_seq":"ArchR_Signac",
 "cutandrun":"SEACR_MACS2","methylation_array":"minfi","wgbs":"Bismark_methylKit","wgs":"GATK_DeepVariant","wes":"GATK",
 "target_panel":"panel_variant_calling","hic":"Juicer_cooler","ribo_seq":"riboWaltz","small_rna":"miRDeep2",
 "clip_seq":"PureCLIP","amplicon_16s":"QIIME2_DADA2","metagenomics":"MetaPhlAn_HUMAnN","ms_proteomics_dda":"MaxQuant_quantms",
 "ms_proteomics_dia":"DIANN_quantms","ms_proteomics_tmt":"quantms_TMT","metabolomics":"XCMS_MZmine","structure":"structure_analysis",
 "protein_seq":"sequence_function","multiome":"WNN_MuData",
}
# v1 coarse -> fine remap for the original items
V1_REMAP={"wgs_wes":None, "ms_proteomics":None}  # resolved per-accession below
V1_ACC_FIX={"NA12878":"wgs","HCC1395":"wes","PXD001819":"ms_proteomics_dda","PXD005486":"ms_proteomics_tmt","PXD004684":"ms_proteomics_dia"}

items={}  # accession -> record
def add(acc, modality, method, metadata, repo, organism, platform, design, source, provenance):
    acc=acc.strip()
    items[acc]={"id":acc,"accession":acc,"modality":modality,"method":method,"metadata":metadata,
                "repository":repo,"organism":organism,"platform":platform,"design_contrast":design,
                "source":source,"provenance":provenance}

# 1) harvested (fine labels) — these win
nharv=0
for f in sorted(glob.glob(os.path.join(HERE,"harvest","*.jsonl"))):
    for l in open(f):
        l=l.strip()
        if not l: continue
        try: r=json.loads(l)
        except: continue
        if not r.get("verified", True): continue
        mod=r.get("modality"); 
        if mod not in METHOD: 
            print("  WARN unknown modality (skipped):", mod, r.get("accession")); continue
        add(r["accession"], mod, r.get("analysis_method") or METHOD[mod], r.get("modality_evidence",""),
            r.get("repository",""), r.get("organism",""), r.get("platform",""), r.get("design_contrast",""),
            r.get("source_citation",""), "harvested")
        nharv+=1

# 2) original v1 items — only if accession not already present
norig=0
for l in open(os.path.join(HERE,"data.jsonl")):
    r=json.loads(l); acc=r["accession"]
    if acc in items: continue
    mod=r["modality"]
    if acc in V1_ACC_FIX: mod=V1_ACC_FIX[acc]
    elif mod=="wgs_wes": mod="wgs"
    elif mod=="ms_proteomics": mod="ms_proteomics_dda"
    if mod not in METHOD: continue
    add(acc, mod, METHOD[mod], r.get("metadata",""), "", "", "", "", r.get("source_role",""), "v1")
    norig+=1

out=os.path.join(HERE,"data_v2.jsonl")
with open(out,"w") as f:
    for acc in sorted(items):
        f.write(json.dumps(items[acc])+"\n")
from collections import Counter
c=Counter(v["modality"] for v in items.values())
print(f"harvested={nharv}  original-kept={norig}  TOTAL={len(items)}  modalities={len(c)}")
print("wrote", out)
for m,n in sorted(c.items()): print(f"  {m:<26} {n}")
