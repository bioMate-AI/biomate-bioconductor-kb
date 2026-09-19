#!/bin/bash
# v2 SMOKE: can we build + parametrize an N-methylated cyclic peptide in the SAME validated CHARMM/psfgen
# pipeline that built 32/32 rings? Primary goal = surface missing N-methyl parameters (build test), MM-GBSA
# ddG secondary. One design (1yf4 FSRNVGDPY), methylate ONE backbone amide (a v1-selected non-interface-
# H-bonding position). Full errors printed (nothing swallowed) so the patch can be iterated like CYCP was.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HOME=/root
ROOT=/opt/nm; OUT_S3=${OUT_S3:?}; BUCKET=knowledge-datasets-1759951976
TOP=cyclic_peptide/datasets/charmm36_toppar
CIF_S3=s3://$BUCKET/cyclic_peptide/runs/boltzgen-targets-20260916T001350Z/boltzgen_targets/1yf4/final_ranked_designs/intermediate_ranked_10_designs/rank6_1yf4_5.cif
METH_POS=${METH_POS:-6}   # FSRNVGDPY: v1 says methylate {1,2,6,7,9}; pos6=GLY (backbone-only, cleanest smoke)
mkdir -p "$ROOT/status" "$ROOT/w"; cd "$ROOT/w"
exec > >(tee -a "$ROOT/status/nm.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s","detail":"%s"}\n' "$1" "$(date -u +%FT%TZ)" "${2:-}" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync; sleep 3; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 2; shutdown -h now; exit $rc' EXIT
systemd-run --unit=nm-deadline --on-active=60min /sbin/shutdown -h now || true

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
python -c "import ctypes; ctypes.CDLL('libgomp.so.1'); import openmm, psfgen, parmed, gemmi; print('deps ok', openmm.__version__)"

stage fetch
aws s3 cp "s3://$BUCKET/$TOP/top_all36_prot.rtf" ./top.rtf --only-show-errors
aws s3 cp "s3://$BUCKET/$TOP/par_all36m_prot.prm" ./par.prm --only-show-errors
aws s3 cp "$CIF_S3" ./design.cif --only-show-errors
ls -la ./top.rtf ./par.prm ./design.cif

stage run
METH_POS=$METH_POS python - <<'PY'
import os, numpy as np, traceback
import gemmi
from psfgen import PsfGen
import openmm as mm
from openmm import app, unit
POS=int(os.environ['METH_POS'])
PLAT=mm.Platform.getPlatformByName('CPU')

# --- N-methyl backbone patch (delete amide HN, add N-CH3). Charges: neutral, tertiary-amide-like
#     (N -0.32 / CN -0.11 / 3x HA3 +0.09 -> net change 0 vs original NH1(-0.47)+HN(+0.31)). Approximate,
#     intended for RELATIVE ddG (peptide intramolecular terms largely cancel single-trajectory). ---
NMET='''* n-methyl backbone patch
*
   36  1
PRES NMET         0.00
GROUP
ATOM N   NH1  -0.32
ATOM CN  CT3  -0.11
ATOM HN1 HA3   0.09
ATOM HN2 HA3   0.09
ATOM HN3 HA3   0.09
DELETE ATOM HN
BOND N CN
BOND CN HN1
BOND CN HN2
BOND CN HN3

END
'''
open('nmet.top','w').write(NMET)
HEADTAIL='''* head-to-tail
*
   36  1
PRES CYCP         0.00
BOND 1C 2N

END
'''
open('headtail.top','w').write(HEADTAIL)

def is_aa(r):
    i=gemmi.find_tabulated_residue(r.name); return bool(i) and i.is_amino_acid()
def split(cif):
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
    npep=w(pep,'pep.pdb',True); nrec=w(rec,'rec.pdb',False); return npep,nrec
npep,nrec=split('design.cif'); print('npep',npep,'nrec',nrec,'methylate pos',POS)

ALIASES=[('HIS','HSD'),('HID','HSD'),('HIE','HSE'),('HIP','HSP')]
def build(kind, methyl_pos=None):
    g=PsfGen(); g.read_topology('top.rtf'); g.read_topology('headtail.top'); g.read_topology('nmet.top')
    for a,b in ALIASES:
        try: g.alias_residue(top_resname=b, pdb_resname=a)
        except Exception:
            try: g.alias_residue(a,b)
            except Exception: pass
    try: g.alias_atom(resname='ILE', top_atomname='CD', pdb_atomname='CD1')
    except Exception: pass
    if kind in ('complex','ligand'):
        g.add_segment(segid='PEP', pdbfile='pep.pdb', first='none', last='none'); g.read_coords('PEP','pep.pdb')
        g.patch('CYCP', [('PEP',str(npep)),('PEP','1')])
        if methyl_pos: g.patch('NMET', [('PEP',str(methyl_pos))])
    g.regenerate_angles(); g.regenerate_dihedrals()
    try: g.guess_coords()
    except Exception: pass
    psf=f'{kind}_{"m" if methyl_pos else "b"}.psf'; g.write_psf(filename=psf); g.write_pdb(filename=psf.replace(".psf",".pdb"))
    return psf

params=app.CharmmParameterSet('top.rtf','par.prm')
def energy(psf):
    p=app.CharmmPsfFile(psf)
    sysm=p.createSystem(params, nonbondedMethod=app.CutoffNonPeriodic, nonbondedCutoff=2.0*unit.nanometer,
                        constraints=app.HBonds, implicitSolvent=app.GBn2)
    pdb=app.PDBFile(psf.replace('.psf','.pdb'))
    integ=mm.LangevinMiddleIntegrator(300*unit.kelvin,1/unit.picosecond,0.001*unit.picoseconds)
    sim=app.Simulation(p.topology, sysm, integ, PLAT); sim.context.setPositions(pdb.positions)
    sim.minimizeEnergy(maxIterations=500)
    return sim.context.getState(getEnergy=True).getPotentialEnergy().value_in_unit(unit.kilocalorie_per_mole)

res={}
for label, kw in [('ligand_baseline',{}), ('ligand_methyl',{'methyl_pos':POS})]:
    try:
        psf=build('ligand', **kw); e=energy(psf); res[label]={'ok':True,'E_kcal':round(e,2)}
        print(label,'OK  E=',round(e,2))
    except Exception as ex:
        res[label]={'ok':False,'error':f'{type(ex).__name__}: {ex}'}
        print(label,'FAIL'); traceback.print_exc()
import json; json.dump(res, open('/opt/nm/status/nmethyl_smoke.json','w'), indent=2)
os.system('aws s3 cp /opt/nm/status/nmethyl_smoke.json '+os.environ.get('OUT_S3','')+'/status/nmethyl_smoke.json --only-show-errors 2>/dev/null' if os.environ.get('OUT_S3') else 'true')
print(json.dumps(res,indent=2))
PY
# sync result explicitly (OUT_S3 available in shell)
aws s3 cp /opt/nm/status/nmethyl_smoke.json "$OUT_S3/status/nmethyl_smoke.json" --only-show-errors || true
stage nm_complete
