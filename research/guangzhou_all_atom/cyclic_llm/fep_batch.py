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
MDRUN_CMD_READY = False

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
    out = dispatch_control_edge(run_id=rid, dry_run=not submit)
    print(json.dumps(out, indent=2, default=str))
