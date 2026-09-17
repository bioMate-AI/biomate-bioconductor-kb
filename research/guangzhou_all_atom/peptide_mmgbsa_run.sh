#!/bin/bash
# End-to-end protein-(cyclic)peptide MM-GBSA on BoltzGen designs — the verified DeltaG the whole thread
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
ROOT=/opt/mmg; OUT_S3=${OUT_S3:?}; DESIGNS_S3=${DESIGNS_S3:?}
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
for V in jul22 jul21 aug21 jul20; do
  if curl -fsSL "http://mackerell.umaryland.edu/download.php?filename=CHARMM_ff_params_files/toppar_c36_${V}.tgz" -o toppar.tgz 2>/dev/null && tar tzf toppar.tgz >/dev/null 2>&1; then tar xzf toppar.tgz; break; fi
done
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

RTF=os.environ['RTF']; PRM=os.environ['PRM']; DES=os.environ['DESIGNS_S3']; NS=float(os.environ['NS'])
TARGETS=['1yf4','1u8p','1kc4','1csb']            # 4 v5 targets (top ranked design each)
CPU=mm.Platform.getPlatformByName('CPU')
try: PLAT=mm.Platform.getPlatformByName('CUDA')
except Exception: PLAT=CPU
print('platform:', PLAT.getName())

def is_aa(r):
    i=gemmi.find_tabulated_residue(r.name); return bool(i) and i.is_amino_acid()

def split_design(cif, tag):
    st=gemmi.read_structure(cif); st.setup_entities(); m=st[0]
    ch=[(c.name,sum(is_aa(r) for r in c)) for c in m]; ch=[c for c in ch if c[1]>0]; ch.sort(key=lambda x:x[1])
    pep,rec=ch[0][0],ch[-1][0]
    def w(name,path,rn):
        s=gemmi.Structure(); md=gemmi.Model('1'); c2=gemmi.Chain('X')
        for c in m:
            if c.name!=name: continue
            for r in c:
                if is_aa(r): c2.add_residue(r)
        md.add_chain(c2); s.add_model(md); s.setup_entities()
        if rn:
            n=0
            for r in s[0][0]: n+=1; r.seqid=gemmi.SeqId(n,' ')
        s.write_pdb(path); return sum(1 for _ in c2)
    npep=w(pep, f'{tag}_pep.pdb', True); nrec=w(rec, f'{tag}_rec.pdb', False)
    return nrec, npep

HEADTAIL='''* head-to-tail patch
*
   36  1
PRES CYCP         0.00
BOND 1C 2N

END
'''
open('headtail.top','w').write(HEADTAIL)
ALIASES=[('HIS','HSD'),('HID','HSD'),('HIE','HSE'),('HIP','HSP')]

def build_psf(kind, tag, npep):
    g=PsfGen()
    g.read_topology(RTF); g.read_topology('headtail.top')
    for a,b in ALIASES:
        try: g.alias_residue(top_resname=b, pdb_resname=a)
        except Exception:
            try: g.alias_residue(a,b)
            except Exception: pass
    if kind in ('complex','receptor'):
        g.add_segment(segid='REC', pdbfile=f'{tag}_rec.pdb')
        g.read_coords(segid='REC', filename=f'{tag}_rec.pdb')
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

results=[]
for tag in TARGETS:
    rec={'target':tag}
    try:
        subprocess.run(['aws','s3','sync',f'{DES}/{tag}/',f'./{tag}/','--only-show-errors','--exclude','*','--include','*.cif'],check=True)
        cifs=[c for c in glob.glob(f'{tag}/**/*.cif',recursive=True) if 'before_refolding' not in c]
        cif=sorted([c for c in cifs if 'rank0' in os.path.basename(c)]) or sorted(cifs)
        cif=cif[0]
        nrec,npep=split_design(cif, tag); rec['nrec_res']=nrec; rec['npep_res']=npep
        cpsf,cpdb=build_psf('complex',tag,npep)
        rpsf,_=build_psf('receptor',tag,npep)
        lpsf,_=build_psf('ligand',tag,npep)
        # verify peptide ring in the ligand psf
        lp=pmd.load_file(lpsf); nb=len(lp.bonds); na=len(lp.atoms)
        rec['ligand_ring_closed']=(nb==na)  # cyclic: bonds==atoms; linear: atoms-1
        # complex system + coords
        cp, csys = make_system(cpsf)
        pos = app.PDBFile(cpdb).getPositions()
        # minimize complex
        integ=mm.LangevinMiddleIntegrator(300*unit.kelvin,1/unit.picosecond,0.002*unit.picoseconds)
        sim=app.Simulation(cp.topology, csys, integ, PLAT)
        sim.context.setPositions(pos)
        sim.minimizeEnergy(maxIterations=2000)
        sim.context.setVelocitiesToTemperature(300*unit.kelvin)
        nsteps=int(NS*1000/0.002); interval=max(1, nsteps//20)
        rp, rsys = make_system(rpsf); lp2, lsys = make_system(lpsf)
        natom_rec = rsys.getNumParticles()
        dgs=[]
        sim.step(2000)  # brief equilibration
        for k in range(20):
            sim.step(interval)
            st=sim.context.getState(getPositions=True)
            P=st.getPositions()
            Ecom=energy(csys, P)
            Erec=energy(rsys, P[:natom_rec])
            Elig=energy(lsys, P[natom_rec:])
            dgs.append(Ecom-Erec-Elig)
        dgs=np.array(dgs)
        rec['dG_bind_kcal_mol']=round(float(dgs.mean()),2)
        rec['dG_std']=round(float(dgs.std()),2)
        rec['n_frames']=len(dgs)
        rec['ok']=True
        print(f"{tag}: dG = {rec['dG_bind_kcal_mol']} +/- {rec['dG_std']} kcal/mol (ring_closed={rec['ligand_ring_closed']})")
    except Exception as e:
        import traceback; rec['ok']=False; rec['error']=type(e).__name__+': '+str(e)[:200]
        print(f"{tag} FAILED:", rec['error']); traceback.print_exc()
    results.append(rec); json.dump({'results':results}, open('/opt/mmg/status/mmgbsa_results.json','w'), indent=2)

ok=[r for r in results if r.get('ok')]
ok.sort(key=lambda r: r['dG_bind_kcal_mol'])
summary={'n_targets':len(results),'n_ok':len(ok),
         'ranking_by_dG':[{ 't':r['target'],'dG':r['dG_bind_kcal_mol'],'std':r['dG_std'],'ring':r.get('ligand_ring_closed')} for r in ok],
         'note':'Implicit-solvent (GBn2) single-trajectory MM-GBSA, CHARMM36m, cyclic peptide via psfgen '
                'CYCP head-to-tail patch. RELATIVE ranking oracle, not absolute affinity; entropy omitted; '
                'confirm finalists with FEP.','all':results}
json.dump(summary, open('/opt/mmg/status/mmgbsa_results.json','w'), indent=2)
print(json.dumps(summary['ranking_by_dG'], indent=2))
PY
stage mmgbsa_complete
