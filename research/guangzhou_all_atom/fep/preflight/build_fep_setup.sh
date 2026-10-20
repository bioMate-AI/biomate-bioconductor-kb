#!/bin/bash
# build_fep_setup.sh — OFFLINE (CPU, no GPU/mdrun) build of the avb6 FEP CONTROL-EDGE inputs.
# Control edge ONLY: Trivehexin-mono (YRGDLAYPK, Tyr1/Tyr7) -> avebehexin (FRGDLAFPK), i.e. Y1F+Y7F.
# Builds BOTH legs (complex + solvent) as pmx A->B dual-state hybrids, solvates+ionizes, grompp em.tpr
# as the readiness proof, stages everything to DEST/in/, and writes in/FEP_INPUTS_READY LAST iff all OK.
# The GPU Batch job then runs mdrun only (em->nvt->npt->per-lambda HREX) — NO pmx needed there.
#
# Expects: micromamba env /opt/fepenv with gromacs + pmx (develop) already created by the launcher's
# user-data, and these env vars: SRC (precursor in/ prefix), DEST (FEP inputs out prefix), REGION.
# Inputs pulled from SRC: receptor.pdb peptide.pdb mn_cada.pdb cada_mn.itp mdp/.
# NOTE: NO `set -u` here. The micromamba/conda shell hook + `micromamba activate` below
# reference unbound vars (e.g. $PS1); under `set -u` that is a FATAL shell abort that `|| true`
# cannot catch, so the script died on env activation before the first STAGE marker (the
# i-00f9a406 / i-02906edd silent code=1 exits). Var refs here are already ${VAR:-}-guarded, and
# dropping -u means a real failure now PRINTS its marker instead of aborting blind. Keep pipefail.
set -o pipefail
cd /work 2>/dev/null || { mkdir -p /work && cd /work; }
echo "FEPBUILD_START $(date -u 2>/dev/null) host=$(hostname 2>/dev/null) pwd=$(pwd)"
_on_exit(){ ec=$?; echo "FEPBUILD_EXIT code=$ec";
  # RECURSIVE tar from /work so per-leg solvent/*.out + complex/*.out (the real pdb2gmx/grompp errors)
  # are captured; exclude the big pulled inputs (in/) and any tarball.
  if [ -n "${DEST:-}" ]; then (cd /work 2>/dev/null && tar czf /tmp/fepbuild_logs.tgz --exclude='./in' --exclude='*.tgz' . 2>/dev/null);
    aws s3 cp /tmp/fepbuild_logs.tgz "${DEST}/fepbuild_logs.tgz" --region "${REGION:-us-west-2}" >/dev/null 2>&1 \
      && echo "LOGS_UPLOADED ${DEST}/fepbuild_logs.tgz" || echo "LOGS_UPLOAD_FAIL"; fi; }
trap _on_exit EXIT
R(){ echo "STAGE_$1:$2  ${3:-}"; }
GFATAL(){ grep -A8 -iE 'fatal error' "$1" 2>/dev/null | head -10 | tr '\n' '|'; }   # full GROMACS fatal block on one line

# ---- env ----
eval "$(/opt/micromamba shell hook -s bash 2>/dev/null)" 2>/dev/null || true
micromamba activate /opt/fepenv 2>/dev/null || true
command -v gmx >/dev/null 2>&1 || source /opt/fepenv/bin/GMXRC 2>/dev/null || true
GV=$(gmx --version 2>&1 | grep -i "GROMACS version" | head -1); [ -n "$GV" ] && R A OK "$GV" || { R A FAIL "no gmx in env"; exit 0; }
PY=$(command -v python3)
# pmx: install as an EXPLICIT marked stage (install -> import -> mutff), each emitting a marker and
# exiting 0 cleanly on failure so the trap+markers always diagnose it (never a bare exit).
# --no-build-isolation: pmx pins setuptools~=46.0.0 in build-system.requires, which conflicts with the
# env's modern setuptools under pip's strict build isolation (the i-02906edd failure). --no-build-isolation
# bypasses that pin and builds with the env's own setuptools/wheel/numpy + c-compiler. VERIFIED working.
if ! $PY -c "import pmx" >/dev/null 2>&1; then
  # Force an older C standard for pmx's C extension: the conda-forge gcc defaults to C23, where
  # `bool` is a reserved keyword, so pmx's legacy `typedef int bool;` (pmx.h) fails to compile
  # ("'bool' cannot be defined via 'typedef'", the i-0e19d6d4 failure). -std=gnu11 restores the
  # pre-C23 behaviour where that typedef is legal. VERIFIED error+fix from the real compile log.
  export CFLAGS="-std=gnu11 ${CFLAGS:-}"
  pip install --no-build-isolation "git+https://github.com/deGrootLab/pmx.git@develop" > pmx_install.out 2>&1 || true
fi
if $PY -c "import pmx" >/dev/null 2>&1; then
  R pmx OK "pmx $($PY -c 'import pmx;print(getattr(pmx,"__version__","?"))' 2>/dev/null)"
else
  R pmx FAIL "import pmx failed: $(tail -4 pmx_install.out 2>/dev/null | tr '\n' '|')"; exit 0
fi
MUTFF=$($PY -c "import pmx,os;print(os.path.join(os.path.dirname(pmx.__file__),'data','mutff'))" 2>/dev/null)
if [ -n "$MUTFF" ] && [ -d "$MUTFF" ]; then R mutff OK "$MUTFF"; else R mutff FAIL "pmx/mutff dir missing"; exit 0; fi
# pmx CLI entry point: this pmx (develop) has NO pmx.__main__, so `python -m pmx` fails. The real CLI is
# the console script `pmx` (= pmx.scripts.cli:entry_point) next to the env python; module fallback if absent.
PMXCLI="$(dirname "$PY")/pmx"; [ -x "$PMXCLI" ] || PMXCLI="$PY -m pmx.scripts.cli"
R pmxcli OK "$PMXCLI"
export GMXLIB="$MUTFF"        # so pdb2gmx/grompp find charmm36m-mut.ff + ions + spc216
FF=charmm36m-mut

# ---- inputs ----
mkdir -p in && aws s3 cp "$SRC" in --recursive --region "${REGION:-us-west-2}" >/dev/null 2>&1
for f in receptor.pdb peptide.pdb mn_cada.pdb cada_mn.itp; do cp "in/$f" . 2>/dev/null; done
[ -f peptide.pdb ] && [ -f receptor.pdb ] && [ -f cada_mn.itp ] && R C OK "precursors present" || { R C FAIL "missing precursors"; exit 0; }
# CYCLIC-PEPTIDE handling: pmx gentop crashes mutating a residue at the chain terminus of a cyclic peptide
# (alchemy.py _find_predefined_dihedrals fetches resid i-1/i+1; for the arbitrary terminus that neighbor
# does not exist -> "resid 0 not found"). pmx's own cyclic path (scripts/build_cyclic_top.py, from
# gmx_makecyclictop) extends the chain with dummy terminal copies + post-adds the wrap-around bonded terms;
# it is NOT integrated with the mutation/gentop path. Canonical, non-hack fix: the cyclic numbering origin
# is arbitrary, so rotate it (start at orig resid 3=GLY) -> Tyr1->new8, Tyr7->new5 (BOTH interior), and the
# cut falls on the orig 2-3 amide (a non-mutated junction). gentop's i+-1 then resolves; the head-to-tail
# bond is re-added post-gentop across the (non-mutated) cut. All other amides (incl. orig 9-1) become
# ordinary sequential bonds pdb2gmx builds. Coordinates unchanged (bound pose preserved); only resSeq order.
python3 - <<'PYEOF' > rotate.out 2>&1 || true
order=[3,4,5,6,7,8,9,1,2]
byres={}
for ln in open('peptide.pdb'):
    if ln.startswith(('ATOM','HETATM')):
        rs=int(ln[22:26]); byres.setdefault(rs,[]).append(ln.rstrip('\n'))
out=[]
for newid,orig in enumerate(order,1):
    for ln in byres[orig]: out.append(ln[:22]+('%4d'%newid)+ln[26:])
open('peptide_rot.pdb','w').write('\n'.join(out)+'\nEND\n')
import sys; print('ROT_OK sites new5=%s new8=%s'%(out and [l[17:20].strip() for l in out if int(l[22:26])==5][0], [l[17:20].strip() for l in out if int(l[22:26])==8][0]))
PYEOF
if [ -f peptide_rot.pdb ]; then R rotate OK "$(cat rotate.out)"; else R rotate FAIL "$(tail -3 rotate.out)"; exit 0; fi
printf "P 5 PHE\nP 8 PHE\n" > muts.txt   # Tyr sites after cyclic-origin rotation (orig Tyr1->new8, Tyr7->new5)

add_cyclization(){ # $1=topfile : inject head-to-tail C(last)-N(first) amide bond into the peptide moleculetype
  $PY - "$1" <<'PYEOF'
import re,sys
f=sys.argv[1]; t=open(f).read()
# operate on the LAST [ atoms ] block's molecule (the peptide, smallest). Find all moleculetype atom blocks.
blocks=[m for m in re.finditer(r'\[ atoms \](.*?)(?=\n\[)', t, re.S)]
if not blocks: print("CYC_NO_ATOMS"); sys.exit()
blk=blocks[-1]  # peptide is the last-defined moleculetype in the merged top
ids=[]
for ln in blk.group(1).splitlines():
    p=ln.split()
    if len(p)>=5 and p[0].isdigit(): ids.append((int(p[0]),p[4]))
firstN=next((i for i,an in ids if an=='N'),None)
lastC=None
for i,an in ids:
    if an=='C': lastC=i
if firstN and lastC and lastC>firstN:
    # add bond under the peptide's own [ bonds ]; find the [ bonds ] that follows this [ atoms ]
    tail=t[blk.end():]
    nb=re.search(r'\[ bonds \]\n',tail)
    if nb:
        pos=blk.end()+nb.end()
        t=t[:pos]+("%5d %5d     1 ; HEAD-TO-TAIL CYCLIZATION (C_last-N_first)\n"%(lastC,firstN))+t[pos:]
        open(f,'w').write(t); print("CYC_ADDED lastC=%d firstN=%d"%(lastC,firstN))
    else: print("CYC_NO_BONDS_BLOCK")
else: print("CYC_INDEX_FAIL firstN=%s lastC=%s"%(firstN,lastC))
PYEOF
}

build_leg(){ # $1=legname(complex|solvent)  $2=input.pdb  $3=withMn(yes/no)
  leg=$1; inp=$2; withmn=$3; W=$leg; mkdir -p $W; cp "$inp" $W/start.pdb; (cd $W
   export GMXLIB="$MUTFF"
   # canonical pmx mutation-FEP order: pdb2gmx WT (hydrogenate) -> pmx mutate -> pdb2gmx hybrid (NO -ignh:
   # keep pmx's placed hybrid-residue atoms; -ignh would strip+regenerate H from an hdb that does not know
   # the hybrid residue -> the HYBRID_PDB2GMX_FAIL fatal) -> pmx gentop (fill B-states).
   # 1. pdb2gmx WT -> hydrogenated conf.pdb + topol.top  (reduced CYS, no -ss; -ignh ok: input pose lacks H)
   gmx pdb2gmx -f start.pdb -o conf.pdb -p topol.top -i posre.itp -ff $FF -water tip3p -ignh < /dev/null > ${leg}_pdb2gmx.out 2>&1 || { echo "${leg}:PDB2GMX_FAIL $(GFATAL ${leg}_pdb2gmx.out)"; exit 11; }
   # 2. pmx mutate on the hydrogenated conf.pdb; --ref start.pdb maps pdb2gmx re-chain/renumber back to the
   #    original chains so "P 1 PHE / P 7 PHE" targets ONLY the peptide (not receptor res 1/7).
   $PMXCLI mutate -f conf.pdb -o hybrid.pdb -ff $FF --script ../muts.txt --ref start.pdb > ${leg}_mutate.out 2>&1 || { echo "${leg}:PMX_MUTATE_FAIL $(tail -6 ${leg}_mutate.out | tr '\n' '|')"; exit 12; }
   # 3. pdb2gmx the hybrid structure -> hybrid topology (NO -ignh)
   gmx pdb2gmx -f hybrid.pdb -o hconf.pdb -p htop.top -i hposre.itp -ff $FF -water tip3p < /dev/null > ${leg}_hpdb2gmx.out 2>&1 || { echo "${leg}:HYBRID_PDB2GMX_FAIL $(GFATAL ${leg}_hpdb2gmx.out)"; exit 13; }
   # 4. pmx gentop -> fill B-states
   $PMXCLI gentop -p htop.top -o fep.top -ff $FF > ${leg}_gentop.out 2>&1 || { echo "${leg}:GENTOP_FAIL $(tail -6 ${leg}_gentop.out | tr '\n' '|')"; exit 14; }
  ) ; r=$?; [ $r -ne 0 ] && { R ${leg}_build FAIL "see ${leg}/*.out (rc=$r)"; return $r; }
  # cyclization on the hybrid fep.top
  add_cyclization "$W/fep.top" > $W/${leg}_cyc.out 2>&1
  (cd $W
   export GMXLIB="$MUTFF"
   CONF=hconf.pdb
   if [ "$withmn" = yes ]; then
     # add CaDA Mn: include cada_mn.itp (atomtypes+MN2) after ff include; append MN2 x3 to [molecules]; add 21 Mn atoms to gro
     cp ../cada_mn.itp .
     python3 - <<'PYEOF' > ${leg}_mn.out 2>&1 || { echo MN_MERGE_FAIL; exit 21; }
import re
t=open('fep.top').read().splitlines(); out=[]; done=False
for ln in t:
    out.append(ln)
    if ln.strip().startswith('#include') and not done:
        out.append('#include "cada_mn.itp"'); done=True
s='\n'.join(out)
s=re.sub(r'(\[ molecules \].*)$', r'\1\nMN2                 3', s, flags=re.S)
open('fep.top','w').write(s); print('MN_TOP_OK')
PYEOF
   fi
   # box + solvate + ions
   gmx editconf -f $CONF -o box.gro -c -d 1.2 -bt dodecahedron > ${leg}_editconf.out 2>&1 || { echo "EDITCONF_FAIL $(GFATAL ${leg}_editconf.out)"; exit 22; }
   if [ "$withmn" = yes ]; then
     # append the 21 CaDA-Mn atoms to the (protein+peptide) box gro BEFORE solvation
     python3 - <<'PYEOF' > ${leg}_mngro.out 2>&1 || { echo MN_GRO_FAIL; exit 23; }
g=open('box.gro').read().splitlines(); n=int(g[1]); body=g[2:2+n]; box=g[2+n]
mn=[]; resn=1; idx=0
for ln in open('mn_cada.pdb'):
    if ln.startswith('HETATM'):
        x=float(ln[30:38])/10;y=float(ln[38:46])/10;z=float(ln[46:54])/10;nm=ln[12:16].strip()
        if nm=='MN' and idx!=0: resn+=1
        mn.append('%5d%-5s%5s%5d%8.3f%8.3f%8.3f'%(resn,'MN2',nm,(n+len(mn)+1)%100000,x,y,z)); idx+=1
open('box.gro','w').write(g[0]+'\n%d\n'%(n+len(mn))+'\n'.join(body+mn)+'\n'+box+'\n'); print('MNGRO_OK +%d'%len(mn))
PYEOF
     cp mn_cada.pdb . 2>/dev/null
   fi
   gmx solvate -cp box.gro -cs spc216.gro -p fep.top -o solv.gro > ${leg}_solvate.out 2>&1 || { echo "SOLVATE_FAIL $(GFATAL ${leg}_solvate.out)"; exit 24; }
   # ions: grompp a dummy em then genion
   gmx grompp -f ../in/mdp/em.mdp -c solv.gro -p fep.top -o ions.tpr -maxwarn 20 > ${leg}_ionsgrompp.out 2>&1 || { echo "IONS_GROMPP_FAIL $(GFATAL ${leg}_ionsgrompp.out)"; exit 25; }
   echo SOL | gmx genion -s ions.tpr -o ionized.gro -p fep.top -pname NA -nname CL -neutral -conc 0.15 > ${leg}_genion.out 2>&1 || { echo "GENION_FAIL $(GFATAL ${leg}_genion.out)"; exit 26; }
   # readiness proof: grompp em on the final ionized system
   gmx grompp -f ../in/mdp/em.mdp -c ionized.gro -p fep.top -o em.tpr -maxwarn 20 > ${leg}_emgrompp.out 2>&1 || { echo "EM_GROMPP_FAIL $(GFATAL ${leg}_emgrompp.out)"; exit 27; }
   echo "${leg}_EM_TPR_OK atoms=$(gmx dump -s em.tpr 2>/dev/null | grep -m1 'natoms' | tr -dc '0-9')"
  ) ; r=$?
  if [ $r -eq 0 ] && [ -f $W/em.tpr ]; then R ${leg}_system OK "$W/em.tpr built (hybrid+solvate+0.15M)"; return 0
  else R ${leg}_system FAIL "see $W/*.out (rc=$r); markers: $(grep -hoE '[A-Z_]+_FAIL' $W/*.out 2>/dev/null|tr '\n' ',')"; return $r; fi
}

# ---- SOLVENT leg (hybrid peptide alone) ----
build_leg solvent peptide_rot.pdb no ; SOLV=$?

# ---- COMPLEX leg (receptor + peptide together via pdb2gmx; CaDA-Mn added post-hoc) ----
# combine receptor + peptide into one PDB so pdb2gmx builds a single consistent topology (chains A,B,P)
grep -hE '^(ATOM|TER)' receptor.pdb > complex_noMn.pdb
echo "TER" >> complex_noMn.pdb
grep -hE '^(ATOM|HETATM)' peptide_rot.pdb >> complex_noMn.pdb   # cyclic-origin-rotated peptide (sites interior)
echo "END" >> complex_noMn.pdb
build_leg complex complex_noMn.pdb yes ; CPLX=$?

# ---- stage FEP inputs + sentinel (LAST, only if BOTH legs built em.tpr) ----
if [ "$SOLV" -eq 0 ] && [ "$CPLX" -eq 0 ]; then
  for leg in solvent complex; do
    aws s3 cp $leg "${DEST}/in/$leg" --recursive --region "${REGION:-us-west-2}" \
      --exclude '*' --include 'fep.top' --include 'ionized.gro' --include 'em.tpr' --include '*.itp' >/dev/null 2>&1
  done
  aws s3 cp in/mdp "${DEST}/in/mdp" --recursive --region "${REGION:-us-west-2}" >/dev/null 2>&1
  aws s3 cp cada_mn.itp "${DEST}/in/cada_mn.itp" --region "${REGION:-us-west-2}" >/dev/null 2>&1
  echo "control-edge Y1F+Y7F; both legs; $(date -u)" > FEP_INPUTS_READY
  aws s3 cp FEP_INPUTS_READY "${DEST}/in/FEP_INPUTS_READY" --region "${REGION:-us-west-2}" >/dev/null 2>&1 \
    && R READY OK "FEP_INPUTS_READY staged -> ${DEST}/in/" || R READY FAIL "sentinel upload failed"
else
  R READY SKIP "legs incomplete (solvent rc=$SOLV complex rc=$CPLX); NO sentinel written"
fi
echo "FEPBUILD_STAGES_DONE"
