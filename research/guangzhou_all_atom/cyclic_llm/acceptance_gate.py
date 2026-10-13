"""Operationalizes acceptance_criteria.yaml (Candidate Design Requirements v1.0) as a computable gate.
Sequence-evaluable αvβ6 hard gates H1-H5 + H4 flanks + H5 single-Lys chelator handle + H8 FTO-genus flag.
Docking-dependent H6/H7 are returned 'pending' (need docking vs αvβ6 + counter-integrins w/ controls)."""
import re
from cyclic_llm.knowledge_liability_flags import parse_helm

def avb6_gate(helm):
    res,mods,scaf=parse_helm(helm); seq="".join(res)
    g={}
    w=seq+seq[:6] if scaf['cyclic'] else seq
    g['H1_RGD']= 'RGD' in w                                   # contiguous R-G-D (Asp L-config: not [dD])
    g['H2_RGDL']= 'RGDL' in w
    has_dpro=any(m['d_stereo'] and res[i]=='P' for i,m in enumerate(mods))
    has_nme=any(m['n_methyl'] for m in mods)
    g['H3_turn_nmethyl']= has_dpro and has_nme
    # flanks: P1 = residue immediately BEFORE the R of RGDL; P7 = residue immediately before the D-Pro
    g['H4_aromatic_flanks']=None
    m=re.search(r'(.)RGDL',w)   # P1 before R
    p1=m.group(1) if m else None
    # P7 = residue before the dPro; find dPro index
    dpi=next((i for i,mm in enumerate(mods) if mm['d_stereo'] and res[i]=='P'),None)
    p7=res[dpi-1] if dpi else None
    g['_P1']=p1; g['_P7']=p7
    g['H4_aromatic_flanks']= (p1 in {'F','Y','W'}) and (p7 in {'F','Y','W'})
    # H5 single chelator handle: cyclic + exactly one primary-amine side chain (one Lys; Arg guanidinium doesn't count)
    nlys=sum(1 for r in res if r=='K')
    g['_n_lys']=nlys
    g['H5_single_handle']= scaf['cyclic'] and nlys==1
    # H8 FTO genus flag: matches cyclo([FYW]-RGDL-[any]-[FYW]-dPro-NMe*)
    g['H8_fto_genus_flag']= bool(p1 in {'F','Y','W'} and p7 in {'F','Y','W'} and has_dpro and has_nme and 'RGDL' in w)
    hard=[g['H1_RGD'],g['H2_RGDL'],g['H3_turn_nmethyl'],g['H4_aromatic_flanks'],g['H5_single_handle']]
    g['PASS_H1_H5']= all(hard)
    g['H6_H7_docking']='pending (needs αvβ6 + αvβ8/αvβ3/αvβ5/α5β1 docking vs controls in-batch)'
    return g
