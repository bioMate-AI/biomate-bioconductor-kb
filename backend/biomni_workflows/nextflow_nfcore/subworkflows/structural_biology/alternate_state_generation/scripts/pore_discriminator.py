import numpy as np
VDW={'C':1.7,'N':1.55,'O':1.52,'S':1.8,'H':1.2,'P':1.8}
def parse(p,chain=None):
    at=[]; ca=[]
    for l in open(p):
        if l.startswith("ATOM"):
            if chain and l[21]!=chain: continue
            if l[16] not in " A": continue
            el=l[76:78].strip() or l[12:16].strip()[0]
            xyz=[float(l[30:38]),float(l[38:46]),float(l[46:54])]
            at.append((VDW.get(el,1.7),xyz))
            if l[12:16].strip()=="CA": ca.append((int(l[22:26]),xyz))
    r=np.array([a[0] for a in at]); X=np.array([a[1] for a in at])
    return r,X,ca
def axis(X):
    c=X.mean(0); return c, np.linalg.svd(X-c)[2][0]
def pore_profile(r,X,n,c,nz=16,grid=2.0):
    z=(X-c)@n
    zb=np.linspace(np.percentile(z,3),np.percentile(z,97),nz+1)
    e1=n/np.linalg.norm(n)
    a=np.array([1,0,0.]); a=a-e1*(a@e1); a/=np.linalg.norm(a); b=np.cross(e1,a)
    prof=[]; zc=[]
    for i in range(nz):
        m=(z>=zb[i]-3)&(z<zb[i+1]+3)
        if m.sum()<6: prof.append(np.nan); zc.append((zb[i]+zb[i+1])/2); continue
        Xs=X[m]; rs=r[m]; zi=(zb[i]+zb[i+1])/2
        P=(Xs-c); u=P@a; v=P@b
        # grid search center maximizing largest empty sphere
        best=-9
        for uu in np.arange(u.min(),u.max(),grid):
            for vv in np.arange(v.min(),v.max(),grid):
                d=np.sqrt((u-uu)**2+(v-vv)**2)-rs
                rr=d.min()
                if rr>best: best=rr
        prof.append(best); zc.append(zi)
    return np.array(zc),np.array(prof)
def kabsch_fit(Pca,Qca):
    # common residues by resnum
    dq={rn:xyz for rn,xyz in Qca}
    pairs=[(np.array(xyz),np.array(dq[rn])) for rn,xyz in Pca if rn in dq]
    P=np.array([a for a,b in pairs]); Q=np.array([b for a,b in pairs])
    cP=P.mean(0);cQ=Q.mean(0);H=(P-cP).T@(Q-cQ);U,S,Vt=np.linalg.svd(H)
    d=np.sign(np.linalg.det(Vt.T@U.T));R=Vt.T@np.diag([1.,1.,d])@U.T
    return R,cP,cQ
def open_side(p,chain,ref=None,refchain=None):
    r,X,ca=parse(p,chain)
    c,n=axis(X)
    # if ref given, align this structure's axis frame to ref for shared z
    if ref:
        rr,RX,rca=parse(ref,refchain)
        R,cP,cQ=kabsch_fit(ca,rca)         # maps this->ref
        X2=(R@(X-cP).T).T+cQ
        c2,n2=axis(np.array([b for _,b in rca]))  # ref axis
        zc,prof=pore_profile(r,X2,n2,c2)
    else:
        zc,prof=pore_profile(r,X,n,c)
    # openness asymmetry: mean radius low-z third minus high-z third
    good=~np.isnan(prof)
    lo=np.nanmean(prof[zc<np.percentile(zc,33)]); hi=np.nanmean(prof[zc>np.percentile(zc,67)])
    return lo-hi, prof
# validate: within each pair, superpose outward onto inward; sign of asym must FLIP
tests=[("LAT1",("6IRS_B.pdb","B"),("7DSK_B.pdb","B")),
       ("LeuT",("3TT3.pdb","A"),("3TT1.pdb","A")),
       ("Mhp1",("2JLN.pdb","A"),("2X79.pdb","A"))]
print("within-pair (outward superposed onto inward's frame) — asym sign should FLIP inward vs outward:")
for name,(inf,inc),(ouf,ouc) in tests:
    try:
        ai,_=open_side(inf,inc)                       # inward in its own frame
        ao,_=open_side(ouf,ouc,ref=inf,refchain=inc)  # outward aligned to inward frame
        flip = (np.sign(ai)!=np.sign(ao))
        print(f"  {name:6s} inward_asym={ai:+.2f}  outward_asym(aligned)={ao:+.2f}  FLIP={flip}")
    except Exception as e:
        print(f"  {name:6s} ERR {e}")
