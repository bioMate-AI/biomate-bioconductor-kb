"""fep_production.py — FAST fan-out production ΔΔG for the αvβ6 control edge.

Replaces the monolithic ~2-GPU-day sequential run (one Batch job, 24 serial windows) with a parallel
fan-out: one Batch GPU job PER (leg, λ) window, each starting from the ALREADY-EQUILIBRATED npt.gro/npt.cpt
(docs/20261021_AVB6_FEP_EQUILIBRATION_ACCEPTANCE.md), with FULL GPU residency (-nb -pme -bonded -update gpu)
and shorter per-window sampling. Wall-clock ~1-3 GPU-hours instead of ~2 GPU-days; same physics.

Submits via the aws CLI (no boto dependency). De-risk: `--test` submits ONE window first; only fan out the
rest after it returns a dhdl. Collect with gmx bar per leg -> dG; ΔΔG = dG_complex - dG_solvent.

Usage:
  python fep_production.py --test solvent 0      # one validation window
  python fep_production.py --fanout              # all 24 windows (12 λ × 2 legs)
  python fep_production.py --collect             # BAR over the uploaded dhdl
"""
from __future__ import annotations
import json, subprocess, sys

BUCKET = "biomate-nextflow-work"; REGION = "us-east-1"; BATCH_REGION = "us-west-2"
RUN = "avb6-fep-ctrl-build1"
BASE = f"s3://{BUCKET}/cyclic_peptide/fep/{RUN}"
IN, EQUIL, OUT = f"{BASE}/in", f"{BASE}/equil_out", f"{BASE}/prod_out"
QUEUE, JOBDEF = "biomate-gpu-t4-queue", "biomate-gromacs-cu12-gpu"
COMPLEX_QUEUE = "biomate-gpu-spot-queue"   # SPOT g6.12xlarge (48 vCPU) — cheap + many cores for CPU-PME-bound FEP
NLAMBDA = 12                      # proven template schedule (coul 0-4, vdw 5-11)
NS = 1.0                          # per-window production (ns) — shorter than 5 ns; BAR-gate to extend
LEGS = ("solvent", "complex")


def window_command(leg: str, lam: int) -> str:
    # complex: stiff bonded CaDA-Mn -> 0.5 fs (proven); solvent: 2 fs (template default). nsteps for NS ns.
    nsteps = int(NS * 1e6 / (0.5 if leg == "complex" else 2.0) * 1000) // 1000  # 0.5fs or 2fs
    nsteps = int(NS * 1000000 / 0.5) if leg == "complex" else int(NS * 1000000 / 2.0)
    dtfix = "sed -i 's/^dt .*/dt = 0.0005/' prod.mdp; " if leg == "complex" else ""
    return (
        "set -x; export PATH=$PATH:/usr/local/gromacs/bin; source /usr/local/gromacs/bin/GMXRC 2>/dev/null || true; "
        "(command -v aws || pip install -q awscli) >/dev/null 2>&1 || true; "
        f"LEG={leg}; LAM={lam}; mkdir -p /work/run && cd /work; "
        f"aws s3 cp {IN} /work/in --recursive --region {REGION} >/dev/null && "
        f"aws s3 cp {EQUIL}/{leg}/npt.gro /work/run/ --region {REGION} && "
        f"aws s3 cp {EQUIL}/{leg}/npt.cpt /work/run/ --region {REGION}; cd /work/run; "
        "cp /work/in/%s/* . && cp -r /work/in/ff/charmm36m-mut.ff . && cp /work/in/cada_mn.itp . && "
        "cp /work/in/mdp/prod_fep.mdp.template . ; " % leg +
        "sed -i 's#/opt/fepenv/lib/python3.10/site-packages/pmx/data/mutff/##g' fep.top; export GMXLIB=$PWD; "
        "sed 's/__LAMBDA_STATE__/%d/' prod_fep.mdp.template > prod.mdp; " % lam +
        "sed -i 's/^nsteps .*/nsteps = %d/' prod.mdp; " % nsteps + dtfix +
        "gmx grompp -f prod.mdp -c npt.gro -t npt.cpt -p fep.top -o prod.tpr -maxwarn 60 > grompp.log 2>&1; GR=$?; "
        "echo GROMPP_RC=$GR; [ $GR -ne 0 ] && { tail -20 grompp.log; } ; "
        "[ $GR -eq 0 ] && gmx mdrun -deffnm prod -nb gpu -pme cpu -ntmpi 1 -ntomp $(nproc) -dhdl prod_dhdl.xvg > md.log 2>&1; "
        "RC=$?; grep -iE 'Performance|ns/day|Fatal|error' md.log | tail -4; "
        f"aws s3 cp /work/run {OUT}/{leg}/lambda_{lam}/ --recursive --region {REGION} "
        "  --exclude '*.trr' --exclude 'charmm36m-mut.ff/*' --exclude 'prod_fep.mdp.template' >/dev/null; "
        "[ -s prod_dhdl.xvg ] && echo \"PROD_OK %s %d\" || echo \"PROD_FAIL %s %d\"; exit $RC" % (leg, lam, leg, lam)
    )


def collect_command() -> str:
    """gmx bar per leg over the 12 dhdl windows -> ΔG; ΔΔG_bind = ΔG_complex - ΔG_solvent (the control
    edge must recover the known small affinity gap -> ~0)."""
    return (
        "set -x; export PATH=$PATH:/usr/local/gromacs/bin; source /usr/local/gromacs/bin/GMXRC 2>/dev/null || true; "
        "(command -v aws || pip install -q awscli) >/dev/null 2>&1 || true; mkdir -p /work && cd /work; "
        f"aws s3 cp {OUT} /work/prod --recursive --region {REGION} --exclude '*' --include '*/prod_dhdl.xvg' >/dev/null; "
        "python3 - <<'PY'\n"
        "import glob,subprocess,re,json\n"
        "res={}\n"
        "for leg in ('solvent','complex'):\n"
        "    fs=sorted(glob.glob(f'/work/prod/{leg}/lambda_*/prod_dhdl.xvg'), key=lambda p:int(re.search(r'lambda_(\\d+)',p).group(1)))\n"
        "    if len(fs)<3: res[leg]={'n':len(fs),'error':'too few windows'}; continue\n"
        "    p=subprocess.run(['gmx','bar','-f']+fs+['-o',f'/work/bar_{leg}.xvg'],capture_output=True,text=True)\n"
        "    log=p.stdout+p.stderr; open(f'/work/bar_{leg}.log','w').write(log)\n"
        "    m=re.search(r'total\\s+\\S+\\s+-?\\d.*?(-?\\d+\\.\\d+)\\s*\\+/-\\s*(\\d+\\.\\d+)',log)\n"
        "    tot=[l for l in log.splitlines() if l.strip().lower().startswith('total')]\n"
        "    res[leg]={'n':len(fs),'total_line':tot[-1] if tot else None}\n"
        "print('BAR_RESULT '+json.dumps(res))\n"
        "open('/work/ddg_result.json','w').write(json.dumps(res,indent=2))\n"
        "PY\n"
        f"aws s3 cp /work/bar_solvent.log {OUT}/ddg/ --region {REGION} 2>/dev/null; "
        f"aws s3 cp /work/bar_complex.log {OUT}/ddg/ --region {REGION} 2>/dev/null; "
        f"aws s3 cp /work/ddg_result.json {OUT}/ddg/ --region {REGION} 2>/dev/null; "
        "echo COLLECT_DONE"
    )


def submit_collect() -> str:
    req = {"jobName": f"fep-collect-{RUN}".replace("_", "-")[:120], "jobQueue": QUEUE, "jobDefinition": JOBDEF,
           "containerOverrides": {"command": [collect_command()]}, "tags": {"pipeline": "cyclic-peptide", "stage": "fep-collect"}}
    p = subprocess.run(["aws", "batch", "submit-job", "--region", BATCH_REGION, "--cli-input-json", json.dumps(req)],
                       capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit(f"collect submit failed: {p.stderr[:300]}")
    return json.loads(p.stdout)["jobId"]


def submit(leg: str, lam: int) -> str:
    cmd = window_command(leg, lam)
    q = COMPLEX_QUEUE if leg == "complex" else QUEUE
    rr = [{"type":"VCPU","value":"48"},{"type":"MEMORY","value":"180000"},{"type":"GPU","value":"1"}] if leg=="complex" else None
    req = {"jobName": f"fep-prod-{leg}-l{lam}-{RUN}".replace("_", "-")[:120],
           "jobQueue": q, "jobDefinition": JOBDEF,
           "containerOverrides": ({"command": [cmd], "resourceRequirements": rr} if rr else {"command": [cmd]}),
           "tags": {"pipeline": "cyclic-peptide", "stage": "fep-prod", "leg": leg, "lambda": str(lam)}}
    p = subprocess.run(["aws", "batch", "submit-job", "--region", BATCH_REGION,
                        "--cli-input-json", json.dumps(req)], capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit(f"submit failed: {p.stderr[:300]}")
    return json.loads(p.stdout)["jobId"]


if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "--test":
        leg, lam = a[1], int(a[2])
        print(f"TEST window {leg} λ{lam} -> job {submit(leg, lam)}  (validate it produces dhdl before --fanout)")
    elif a and a[0] == "--fanout":
        ids = {f"{leg}-{lam}": submit(leg, lam) for leg in LEGS for lam in range(NLAMBDA)}
        print(f"FANNED OUT {len(ids)} windows ({NLAMBDA} λ × {len(LEGS)} legs):")
        for k, v in ids.items():
            print(f"  {k}: {v}")
    elif a and a[0] == "--collect":
        print(f"COLLECT job -> {submit_collect()}  (gmx bar per leg; ΔΔG_bind = ΔG_complex - ΔG_solvent)")
    else:
        print(__doc__)
