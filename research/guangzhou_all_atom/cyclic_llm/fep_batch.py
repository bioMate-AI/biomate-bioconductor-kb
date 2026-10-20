#!/usr/bin/env python3
"""fep_batch.py — route the αvβ6 relative-FEP CONTROL EDGE through AWS Batch (GROMACS GPU-spot).

Parallel to physics_batch.py (which dispatches Boltz cofold). This dispatches the CaDA-Mn
relative-FEP control edge designed in docs/20261019_AVB6_CADA_AND_FEP_SETUP.md.

AUDITED INFRA (read-only, 2026-10-19):
  queue   biomate-gpu-spot-queue        ENABLED / VALID (spot GPU)
  job-def biomate-gromacs-cu12-gpu      ACTIVE  (image biomate/gromacs-cuda:2024-cu12, GPU=1)

THE EDGE (control <-> control, the A2 anchor):
  state A = CTRL-TRIVEHEXIN arm  YRGDLAYPK  (Tyr1, Tyr7)
  state B = CTRL-AVEBEHEXIN      FRGDLAFPK  (Phe1, Phe7)
  => a double Y->F perturbation (remove two aromatic -OH). Both states are standard
     L-amino-acid 9-mers already parameterized in CHARMM36m — NO custom ligand FF needed.
  Inputs (metal-complete poses, gate-admissible): results/poses/CTRL-{TRIVEHEXIN,AVEBEHEXIN}_metal.cif
  ddG_bind = dG_complex(A->B) - dG_solvent(A->B); MUST recover the small known affinity gap of
  two known binders. Only if that edge is recovered is the candidate ladder admissible.

SAFETY — dry_run=True by DEFAULT: validates the real queue+job-def exist, emits the exact submit
payload, SPENDS NOTHING. A live submit (--submit) is ONE spot GPU job (~1 GPU-day) and is gated on:
  (1) a review note (docs/20261019_AVB6_FEP_CONTROL_EDGE_REVIEW.md), AND
  (2) the IN-CONTAINER grompp PREFLIGHT passing — the command below runs pmx hybrid-topology
      generation + `gmx grompp` on CPU and EXITS NON-ZERO before any mdrun if the CaDA-Mn /
      hybrid topology does not parse. That makes a broken topology fail fast + cheap (no GPU
      burn), but it does NOT substitute for local validation: this module is wired and
      infra-validated; the topology itself is NOT yet locally validated (no GROMACS on the
      author's box), so the default stays dry_run. See the review note.

Spot only. Self-terminating. Relative-within-target. Ground truth = wet-lab assay.
"""
import os, sys, json, time

REGION = "us-west-2"
QUEUE  = "biomate-gpu-spot-queue"
JOBDEF = "biomate-gromacs-cu12-gpu"
BUCKET = "biomate-nextflow-work"
PREFIX = "cyclic_peptide/fep"

HERE = os.path.dirname(os.path.abspath(__file__))
FEP  = os.path.join(os.path.dirname(HERE), "fep")

# _fep_command below still builds the pmx hybrid IN-CONTAINER (impossible: image has no pip). Once the
# OFFLINE build (fep/build_fep_inputs.sh) stages the hybrid+solvated legs + em.tpr under in/ with the
# FEP_INPUTS_READY sentinel, _fep_command must be REWRITTEN to mdrun-only (em->nvt->npt->per-lambda HREX
# on the staged fep.top + ionized.gro, NO pmx). This flag gates --submit until that rewrite is done.
MDRUN_CMD_READY = False     # FULL per-lambda production ddG stays GUARDED until the user's explicit go
EQUIL_CMD_READY = True       # SHORT equilibration (em->nvt->npt only) is authorized (user chose (a))

CONTROL_EDGE = {
    "edge_id": "CTRL-TRIVEHEXIN__to__CTRL-AVEBEHEXIN",
    "state_A": {"name": "CTRL-TRIVEHEXIN", "seq": "YRGDLAYPK",
                "pose": "results/poses/CTRL-TRIVEHEXIN_metal.cif"},
    "state_B": {"name": "CTRL-AVEBEHEXIN", "seq": "FRGDLAFPK",
                "pose": "results/poses/CTRL-AVEBEHEXIN_metal.cif"},
    "mutations": ["TYR1PHE", "TYR7PHE"],
    "n_windows": 12,
    "ns_per_window": 5,
}


def _boto(svc):
    import boto3
    return boto3.client(svc, region_name=REGION)


def _equil_command(in_s3, out_s3, legs="solvent complex", metal_model="bonded"):
    """SHORT equilibration ONLY (em -> NVT -> NPT), on the staged inputs. NOT production FEP.
    Image ENTRYPOINT is ['/bin/bash','-c'] -> the command MUST be a SINGLE script string.

    The COMPLEX leg carries the CaDA Mn (stiff M-D/D-D dummy bonds, k~669440 kJ/mol/nm^2, r0~0.09 nm).
    Steep EM stalls at machine precision with a large residual force ON THE Mn CENTER (atom 16428, res
    1080 MN2) and dt=2 fs then SIGSEGVs at NVT step 0 -- the stiff short dummy bonds are unstable at 2 fs.
    The solvent leg (no Mn) is fine at 2 fs. So the complex leg gets: (1) re-idealize each CaDA octahedron
    (reset D1..D6 to center +/- 0.09 nm along axes) to zero the bonded strain EM could not relieve, and
    (2) a SMALL timestep (NVT 0.2 fs, NPT 0.5 fs). Solvent leg keeps the standard 2 fs protocol.
    (Production note: dt<=0.5 fs makes the 2-GPU-day ddG ~4-8x costlier -> reformulating the CaDA dummies
    as VIRTUAL SITES, which need no timestep reduction, is the right build-level fix before production.)"""
    # ALL tprs are grompp'd ON the GPU box from the version-independent ionized.gro + fep.top -- the staged
    # em.tpr is NOT used (it was written by the build box's GROMACS 2026/tpx-138, unreadable by this image's
    # GROMACS 2024/tpx-133: "reading tpx file version 138 with version 133 program"). Chain fails loudly:
    # the && chain stops at the first failed stage, RC propagates, and the job exits non-zero so a Batch
    # SUCCEEDED means NVT+NPT genuinely completed. Logs are uploaded on success AND failure.
    s = (
        "set -x; export PATH=$PATH:/usr/local/gromacs/bin; source /usr/local/gromacs/bin/GMXRC 2>/dev/null || true; "
        "(command -v aws || pip install -q awscli 2>/dev/null) >/dev/null 2>&1 || true; "
        f"  METAL={metal_model}; UPD=''; [ \"$METAL\" = vsite ] && UPD='-update cpu'; "  # vsite: constraints/update on CPU (GPU update is stricter on coupled constraints)
        "mkdir -p /work && cd /work; "
        f"aws s3 cp {in_s3} /work/in --recursive --region {REGION}; RC=0; "
        f"for leg in {legs}; do "
        "  echo EQUIL_LEG_START $leg metal=$METAL; mkdir -p /work/$leg && cd /work/$leg; "
        "  cp /work/in/$leg/* . 2>/dev/null; cp -r /work/in/ff/charmm36m-mut.ff .; cp /work/in/mdp/*.mdp .; "
        "  sed -i 's#/opt/fepenv/lib/python3.10/site-packages/pmx/data/mutff/##g' fep.top; export GMXLIB=$PWD; "
        "  printf 'nstxout-compressed = 5000\\n' >> nvt.mdp; printf 'nstxout-compressed = 5000\\n' >> npt.mdp; "
        "  NVTC=em.gro; "
        # ---- COMPLEX leg metal-model handling ----
        "  if [ \"$leg\" = complex ]; then "
        "    if [ \"$METAL\" = vsite ]; then "
        # vsite CaDA = rigid cluster -> STANDARD dt=2fs (same protocol as the working solvent leg); swap the itp
        "      cp /work/in/cada_mn_vsite.itp cada_mn.itp && echo 'VSITE_ITP_SWAPPED'; "
        # harder LINCS for the coupled rigid CaDA cluster (K4) that failed at default order 4
        "      for f in em.mdp nvt.mdp npt.mdp; do printf 'lincs-order = 8\\nlincs-iter = 2\\n' >> $f; done; "
        "    else "
        # bonded CaDA = stiff bonds -> small timestep (fallback)
        "      sed -i 's/^dt .*/dt = 0.0002/; s/^nsteps .*/nsteps = 100000/' nvt.mdp; "   # 20 ps @ 0.2 fs
        "      sed -i 's/^dt .*/dt = 0.0005/; s/^nsteps .*/nsteps = 200000/' npt.mdp; "   # 100 ps @ 0.5 fs
        "    fi; "
        "  fi; "
        # ---- EM (steep) ----
        "  gmx grompp -f em.mdp -c ionized.gro -p fep.top -o em.tpr -maxwarn 50 > em_grompp.log 2>&1 "
        "  && gmx mdrun -deffnm em -ntmpi 1 -nb gpu > em.log 2>&1 && [ -f em.gro ] ; STG=$?; "
        # ---- BONDED-complex only: reset each CaDA octahedron (D1..D6 = Mn center +/- 0.09 nm) to zero bonded strain ----
        "  if [ \"$leg\" = complex ] && [ \"$METAL\" != vsite ] && [ \"$STG\" -eq 0 ]; then "
        "    python3 - em.gro em_fixed.gro <<'PYEOF' > reidealize.log 2>&1 && NVTC=em_fixed.gro || STG=97\n"
        "import sys\n"
        "L=open(sys.argv[1]).read().splitlines(); n=int(L[1]); body=L[2:2+n]; box=L[2+n:]\n"
        "cent={}\n"
        "for ln in body:\n"
        "    if ln[5:10].strip()=='MN2' and ln[10:15].strip()=='MN': cent[ln[0:5]]=(float(ln[20:28]),float(ln[28:36]),float(ln[36:44]))\n"
        "off={'D1':(0.09,0,0),'D2':(-0.09,0,0),'D3':(0,0.09,0),'D4':(0,-0.09,0),'D5':(0,0,0.09),'D6':(0,0,-0.09)}\n"
        "out=[]\n"
        "for ln in body:\n"
        "    a=ln[10:15].strip(); r=ln[0:5]\n"
        "    if ln[5:10].strip()=='MN2' and a in off and r in cent:\n"
        "        c=cent[r]; d=off[a]; out.append(ln[:20]+'%8.3f%8.3f%8.3f'%(c[0]+d[0],c[1]+d[1],c[2]+d[2])+ln[44:])\n"
        "    else: out.append(ln)\n"
        "open(sys.argv[2],'w').write(L[0]+'\\n'+str(n)+'\\n'+'\\n'.join(out)+'\\n'+'\\n'.join(box)+'\\n')\n"
        "print('REIDEALIZE_OK centers=%d'%len(cent))\n"
        "PYEOF\n"
        "  fi; "
        # ---- NVT -> NPT ----
        "  [ \"$STG\" -eq 0 ] && { gmx grompp -f nvt.mdp -c $NVTC -r $NVTC -p fep.top -o nvt.tpr -maxwarn 50 > nvt_grompp.log 2>&1 "
        "    && gmx mdrun -deffnm nvt -ntmpi 1 -nb gpu $UPD > nvt.log 2>&1 && [ -f nvt.gro ] "
        "    && gmx grompp -f npt.mdp -c nvt.gro -r nvt.gro -t nvt.cpt -p fep.top -o npt.tpr -maxwarn 50 > npt_grompp.log 2>&1 "
        "    && gmx mdrun -deffnm npt -ntmpi 1 -nb gpu $UPD > npt.log 2>&1 && [ -f npt.gro ] ; STG=$?; }; "
        "  printf 'Potential\\nTemperature\\nPressure\\nDensity\\n' | gmx energy -f npt.edr -o ${leg}_ener.xvg > ${leg}_energy.log 2>&1 || true; "
        "  echo \"$leg ENERGY:\"; grep -iE '^(Potential|Temperature|Pressure|Density)' ${leg}_energy.log | head; "
        "  LW=$(grep -i 'LINCS WARNING' *.log 2>/dev/null | wc -l); FA=$(grep -i 'Fatal error' *.log 2>/dev/null | wc -l); "
        "  echo \"$leg STABILITY stage_rc=$STG LINCS_WARN=$LW FATAL=$FA npt_gro=$([ -f npt.gro ] && echo yes || echo no)\"; "
        f"  aws s3 cp /work/$leg {out_s3}$leg/ --recursive --region {REGION} --exclude '*.trr' --exclude 'charmm36m-mut.ff/*' --exclude '*.itp' --exclude 'ionized.gro'; "
        "  if [ \"$STG\" -eq 0 ] && [ -f npt.gro ] && [ \"$LW\" -eq 0 ] && [ \"$FA\" -eq 0 ]; then echo \"$leg:EQUIL_OK\"; else echo \"$leg:EQUIL_FAIL\"; RC=1; fi; "
        "  cd /work; done; "
        "  [ $RC -eq 0 ] && echo EQUIL_ALL_OK || echo EQUIL_FAILED; exit $RC"
    )
    return [s]


def dispatch_equilibration(run_id, dry_run=True, legs="solvent complex", metal_model="bonded"):
    """Dispatch the SHORT equilibration job to the GROMACS GPU-spot job-def. Requires the FEP_INPUTS_READY
    sentinel; gated by EQUIL_CMD_READY. `legs` selects legs; `metal_model` = bonded (small-dt) | vsite (2fs)."""
    base = f"s3://{BUCKET}/{PREFIX}/{run_id}"
    # separate output prefix per metal model so the bonded cross-check and the vsite run don't clobber
    out_dir = "equil_out" if metal_model == "bonded" else f"equil_out_{metal_model}"
    in_s3, out_s3 = f"{base}/in/", f"{base}/{out_dir}/"
    payload = dict(
        jobName=f"equil-{metal_model}-{run_id}".replace("_", "-")[:120],
        jobQueue=QUEUE, jobDefinition=JOBDEF,
        containerOverrides=dict(command=_equil_command(in_s3, out_s3, legs=legs, metal_model=metal_model)),
        # Spot resilience: auto-retry a SPOT RECLAIM (host terminated), but EXIT on a real non-zero
        # container exit so a true physics/LINCS crash still fails loudly (not retried into the same wall).
        retryStrategy=dict(attempts=3, evaluateOnExit=[
            dict(onStatusReason="Host EC2*", action="RETRY"),   # spot interruption / host terminated -> retry
            dict(onExitCode="*", action="EXIT"),                # any real container exit -> fail loudly
        ]),
        tags={"pipeline": "cyclic-peptide", "stage": "equilibration", "target": "avb6",
              "edge": CONTROL_EDGE["edge_id"]},
    )
    validated = {}
    try:
        b = _boto("batch")
        qs = b.describe_job_queues(jobQueues=[QUEUE])["jobQueues"]
        jds = b.describe_job_definitions(jobDefinitionName=JOBDEF, status="ACTIVE")["jobDefinitions"]
        validated = {"queue_state": (qs[0]["state"] if qs else None), "jobdef_active": bool(jds)}
    except Exception as e:
        validated = {"validation_error": f"{type(e).__name__}: {str(e)[:150]}"}
    if dry_run:
        return {"dry_run": True, "mode": "equilibration", "would_submit": payload,
                "validated": validated, "in_s3": in_s3, "result_prefix": out_s3}
    if not EQUIL_CMD_READY:
        return {"submitted": False, "REFUSED": "EQUIL_CMD_READY is False"}
    try:
        _boto("s3").head_object(Bucket=BUCKET, Key=f"{PREFIX}/{run_id}/in/FEP_INPUTS_READY")
    except Exception:
        return {"submitted": False, "REFUSED": "FEP_INPUTS_READY not staged for %s" % run_id}
    jid = _boto("batch").submit_job(**payload)["jobId"]
    return {"submitted": True, "mode": "equilibration", "submitted_job_id": jid,
            "result_prefix": out_s3, "note": "em->nvt->npt both legs; NOT production ddG"}


def _fep_command(in_s3, out_s3):
    """Container command: pull inputs; pmx hybrid topology; grompp PREFLIGHT (fail fast, CPU);
    only then em -> nvt -> npt -> 12-window HREX production on GPU; upload. The preflight gate
    is the `grompp ... || exit 7` lines — a broken CaDA/hybrid topology costs seconds, not a GPU-day."""
    return ["bash", "-c",
            "set -ex; (which aws || pip install -q awscli); "
            f"mkdir -p /work && cd /work; aws s3 cp {in_s3} /work/in --recursive; "
            # --- pmx hybrid topology for the Y->F double perturbation (fail fast if pmx absent) ---
            "(which pmx || pip install -q pmx) || { echo 'PMX_MISSING'; exit 6; }; "
            "python -m pmx mutate -f /work/in/stateA.pdb -o /work/hybrid.pdb "
            "  --script /work/in/mutations.txt --keep_resid || { echo 'PMX_HYBRID_FAIL'; exit 6; }; "
            # --- grompp PREFLIGHT on CPU: parse topology incl. cada_mn.itp; exit before GPU if broken ---
            "gmx grompp -f /work/in/mdp/em.mdp -c /work/solv_ions.gro -p /work/topol.top "
            "  -o /work/em.tpr -maxwarn 2 || { echo 'GROMPP_PREFLIGHT_FAIL'; exit 7; }; "
            "echo GROMPP_PREFLIGHT_OK; "
            # --- em -> nvt -> npt ---
            "gmx mdrun -deffnm em -ntmpi 1; "
            "gmx grompp -f /work/in/mdp/nvt.mdp -c em.gro -r em.gro -p topol.top -o nvt.tpr -maxwarn 2; "
            "gmx mdrun -deffnm nvt -nb gpu; "
            "gmx grompp -f /work/in/mdp/npt.mdp -c nvt.gro -r nvt.gro -t nvt.cpt -p topol.top -o npt.tpr -maxwarn 2; "
            "gmx mdrun -deffnm npt -nb gpu; "
            # --- 12-window HREX production (both legs are built the same way; complex shown) ---
            "for L in $(seq 0 11); do "
            "  sed s/__LAMBDA_STATE__/$L/ /work/in/mdp/prod_fep.mdp.template > prod_$L.mdp; "
            "  gmx grompp -f prod_$L.mdp -c npt.gro -t npt.cpt -p topol.top -o prod_$L.tpr -maxwarn 2; "
            "done; "
            "gmx mdrun -multidir $(seq 0 11) -deffnm prod -replex 1000 -nb gpu || "
            "  { for L in $(seq 0 11); do gmx mdrun -deffnm prod_$L -nb gpu; done; }; "
            # --- BAR estimate + upload ---
            "gmx bar -f prod_*/prod.xvg -o bar.xvg | tee /work/ddG.txt || true; "
            f"aws s3 cp /work {out_s3} --recursive --exclude '*.trr'; echo FEP_BATCH_DONE"]


def dispatch_control_edge(run_id=None, dry_run=True):
    """Dispatch the ONE control-edge FEP job to the GROMACS GPU-spot job-def.
    dry_run=True (default): validate real queue+job-def, emit payload, SPEND NOTHING."""
    run_id = run_id or f"avb6-fep-ctrl-{int(time.time())}"
    base   = f"s3://{BUCKET}/{PREFIX}/{run_id}"
    in_s3, out_s3 = f"{base}/in/", f"{base}/out/"
    payload = dict(
        jobName=f"fep-{run_id}".replace("_", "-")[:120],
        jobQueue=QUEUE, jobDefinition=JOBDEF,
        containerOverrides=dict(command=_fep_command(in_s3, out_s3)),
        tags={"pipeline": "cyclic-peptide", "stage": "fep", "target": "avb6",
              "edge": CONTROL_EDGE["edge_id"]},
    )
    validated = {}
    try:
        b = _boto("batch")
        qs = b.describe_job_queues(jobQueues=[QUEUE])["jobQueues"]
        jds = b.describe_job_definitions(jobDefinitionName=JOBDEF, status="ACTIVE")["jobDefinitions"]
        validated = {
            "queue_exists": bool(qs), "queue_state": (qs[0]["state"] if qs else None),
            "jobdef_active": bool(jds),
            "jobdef_image": (jds[0]["containerProperties"]["image"] if jds else None),
            "edge": CONTROL_EDGE["edge_id"], "mutations": CONTROL_EDGE["mutations"],
            "inputs_present": {s["name"]: os.path.exists(os.path.join(os.path.dirname(HERE), s["pose"]))
                               for s in (CONTROL_EDGE["state_A"], CONTROL_EDGE["state_B"])},
            "cada_itp_present": os.path.exists(os.path.join(FEP, "forcefield", "cada_mn.itp")),
        }
    except Exception as e:
        validated = {"validation_error": f"{type(e).__name__}: {str(e)[:150]}"}
    if dry_run:
        return {"dry_run": True, "would_submit": payload, "validated": validated,
                "in_s3": in_s3, "result_prefix": out_s3,
                "PREFLIGHT_BLOCKER": "topology not locally validated (no GROMACS on author box); "
                                     "live submit gated on in-container grompp preflight passing"}
    # REAL submit — GATED. A relative FEP RUN needs the pmx hybrid (A->B dual-state) topology + a
    # fully solvated/equilibrated system. The GROMACS image has NO pip/pmx (proven 2026-10-20), so the
    # hybrid CANNOT be built in-container; and the preflight validated FF-ASSEMBLY/grompp of the
    # components, NOT the alchemical hybrid or a solvated complex. The GPU job must therefore run
    # mdrun on a PRE-BUILT (offline, gromacs+pmx) system. Refuse to submit until that system is staged,
    # signalled by an `in/FEP_INPUTS_READY` sentinel. This prevents firing a job that would download
    # nothing and die at the pmx step (predicted-failure spend). See docs/20261019_AVB6_FEP_CONTROL_EDGE_REVIEW.md.
    if not MDRUN_CMD_READY:
        return {"dry_run": False, "submitted": False,
                "REFUSED": "_fep_command still does in-container pmx (impossible). Rewrite it to mdrun-only "
                           "on the staged hybrid legs, then set MDRUN_CMD_READY=True. (Done at submit hand-back.)"}
    ready_key = f"{PREFIX}/{run_id}/in/FEP_INPUTS_READY"
    try:
        _boto("s3").head_object(Bucket=BUCKET, Key=ready_key)
    except Exception:
        return {"dry_run": False, "submitted": False,
                "REFUSED": "FEP inputs not staged -> submit would produce a predicted-failure job "
                           "(no inputs + image has no pip/pmx). Build the hybrid + solvated system OFFLINE "
                           "(gromacs+pmx: pdb2gmx -> pmx mutate charmm36m-mut -> gentop -> solvate/genion, "
                           "both legs, per-lambda .tpr), stage under in/ with an FEP_INPUTS_READY sentinel, "
                           "then re-run --submit. The GPU job then runs mdrun only.",
                "expected_ready_key": f"s3://{BUCKET}/{ready_key}", "in_s3": in_s3}
    jid = _boto("batch").submit_job(**payload)["jobId"]
    return {"dry_run": False, "submitted_job_id": jid, "in_s3": in_s3, "result_prefix": out_s3}


if __name__ == "__main__":
    submit = "--submit" in sys.argv
    rid = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--run-id=")), None)
    if "--equil" in sys.argv:          # SHORT equilibration (em->nvt->npt); NOT production ddG
        legs = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--legs=")), "solvent complex").replace(",", " ")
        metal = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--metal=")), "bonded")
        out = dispatch_equilibration(run_id=rid, dry_run=not submit, legs=legs, metal_model=metal)
    else:                              # FULL per-lambda production ddG (stays guarded by MDRUN_CMD_READY)
        out = dispatch_control_edge(run_id=rid, dry_run=not submit)
    print(json.dumps(out, indent=2, default=str))
