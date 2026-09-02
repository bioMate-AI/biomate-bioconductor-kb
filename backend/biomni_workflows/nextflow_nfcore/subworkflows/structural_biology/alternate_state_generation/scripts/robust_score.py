#!/usr/bin/env python3
"""
Robust model scorer — aligns ANY model to her inward structure by SEQUENCE (not residue number),
then runs the validated pore discriminator. Immune to per-chain renumbering (OpenMM/ProMod3),
full-length AF2 models (1-506), and the drifted cryo-EM numbering. Use for every candidate.

  python3 robust_score.py <model.pdb> [modelchain]
"""
import sys, numpy as np, importlib.util
AA3={'ALA':'A','ARG':'R','ASN':'N','ASP':'D','CYS':'C','GLN':'Q','GLU':'E','GLY':'G','HIS':'H',
'ILE':'I','LEU':'L','LYS':'K','MET':'M','PHE':'F','PRO':'P','SER':'S','THR':'T','TRP':'W','TYR':'Y','VAL':'V','MSE':'M'}
REF="snat2_cryoem_inward.pdb"

def ca_seq(p,chain=None):
    o=[];seq=[]
    for l in open(p):
        if l.startswith("ATOM") and l[12:16].strip()=="CA" and l[16] in " A":
            if chain and l[21]!=chain: continue
            r=l[17:20].strip()
            if r in AA3: o.append((l[21],int(l[22:26]))); seq.append(AA3[r])
    return o,"".join(seq)
def nw(a,b):
    n,m=len(a),len(b);G=-1;S=np.zeros((n+1,m+1));T=np.zeros((n+1,m+1),int)
    S[:,0]=np.arange(n+1)*G;S[0,:]=np.arange(m+1)*G
    for i in range(1,n+1):
        ai=a[i-1]
        for j in range(1,m+1):
            d=S[i-1,j-1]+(1 if ai==b[j-1] else -1);u=S[i-1,j]+G;le=S[i,j-1]+G
            if d>=u and d>=le:S[i,j]=d;T[i,j]=0
            elif u>=le:S[i,j]=u;T[i,j]=1
            else:S[i,j]=le;T[i,j]=2
    i,j=n,m;pr=[]
    while i>0 and j>0:
        if T[i,j]==0:
            if a[i-1]==b[j-1]: pr.append((i-1,j-1))
            i-=1;j-=1
        elif T[i,j]==1:i-=1
        else:j-=1
    return pr[::-1]

def remap_to_ref(model,chain=None):
    """rewrite model residues with her numbering via sequence alignment -> temp pdb path"""
    mo,ms=ca_seq(model,chain); ro,rs=ca_seq(REF)
    pr=nw(ms,rs)                                   # model idx -> ref idx
    m2ref={ mo[i][1]:ro[j][1] for i,j in pr }      # model resnum -> her resnum (aligned only)
    mchain=mo[0][0] if mo else "A"
    out=[]
    for l in open(model):
        if l.startswith(("ATOM","HETATM")):
            if chain and l[21]!=chain: continue
            try: rn=int(l[22:26])
            except: continue
            if rn in m2ref: out.append(l[:21]+"A"+("%4d"%m2ref[rn])+l[26:])
    tmp=model+".refnum.pdb"; open(tmp,"w").writelines(out)
    return tmp, len(pr)

if __name__=="__main__":
    model=sys.argv[1]; chain=sys.argv[2] if len(sys.argv)>2 else None
    spec=importlib.util.spec_from_file_location("pd","pore_discriminator.py"); pd=importlib.util.module_from_spec(spec)
    try: spec.loader.exec_module(pd)
    except Exception: pass
    tmp,naln=remap_to_ref(model,chain)
    ai,_=pd.open_side(REF,"A")
    ac,_=pd.open_side(tmp,"A",ref=REF,refchain="A")
    flipped=bool(np.sign(ai)!=np.sign(ac))
    print(f"{model}: aligned {naln} res | her={ai:+.2f} model={ac:+.2f} pore_flipped={flipped}")
