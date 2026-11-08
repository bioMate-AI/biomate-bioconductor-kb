#!/bin/bash
# v3 physics-verify: MM-GBSA dG for an explicit list of oversampled designs (the union of the v3 perm-aware
# top-8 and BoltzGen-default top-8). Answers: are the small low-donor binders v3 selected REAL binders by
# physics, or did iptm overrate them? Same validated cyclic MM-GBSA pipeline (psfgen CYCP + OpenMM GBn2).
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HOME=/root
ROOT=/opt/mmg; OUT_S3=${OUT_S3:?}; BUCKET=knowledge-datasets-1759951976
TOP=cyclic_peptide/datasets/charmm36_toppar
CIF_PREFIX_S3=${CIF_PREFIX_S3:?}   # e.g. s3://.../boltzgen_targets/1yf4/intermediate_designs_inverse_folded/refold_cif
DESIGN_IDS=${DESIGN_IDS:?}         # comma list, e.g. 1yf4_10,1yf4_22,...
mkdir -p "$ROOT/status" "$ROOT/w"; cd "$ROOT/w"
exec > >(tee -a "$ROOT/status/mmg.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s","detail":"%s"}\n' "$1" "$(date -u +%FT%TZ)" "${2:-}" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync; sleep 4; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 2; shutdown -h now; exit $rc' EXIT
systemd-run --unit=mmg-deadline --on-active=3h /sbin/shutdown -h now || true

stage installing
apt-get update -qq && apt-get install -y -qq unzip curl libgomp1 || true
command -v aws >/dev/null 2>&1 || { curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda; source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda create -y -n mmg -c conda-forge python=3.11 openmm psfgen parmed gemmi numpy libgomp llvm-openmp >/dev/null 2>&1
conda activate mmg
export LD_LIBRARY_PATH=/opt/miniconda/envs/mmg/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}
python -c "import ctypes; ctypes.CDLL('libgomp.so.1'); import openmm, psfgen, parmed, gemmi; print('deps ok')"

stage fetch
aws s3 cp "s3://$BUCKET/$TOP/top_all36_prot.rtf" ./top.rtf --only-show-errors
aws s3 cp "s3://$BUCKET/$TOP/par_all36m_prot.prm" ./par.prm --only-show-errors
for id in ${DESIGN_IDS//,/ }; do aws s3 cp "$CIF_PREFIX_S3/$id.cif" "./$id.cif" --only-show-errors || echo "miss $id"; done
ls -1 *.cif

stage run
DESIGN_IDS=$DESIGN_IDS python - <<'PY'
import os, json, numpy as np, traceback
import gemmi
from psfgen import PsfGen
import openmm as mm
from openmm import app, unit
IDS=[x for x in os.environ['DESIGN_IDS'].split(',') if x.strip()]
PLAT=mm.Platform.getPlatformByName('CPU')
try: PLAT.setPropertyDefaultValue('Threads', str(os.cpu_count() or 8))
except Exception: pass
open('headtail.top','w').write('* head-to-tail\n*\n   36  1\nPRES CYCP         0.00\nBOND 1C 2N\n\nEND\n')

def is_aa(r):
    i=gemmi.find_tabulated_residue(r.name); return bool(i) and i.is_amino_acid()
def split(cif, tag):
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
    npep=w(pep,f'{tag}_pep.pdb',True); nrec=w(rec,f'{tag}_rec.pdb',False); return npep,nrec

ALIASES=[('HIS','HSD'),('HID','HSD'),('HIE','HSE'),('HIP','HSP')]
def build(kind, tag, npep):
    g=PsfGen(); g.read_topology('top.rtf'); g.read_topology('headtail.top')
    for a,b in ALIASES:
        try: g.alias_residue(top_resname=b, pdb_resname=a)
        except Exception:
            try: g.alias_residue(a,b)
            except Exception: pass
    try: g.alias_atom(resname='ILE', top_atomname='CD', pdb_atomname='CD1')
    except Exception: pass
    if kind in ('complex','receptor'):
        g.add_segment(segid='REC', pdbfile=f'{tag}_rec.pdb'); g.read_coords(segid='REC', filename=f'{tag}_rec.pdb')
    if kind in ('complex','ligand'):
        g.add_segment(segid='PEP', pdbfile=f'{tag}_pep.pdb', first='none', last='none'); g.read_coords(segid='PEP', filename=f'{tag}_pep.pdb')
        g.patch('CYCP', [('PEP',str(npep)),('PEP','1')])
    g.regenerate_angles(); g.regenerate_dihedrals()
    try: g.guess_coords()
    except Exception: pass
    psf=f'{tag}_{kind}.psf'; g.write_psf(filename=psf); g.write_pdb(filename=psf.replace('.psf','.pdb')); return psf

params=app.CharmmParameterSet('top.rtf','par.prm')
def make(psf):
    p=app.CharmmPsfFile(psf); return p, p.createSystem(params, nonbondedMethod=app.CutoffNonPeriodic,
        nonbondedCutoff=2.0*unit.nanometer, constraints=app.HBonds, implicitSolvent=app.GBn2)
def energy(system, positions):
    integ=mm.VerletIntegrator(1.0*unit.femtoseconds); ctx=mm.Context(system, integ, PLAT)
    ctx.setPositions(positions); e=ctx.getState(getEnergy=True).getPotentialEnergy().value_in_unit(unit.kilocalorie_per_mole)
    del ctx, integ; return e

def olc(r):
    t=gemmi.find_tabulated_residue(r.name); return (t.one_letter_code.upper() if t else 'X')
results={}
for i,cid in enumerate(IDS):
    cif=f'{cid}.cif'
    if not os.path.exists(cif): results[cid]={'ok':False,'error':'no cif'}; continue
    try:
        npep,nrec=split(cif, cid)
        cpsf=build('complex',cid,npep); rpsf=build('receptor',cid,npep); lpsf=build('ligand',cid,npep)
        import parmed as pmd
        seq=''.join(olc(r) for r in pmd.load_file(lpsf).residues)
        cp,csys=make(cpsf); pos=app.PDBFile(cpsf.replace('.psf','.pdb')).getPositions()
        integ=mm.LangevinMiddleIntegrator(300*unit.kelvin,1/unit.picosecond,0.002*unit.picoseconds)
        sim=app.Simulation(cp.topology,csys,integ,PLAT); sim.context.setPositions(pos); sim.minimizeEnergy(maxIterations=5000)
        rp,rsys=make(rpsf); lp,lsys=make(lpsf); nra=rsys.getNumParticles()
        P=sim.context.getState(getPositions=True).getPositions()
        Ec=energy(csys,P); Er=energy(rsys,P[:nra]); El=energy(lsys,P[nra:])
        results[cid]={'ok':True,'seq':seq,'dG':round(float(Ec-Er-El),2)}
        print(cid, seq, 'dG', results[cid]['dG'])
    except Exception as e:
        results[cid]={'ok':False,'error':f'{type(e).__name__}: {e}'}; print(cid,'FAIL'); traceback.print_exc()
    json.dump(results, open('/opt/mmg/status/v3verify_mmgbsa.json','w'), indent=2)
    os.system(f'aws s3 cp /opt/mmg/status/v3verify_mmgbsa.json {os.environ.get("OUT_S3","")}/status/v3verify_mmgbsa.json --only-show-errors 2>/dev/null' if os.environ.get('OUT_S3') else 'true')
print(json.dumps(results, indent=2))
PY
aws s3 cp /opt/mmg/status/v3verify_mmgbsa.json "$OUT_S3/status/v3verify_mmgbsa.json" --only-show-errors || true
stage v3verify_complete
