#!/bin/bash
# preflight_in_container.sh — full-complex grompp preflight for the avb6 FEP control edge.
# Runs INSIDE gromacs-cuda:2024-cu12. Inputs staged in /work/in/:
#   receptor.pdb, peptide.pdb, mn_cada.pdb (prepped offline), cada_mn.itp, mdp/
# Continue-on-error: each stage prints STAGE_<x>:OK or STAGE_<x>:FAIL <msg>; a SUMMARY prints at the end.
# No GPU. grompp only (no mdrun). Writes full log to S3 if $S3LOG set.
# NOTE: the gromacs-cuda:2024-cu12 image ENTRYPOINT is ['/bin/bash','-c'] (confirmed via ECR config).
# The launcher therefore invokes this with `--entrypoint /bin/bash ... -lc 'bash /work/preflight_in_container.sh'`.
# CANARY FIRST (before set -u) so a silent/intercepted container can NEVER again masquerade as a clean 0-marker run:
cd /work 2>/dev/null || true
echo "PREFLIGHT_START $(date -u 2>/dev/null) host=$(hostname 2>/dev/null) pwd=$(pwd) gmx=$(command -v gmx 2>/dev/null || echo none)"
# Unconditional diagnostics on ANY exit (early or clean): always ship logs.tgz + an exit-code marker.
_on_exit(){ ec=$?; echo "PREFLIGHT_EXIT code=$ec"; if [ -n "${S3LOG:-}" ]; then tar czf /tmp/logs.tgz *.out *.top *.gro *.pdb 2>/dev/null; aws s3 cp /tmp/logs.tgz "$S3LOG" >/dev/null 2>&1 && echo "LOGS_UPLOADED $S3LOG" || echo "LOGS_UPLOAD_FAIL"; fi; }
trap _on_exit EXIT
set -uo pipefail
R(){ echo "STAGE_$1:$2  ${3:-}"; }

# ---- A: gmx + python ----
if ! command -v gmx >/dev/null 2>&1; then
  for G in /usr/local/gromacs/bin/GMXRC /gromacs/bin/GMXRC; do [ -f "$G" ] && source "$G"; done
  export PATH=$PATH:/usr/local/gromacs/bin
fi
VER=$(gmx --version 2>&1 | grep -i "GROMACS version" | head -1)
[ -n "$VER" ] && R A OK "$VER" || { R A FAIL "no gmx on PATH"; echo SUMMARY_END; exit 0; }
# prep is done OFFLINE now (gemmi runs on the author's box; PDBs staged in in/), so the container
# needs NO gemmi/numpy. Inline python in stages D/F uses stdlib only (re, file IO).
PY=$(command -v python3 || command -v python || echo "")
[ -n "$PY" ] && R Apy OK "python=$PY (prep done offline; in-container python uses stdlib only)" \
             || R Apy WARN "no python3 (stages D/F inline python + pmx will be skipped)"
# probe for an existing conda/mamba env (an image built for structural work may already have tools)
if command -v conda >/dev/null 2>&1; then echo "CONDA_PRESENT: $(conda env list 2>/dev/null | tr '\n' ';')"; fi

# ---- A2: pmx handled OFFLINE (prior run proved the image python has NO pip -> cannot install pmx here) ----
# The Y1F/Y7F hybrid needs GROMACS (pdb2gmx to add backbone H) AND pmx together; container has gmx but no
# pip/pmx. So the hybrid is a separate offline step (recipe in the review doc) and is NON-GATING for the
# D/F grompp validations. If a hybrid was pre-staged in in/, stage E will verify it.
PMX=OFFLINE
R A2pmx NOTE "pmx not installable in-container (image python has no pip, confirmed); hybrid built offline, non-gating"

# ---- B: CHARMM36m ff ----
FF=""
for U in \
 "http://mackerell.umaryland.edu/download.php?filename=CHARMM_ff_params_files/charmm36-jul2024.ff.tgz" \
 "http://mackerell.umaryland.edu/download.php?filename=CHARMM_ff_params_files/charmm36-jul2022.ff.tgz"; do
  curl -fsSL --retry 2 -o c36.tgz "$U" 2>/dev/null && tar xzf c36.tgz 2>/dev/null && FF=$(ls -d charmm36*.ff 2>/dev/null|head -1) && [ -n "$FF" ] && break
done
if [ -n "$FF" ]; then FFNAME=$(basename "$FF" .ff); R B OK "CHARMM36m = $FFNAME"; else FFNAME=charmm27; R B WARN "CHARMM36m DL failed; using bundled $FFNAME for MECHANICS validation only"; fi
export GMXLIB=$PWD

# ---- C: components (pre-generated OFFLINE with gemmi on the author's box; staged in in/) ----
# No gemmi in-container: just stage the known-good PDBs into CWD.
cp in/receptor.pdb in/peptide.pdb in/mn_cada.pdb . 2>/dev/null
if [ -f receptor.pdb ] && [ -f peptide.pdb ] && [ -f mn_cada.pdb ]; then
  R C OK "pre-staged PDBs: receptor=$(grep -c '^ATOM' receptor.pdb) peptide=$(grep -c '^ATOM' peptide.pdb) mn_cada=$(grep -c '^HETATM' mn_cada.pdb) atoms"
else
  R C FAIL "pre-staged PDBs missing in in/ (expected receptor.pdb, peptide.pdb, mn_cada.pdb)"
fi

# ---- D: cyclic PEPTIDE topology + grompp (the FEP-mutated molecule; solvent-leg) ----
# default termini (robust); then demonstrate the head-to-tail cyclization amide as an added C-N bond.
if [ -f peptide.pdb ]; then
  if echo -e "1\n1" | gmx pdb2gmx -f peptide.pdb -o pep.gro -p pep.top -i pep_posre.itp -ff "$FFNAME" -water tip3p -ignh > d_pdb2gmx.out 2>&1; then
    R Dpdb2gmx OK "peptide covered by $FFNAME"
    gmx editconf -f pep.gro -o pep_box.gro -c -d 1.2 -bt cubic > /dev/null 2>&1
    if gmx grompp -f in/mdp/em.mdp -c pep_box.gro -p pep.top -o pep_em.tpr -maxwarn 5 > d_grompp.out 2>&1; then
      R Dgrompp OK "peptide (vacuum) grompp OK"
    else R Dgrompp FAIL "$(grep -iE 'error|fatal' d_grompp.out | head -3)"; fi
    # cyclization: add C(last res)-N(first res) amide bond to the peptide [moleculetype], re-grompp
    $PY - <<'PYEOF' > d_cyc.out 2>&1 || true
import re
top=open('pep.top').read()
# find [ atoms ] of Protein_chain to get first N and last C atom indices
m=re.search(r'\[ atoms \](.*?)\n\[', top, re.S)
ids=[]
if m:
    for ln in m.group(1).splitlines():
        p=ln.split()
        if len(p)>=5 and p[0].isdigit():
            ids.append((int(p[0]),p[3],p[4]))  # (nr, resname, atomname)
firstN=next((i for i,rn,an in ids if an=='N'),None)
lastC=None
for i,rn,an in ids:
    if an=='C': lastC=i
if firstN and lastC:
    # inject a bond into the [ bonds ] block
    top2=re.sub(r'(\[ bonds \]\n)', r'\1%5d %5d     1 ; HEAD-TO-TAIL CYCLIZATION amide (C_last-N_first)\n'%(lastC,firstN), top, count=1)
    open('pep_cyc.top','w').write(top2); print('CYC_ADDED lastC=%d firstN=%d'%(lastC,firstN))
else:
    print('CYC_INDEX_FAIL firstN=%s lastC=%s'%(firstN,lastC))
PYEOF
    if [ -f pep_cyc.top ]; then
      if gmx grompp -f in/mdp/em.mdp -c pep_box.gro -p pep_cyc.top -o pep_cyc.tpr -maxwarn 6 > d_cyc_grompp.out 2>&1; then
        R Dcyc OK "head-to-tail cyclization bond accepted by grompp ($(cat d_cyc.out))"
      else R Dcyc FAIL "cyclization grompp: $(grep -iE 'error|fatal' d_cyc_grompp.out|head -3)"; fi
    else R Dcyc WARN "could not locate N/C indices ($(cat d_cyc.out))"; fi
  else R Dpdb2gmx FAIL "$(grep -iE 'error|fatal|not found' d_pdb2gmx.out | head -4)"; fi
else R D SKIP "no peptide.pdb"; fi

# ---- E: pmx Y1F/Y7F hybrid (control edge) — built OFFLINE, verified here if staged ----
if [ -f in/hybrid.pdb ]; then
  cp in/hybrid.pdb . && R Epmx OK "pre-staged pmx Y1F/Y7F hybrid present ($(grep -c '^ATOM\|^HETATM' hybrid.pdb 2>/dev/null) atoms)"
else
  R Epmx SKIP "hybrid built offline (pmx develop + GMXLIB=mutff + charmm36m-mut on a pdb2gmx-hydrogenated peptide); NON-GATING for D/F"
fi

# ---- F: FULL COMPLEX pdb2gmx (receptor, reduced CYS) + 3x CaDA MN2 + grompp ----
echo "STAGE_F_ENTER receptor_atoms=$([ -f receptor.pdb ] && grep -c '^ATOM' receptor.pdb || echo MISSING) ff=$FFNAME"
if [ -f receptor.pdb ]; then
  # NO -ss: it prompts interactively per disulfide (integrin has many); a batch run can't answer it,
  # pdb2gmx then EOFs mid-prompt and (with the piped pipefail construct) emits no marker. Reduced CYS
  # are valid CHARMM36m residues -> fine for an assembly+coverage grompp preflight. </dev/null makes any
  # stray prompt EOF instantly (no hang); explicit rc=$? avoids the pipefail ambiguity that hid the marker.
  gmx pdb2gmx -f receptor.pdb -o rec.gro -p rec.top -i rec_posre.itp -ff "$FFNAME" -water tip3p -ignh < /dev/null > f_rec.out 2>&1
  rc=$?
  if [ $rc -eq 0 ] && [ -f rec.gro ]; then
    R Frec OK "receptor (chains A,B, 1069 res, reduced CYS) covered by $FFNAME"
    cp in/cada_mn.itp . ; export GMXLIB=$PWD
    if grep -q '#include' rec.top; then
      $PY - <<'PYEOF' > f_mergetop.out 2>&1 || true
import re
t=open('rec.top').read().splitlines(); out=[]; done_inc=False
for ln in t:
    out.append(ln)
    if ln.strip().startswith('#include') and not done_inc:
        out.append('#include "cada_mn.itp"'); done_inc=True   # atomtypes+MN2 moleculetype, after ff, before [system]
s='\n'.join(out)
s=re.sub(r'(\[ molecules \].*)$', r'\1\nMN2                 3', s, flags=re.S)  # 3 Mn sites
open('complex.top','w').write(s); print('MERGE_OK include+MN2x3')
PYEOF
      if [ -f complex.top ]; then
        R Fmerge OK "complex.top assembled (receptor + cada_mn.itp + MN2 x3) ($(cat f_mergetop.out))"
        # concat rec.gro + 21 CaDA-Mn atoms -> complex.gro; then editconf gives it a box for grompp/PME
        $PY - <<'PYEOF' > f_gro.out 2>&1 || true
rec=open('rec.gro').read().splitlines()
nrec=int(rec[1]); body=rec[2:2+nrec]; box=rec[2+nrec]
mn=[]; resn=1; idx=0
for ln in open('mn_cada.pdb'):
    if ln.startswith('HETATM'):
        x=float(ln[30:38])/10; y=float(ln[38:46])/10; z=float(ln[46:54])/10
        nm=ln[12:16].strip()
        if nm=='MN' and idx!=0: resn+=1
        mn.append('%5d%-5s%5s%5d%8.3f%8.3f%8.3f'%(resn,'MN2',nm,(nrec+len(mn)+1)%100000,x,y,z))
        idx+=1
tot=nrec+len(mn)
open('complex.gro','w').write(rec[0]+'\n%d\n'%tot+'\n'.join(body+mn)+'\n'+box+'\n')
print('GRO_OK tot=%d (rec=%d + mn=%d)'%(tot,nrec,len(mn)))
PYEOF
        gmx editconf -f complex.gro -o complex_box.gro -d 1.0 -bt cubic > f_editconf.out 2>&1 || cp complex.gro complex_box.gro
        if gmx grompp -f in/mdp/em.mdp -c complex_box.gro -p complex.top -o complex_em.tpr -maxwarn 10 > f_grompp.out 2>&1; then
          R Fgrompp OK "FULL receptor+CaDA-Mn complex grompp OK ($(cat f_gro.out))"
        else R Fgrompp FAIL "$(grep -iE 'error|fatal' f_grompp.out | head -5 | tr '\n' '|')"; fi
      else R Fmerge FAIL "$(cat f_mergetop.out)"; fi
    else R Fmerge WARN "rec.top has no #include to anchor cada_mn include"; fi
  else R Frec FAIL "rc=$rc $(grep -iE 'error|fatal|not found|does not match|not recognized|no such' f_rec.out | head -6 | tr '\n' '|')"; fi
else R F SKIP "no receptor.pdb"; fi

echo "PREFLIGHT_STAGES_DONE"   # the EXIT trap above ships logs.tgz + PREFLIGHT_EXIT unconditionally
