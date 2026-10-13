#!/bin/bash
# POCKET MM-GBSA (pocket-truncated receptor; each contiguous fragment = its own psfgen\n# segment -> no spurious cross-chain/gap bonds). Adapted from peptide_mmgbsa_run.sh.\n# End-to-end protein-(cyclic)peptide MM-GBSA on BoltzGen designs — the verified DeltaG the whole thread
# was building toward. Self-contained (psfgen + OpenMM + ParmEd, all Python):
#   1. split design -> receptor.pdb + peptide.pdb (renumber peptide 1..N)
#   2. psfgen (modern Eigenstate) build 3 PSFs: complex, receptor-only, ligand-only (cyclic peptide via
#      first/none/last/none + unique CYCP head-to-tail patch — the validated recipe)
#   3. OpenMM: implicit-solvent (GBn2) minimize + short MD of the complex (GPU)
#   4. single-trajectory MM-GBSA: per frame  dG = E_complex - E_receptor - E_ligand  (coords sliced:
#      complex atoms are receptor-then-peptide, so rec = coords[:nrec], lig = coords[nrec:])
# FAIL-FAST: if a target's build fails it is skipped (cheap); MD only runs for built targets.
# MM-GBSA is a RELATIVE ranking oracle (Sun PCCP 2019), not absolute; confirm finalists with FEP.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HOME=/root
ROOT=/opt/mmg; OUT_S3=${OUT_S3:?}; DESIGNS_S3=${DESIGNS_S3:?}; export OUT_S3 DESIGNS_S3
NS=${NS:-0.5}   # MD length in ns (implicit solvent; short is fine for ranking)
mkdir -p "$ROOT/status" "$ROOT/w"; cd "$ROOT/w"
exec > >(tee -a "$ROOT/status/mmg.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync; sleep 6; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 4; shutdown -h now; exit $rc' EXIT
systemd-run --unit=mmg-deadline --on-active=3h /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda; source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda create -y -n mmg -c conda-forge python=3.11 openmm psfgen parmed gemmi numpy >/dev/null 2>&1
conda activate mmg
python -c "import openmm; print('openmm', openmm.__version__, [openmm.Platform.getPlatform(i).getName() for i in range(openmm.Platform.getNumPlatforms())]); import psfgen, parmed; print('psfgen/parmed ok')"

stage fetch_toppar
# PRIMARY: our own S3 cache (reliable — no external dependency; MacKerell is intermittently down)
mkdir -p toppar
aws s3 cp "s3://knowledge-datasets-1759951976/cyclic_peptide/datasets/charmm36_toppar/top_all36_prot.rtf" toppar/ --only-show-errors 2>/dev/null || true
aws s3 cp "s3://knowledge-datasets-1759951976/cyclic_peptide/datasets/charmm36_toppar/par_all36m_prot.prm" toppar/ --only-show-errors 2>/dev/null || true
# FALLBACK: MacKerell tarball (retry across versions) only if the S3 cache missed
if [ -z "$(find . -name 'top_all36_prot.rtf' | head -1)" ] || [ -z "$(find . -name 'par_all36m_prot.prm' | head -1)" ]; then
for V in jul22 jul21 aug21 jul20 jul24; do
  if curl -fsSL --retry 4 --retry-delay 5 "http://mackerell.umaryland.edu/download.php?filename=CHARMM_ff_params_files/toppar_c36_${V}.tgz" -o toppar.tgz 2>/dev/null && tar tzf toppar.tgz >/dev/null 2>&1; then tar xzf toppar.tgz; echo "toppar_c36_${V}"; break; fi
done
# GitHub mirror fallback for BOTH rtf + prm (OpenMM CharmmParameterSet needs both)
if [ -z "$(find . -name 'top_all36_prot.rtf' | head -1)" ] || [ -z "$(find . -name 'par_all36m_prot.prm' -o -name 'par_all36_prot.prm' 2>/dev/null | head -1)" ]; then
  mkdir -p toppar
  for BASE in "https://raw.githubusercontent.com/intbio/charmm36/master" "https://raw.githubusercontent.com/wmwv/charmm36-toppar/master" "https://raw.githubusercontent.com/openmm/openmmforcefields/main/charmm/ffxml/../../.."; do
    curl -fsSL --retry 3 "$BASE/top_all36_prot.rtf" -o toppar/top_all36_prot.rtf 2>/dev/null || true
    curl -fsSL --retry 3 "$BASE/par_all36m_prot.prm" -o toppar/par_all36m_prot.prm 2>/dev/null || true
    [ -s toppar/top_all36_prot.rtf ] && [ -s toppar/par_all36m_prot.prm ] && { echo "toppar from $BASE"; break; }
  done
fi
fi   # close S3-cache-miss fallback block
RTF=$(find . -name "top_all36_prot.rtf" | head -1); PRM=$(find . -name "par_all36m_prot.prm" | head -1)
[ -z "$PRM" ] && PRM=$(find . -name "par_all36_prot.prm" | head -1)
echo "rtf=$RTF prm=$PRM"; [ -z "$RTF" -o -z "$PRM" ] && { echo "FATAL: no CHARMM36 toppar"; exit 1; }

stage run
RTF="$RTF" PRM="$PRM" DESIGNS_S3="$DESIGNS_S3" NS="$NS" python - <<'PY'
import os, json, glob, subprocess, numpy as np
import gemmi
from psfgen import PsfGen
import openmm as mm
from openmm import app, unit
import parmed as pmd

RTF=os.environ['RTF']; PRM=os.environ['PRM']; DES=os.environ['DESIGNS_S3']
TARGET=os.environ.get('TARGET','1yf4')           # score ALL designs of ONE target (valid within-target ranking)
CPU=mm.Platform.getPlatformByName('CPU')
# Force CPU: conda-forge OpenMM's CUDA PTX is newer than the DL-AMI driver (CUDA_ERROR_UNSUPPORTED_PTX).
# Implicit-solvent MM-GBSA on these small systems runs fine on CPU; short peptides are best via
# minimized/short-MD MM-GBSA anyway (Sun PCCP 2019). No GPU needed.
try: CPU.setPropertyDefaultValue('Threads', str(os.cpu_count() or 8))
except Exception: pass
PLAT=CPU
print('platform:', PLAT.getName(), 'threads', os.cpu_count())

def is_aa(r):
    i=gemmi.find_tabulated_residue(r.name); return bool(i) and i.is_amino_acid()

def _write_run(residues, path):
    """Write a list of residues as a single clean chain X, renumbered 1..n."""
    s=gemmi.Structure(); md=gemmi.Model('1'); c2=gemmi.Chain('X')
    n=0
    for r in residues:
        n+=1; r2=r.clone() if hasattr(r,'clone') else r
        c2.add_residue(r2); c2[-1].seqid=gemmi.SeqId(n,' ')
    md.add_chain(c2); s.add_model(md); s.setup_entities()
    s.write_pdb(path); return n

def split_design(cif, tag):
    """POCKET variant: peptide = fewest-aa chain. Receptor = ALL other chains, each split into
    CONTIGUOUS residue runs (gap in seqid.num -> new fragment) so psfgen never bonds across a gap
    (the whole-receptor hang was a spurious bond across chain/gap breaks). Returns (rec_pdbs, npep)."""
    st=gemmi.read_structure(cif); st.setup_entities(); m=st[0]
    ch=[(c.name,sum(is_aa(r) for r in c)) for c in m]; ch=[c for c in ch if c[1]>0]; ch.sort(key=lambda x:x[1])
    pep=ch[0][0]; rec_names=[c for c,_ in ch[1:]]
    pepres=[r for c in m if c.name==pep for r in c if is_aa(r)]
    npep=_write_run(pepres, f'{tag}_pep.pdb')
    rec_pdbs=[]; k=0
    for cn in rec_names:
        res=[r for c in m if c.name==cn for r in c if is_aa(r)]
        res.sort(key=lambda r:r.seqid.num)
        frag=[]; prev=None
        for r in res:
            if prev is not None and r.seqid.num!=prev+1:
                p=f'{tag}_rec{k}.pdb'; _write_run(frag,p); rec_pdbs.append(p); k+=1; frag=[]
            frag.append(r); prev=r.seqid.num
        if frag:
            p=f'{tag}_rec{k}.pdb'; _write_run(frag,p); rec_pdbs.append(p); k+=1
    return rec_pdbs, npep

HEADTAIL='''* head-to-tail patch
*
   36  1
PRES CYCP         0.00
BOND 1C 2N

END
'''
open('headtail.top','w').write(HEADTAIL)
ALIASES=[('HIS','HSD'),('HID','HSD'),('HIE','HSE'),('HIP','HSP')]

def build_psf(kind, tag, npep, rec_pdbs):
    g=PsfGen()
    g.read_topology(RTF); g.read_topology('headtail.top')
    for a,b in ALIASES:
        try: g.alias_residue(top_resname=b, pdb_resname=a)
        except Exception:
            try: g.alias_residue(a,b)
            except Exception: pass
    try: g.alias_atom(resname='ILE', top_atomname='CD', pdb_atomname='CD1')
    except Exception:
        try: g.alias_atom('ILE','CD','CD1')
        except Exception: pass
    # receptor FIRST (each contiguous fragment = its own segment with default NTER/CTER -> no
    # spurious bond across chain/gap breaks), THEN peptide -> complex coords = [REC..., PEP].
    if kind in ('complex','receptor'):
        for i,rp in enumerate(rec_pdbs):
            sid=f'R{i}'
            # Neutral ACE/CT3 caps on the ragged POCKET-CUT termini: default NTER/CTER left psfgen
            # guessing terminal atoms inconsistently -> complex cpdb/cpsf atom-count mismatch -> the
            # 5/10 setPositions failure. Caps are deterministic + chemically correct for a truncation.
            try:
                g.add_segment(segid=sid, pdbfile=rp, first='ACE', last='CT3')
            except Exception:
                g.add_segment(segid=sid, pdbfile=rp)
            g.read_coords(segid=sid, filename=rp)
    if kind in ('complex','ligand'):
        g.add_segment(segid='PEP', pdbfile=f'{tag}_pep.pdb', first='none', last='none')
        g.read_coords(segid='PEP', filename=f'{tag}_pep.pdb')
        g.patch('CYCP', [('PEP', str(npep)), ('PEP','1')])
    g.regenerate_angles(); g.regenerate_dihedrals()
    try: g.guess_coords()
    except Exception: pass
    psf=f'{tag}_{kind}.psf'; pdb=f'{tag}_{kind}.pdb'
    g.write_psf(filename=psf); g.write_pdb(filename=pdb)
    return psf, pdb

params=app.CharmmParameterSet(RTF, PRM)
def make_system(psf):
    p=app.CharmmPsfFile(psf)
    sysm=p.createSystem(params, nonbondedMethod=app.CutoffNonPeriodic, nonbondedCutoff=2.0*unit.nanometer,
                        constraints=app.HBonds, implicitSolvent=app.GBn2)
    return p, sysm

def energy(system, positions):
    integ=mm.VerletIntegrator(1.0*unit.femtoseconds)
    ctx=mm.Context(system, integ, CPU)
    ctx.setPositions(positions)
    e=ctx.getState(getEnergy=True).getPotentialEnergy().value_in_unit(unit.kilocalorie_per_mole)
    del ctx, integ
    return e

def ring_closed(lp):
    # proper head-to-tail test: bond between N of residue-1 and C of the last residue (Pro-safe,
    # unlike bonds==atoms which miscounts due to proline side-chain rings)
    def idx(res,nm):
        for a in res.atoms:
            if a.name==nm: return a.idx
        return None
    ni=idx(lp.residues[0],'N'); ci=idx(lp.residues[-1],'C')
    return bool(any({b.atom1.idx,b.atom2.idx}=={ni,ci} for b in lp.bonds)) if (ni is not None and ci is not None) else False

subprocess.run(['aws','s3','sync',f'{DES}/{TARGET}/',f'./{TARGET}/','--only-show-errors','--exclude','*','--include','*.cif'],check=True)
allc=[c for c in glob.glob(f'{TARGET}/**/*.cif',recursive=True) if 'before_refolding' not in c and 'final_ranked' in c]
if not allc: allc=[c for c in glob.glob(f'{TARGET}/**/*.cif',recursive=True) if 'before_refolding' not in c]
seen=set(); designs=[]
for c in sorted(allc):
    d=os.path.basename(c).replace('.cif','').split('_')[-1]   # design index (rankNN_1yf4_<D>.cif)
    if d in seen: continue
    seen.add(d); designs.append(c)
print(f"{TARGET}: scoring {len(designs)} designs (within-target MM-GBSA ranking)")
results=[]
for cif in designs:
    did=os.path.basename(cif).replace('.cif','')
    tag=f"{TARGET}_{did}".replace('/','_')
    rec={'target':TARGET,'design':did}
    try:
        rec_pdbs,npep=split_design(cif, tag); rec['n_rec_frags']=len(rec_pdbs); rec['npep_res']=npep
        cpsf,cpdb=build_psf('complex',tag,npep,rec_pdbs)
        rpsf,_=build_psf('receptor',tag,npep,rec_pdbs)
        lpsf,_=build_psf('ligand',tag,npep,rec_pdbs)
        lp=pmd.load_file(lpsf)
        rec['ligand_ring_closed']=ring_closed(lp)
        def _olc(r):
            t=gemmi.find_tabulated_residue(r.name); return (t.one_letter_code.upper() if t else 'X')
        rec['seq']=''.join(_olc(r) for r in lp.residues)
        # minimize complex, then single-point MM-GBSA (Sun PCCP 2019: minimized-structure MM-GBSA is
        # the best protocol for short peptides — and fast/robust on CPU, no MD needed).
        cp, csys = make_system(cpsf)
        # FIX (was 5/10): building receptor-only / ligand-only as SEPARATE psfgen jobs gave divergent
        # cut-termini atom counts -> P[:natom_rec] slice mismatch -> 'setPositions wrong number of
        # positions'. Instead minimize the COMPLEX once, then SPLIT the minimized complex with parmed
        # by segid (PEP=ligand, rest=receptor) so atoms/counts are identical by construction (correct
        # single-trajectory MM-GBSA). No separate rec/lig psfgen builds needed.
        pos = app.PDBFile(cpdb).getPositions()
        integ=mm.LangevinMiddleIntegrator(300*unit.kelvin,1/unit.picosecond,0.002*unit.picoseconds)
        sim=app.Simulation(cp.topology, csys, integ, PLAT)
        sim.context.setPositions(pos)
        sim.minimizeEnergy(maxIterations=5000)
        import numpy as _np
        P=sim.context.getState(getPositions=True).getPositions()
        Ecom=energy(csys, P)
        comp_pmd=pmd.charmm.CharmmPsfFile(cpsf); comp_pmd.load_parameters(pmd.charmm.CharmmParameterSet(RTF,PRM))
        comp_pmd.coordinates=_np.array(P.value_in_unit(unit.angstrom))
        rec_idx=[a.idx for a in comp_pmd.atoms if a.residue.segid!='PEP']
        lig_idx=[a.idx for a in comp_pmd.atoms if a.residue.segid=='PEP']
        rst=comp_pmd[rec_idx]; lst=comp_pmd[lig_idx]
        _opt=dict(nonbondedMethod=app.CutoffNonPeriodic, nonbondedCutoff=2.0*unit.nanometer, constraints=app.HBonds, implicitSolvent=app.GBn2)
        rsys=rst.createSystem(**_opt); lsys=lst.createSystem(**_opt)
        Erec=energy(rsys, rst.positions); Elig=energy(lsys, lst.positions)
        rec['dG_bind_kcal_mol']=round(float(Ecom-Erec-Elig),2)
        rec['E_complex_kcal']=round(Ecom,1); rec['E_receptor_kcal']=round(Erec,1); rec['E_ligand_kcal']=round(Elig,1)
        rec['protocol']='minimized single-point, implicit GBn2 (CHARMM36m)'
        rec['ok']=True
        print(f"{tag}: dG = {rec['dG_bind_kcal_mol']} kcal/mol (ring_closed={rec['ligand_ring_closed']}, {rec['npep_res']}-mer)")
    except Exception as e:
        import traceback; rec['ok']=False; rec['error']=type(e).__name__+': '+str(e)[:200]
        print(f"{tag} FAILED:", rec['error']); traceback.print_exc()
    results.append(rec); json.dump({'results':results}, open('/opt/mmg/status/mmgbsa_results.json','w'), indent=2)
    __import__('os').system("aws s3 cp /opt/mmg/status/mmgbsa_results.json %s/status/mmgbsa_results.json --only-show-errors 2>/dev/null" % __import__('os').environ.get('OUT_S3',''))  # per-design sync -> continuous middle outputs

ok=[r for r in results if r.get('ok')]
ok.sort(key=lambda r: r['dG_bind_kcal_mol'])
summary={'target':TARGET,'n_designs':len(results),'n_ok':len(ok),
         'within_target_ranking':[{ 'design':r['design'],'seq':r.get('seq'),'dG':r['dG_bind_kcal_mol'],'ring':r.get('ligand_ring_closed')} for r in ok],
         'note':'Within-TARGET MM-GBSA ranking of designs for one receptor (the valid use). Implicit '
                'GBn2 minimized single-point, CHARMM36m, cyclic via psfgen CYCP patch. RELATIVE ranking, '
                'not absolute affinity; entropy omitted; confirm finalists with FEP. Trust only ring=true rows.',
         'all':results}
json.dump(summary, open('/opt/mmg/status/mmgbsa_results.json','w'), indent=2)
print('n_ok', summary['n_ok'], 'of', summary['n_designs'])
PY
stage mmgbsa_complete
