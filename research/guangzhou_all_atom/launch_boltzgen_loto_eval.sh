#!/bin/bash
# launch_boltzgen_loto_eval.sh — Phase-2 LOTO eval: BASE vs FINE-TUNED BoltzGen on held-out cyclic
# targets — the ONE same-metric head-to-head for the cross-target SOTA comparison
# (docs/20261006_CROSS_TARGET_SOTA_COMPARISON.md). Per held-out complex it builds a peptide-anything
# pocket spec (same builder as boltzgen_ourtarget.sh) and designs twice:
#   base = default design checkpoints (boltzgen1_diverse+adherence)
#   ft   = our fine-tuned ckpt via --design_checkpoints (bgen-ft-full-20261006T073802Z/ckpt/finetuned.ckpt)
# then compares iptm / filter-RMSD per target. Spot-first, self-terminating, S3-streamed.
# SMOKE=1 -> 3 targets + NUM_DESIGNS=4 (validate ft-ckpt loads + 2-arm compare runs, cheaply).
# Params passed as ENV in the user-data (no fragile string injection); targets shipped as a file.
set -Eeuo pipefail
REGION=${REGION:-us-west-2}; export AWS_DEFAULT_REGION=$REGION
BUCKET=${BUCKET:-knowledge-datasets-1759951976}
AMI=${AMI:-ami-04f7da1c787a89267}
SG=${SG:-sg-011121fdf81073ec8}; KEY=${KEY:-biomate-trial-resume-20260912}
FT_CKPT_S3=${FT_CKPT_S3:-s3://$BUCKET/cyclic_peptide/runs/bgen-ft-full-20261006T073802Z/ckpt/finetuned.ckpt}
NUM_DESIGNS=${NUM_DESIGNS:-8}; BUDGET=${BUDGET:-2}
SMOKE=${SMOKE:-0}; MAX_RUNTIME=${MAX_RUNTIME:-5h}
TARGETS_FILE=${TARGETS_FILE:-/tmp/loto_targets.txt}
RUNID=bgen-loto-$([ "$SMOKE" = 1 ] && echo smoke || echo full)-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
[ -s "$TARGETS_FILE" ] || { echo "FATAL: no targets file at $TARGETS_FILE"; exit 1; }
echo "RUNID=$RUNID SMOKE=$SMOKE NUM_DESIGNS=$NUM_DESIGNS targets=$(wc -l < $TARGETS_FILE) FT=$FT_CKPT_S3"

# ship the held-out targets list + the driver
aws s3 cp "$TARGETS_FILE" "$S3RUN/code/targets.txt" --only-show-errors

cat > "/tmp/loto_driver.$$" <<'DRIVER'
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1
ROOT=/opt/boltzgen-run; mkdir -p "$ROOT/status" "$ROOT/specs" "$ROOT/cifs" "$ROOT/out"; cd "$ROOT"
exec > >(tee -a "$ROOT/status/loto.log") 2>&1
: "${OUT_S3:?}" "${FT_CKPT_S3:?}"; NUM_DESIGNS=${NUM_DESIGNS:-8}; BUDGET=${BUDGET:-2}; SMOKE=${SMOKE:-0}
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
sync_out(){ aws s3 sync "$ROOT/out" "$OUT_S3/out/" --only-show-errors --exclude "*" --include "*.csv" --include "*.json" --include "*.cif" --include "*.pdb" || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed || stage done_rc0; sync_out; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 4; shutdown -h now; exit $rc' EXIT
(while sleep 120; do sync_out; done) &

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl git && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
apt-get -o DPkg::Lock::Timeout=300 install -y -qq git curl
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda; source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda create -y -n bg -c conda-forge python=3.12; conda activate bg
pip install -q boltzgen gemmi numpy
git clone https://github.com/HannesStark/boltzgen "$ROOT/boltzgen" || true
export HF_HOME="$ROOT/hf_cache"; cd "$ROOT/boltzgen"
python -c "import boltzgen, torch, gemmi; print('boltzgen import ok; cuda', torch.cuda.is_available())"

stage fetch_inputs
aws s3 cp "$OUT_S3/code/targets.txt" "$ROOT/targets.txt" --only-show-errors
aws s3 cp "$FT_CKPT_S3" "$ROOT/finetuned.ckpt" --only-show-errors && echo "FT ckpt: $(du -h $ROOT/finetuned.ckpt|cut -f1)"
mapfile -t TARGETS < "$ROOT/targets.txt"
[ "$SMOKE" = 1 ] && { TARGETS=("${TARGETS[@]:0:3}"); NUM_DESIGNS=4; echo "SMOKE: 3 targets, NUM_DESIGNS=4"; }

build_spec(){
  local pdb="$1" recep="$2" pep="$3" L="$4"
  local cif="$ROOT/cifs/${pdb}.cif" spec="$ROOT/specs/${pdb}.yaml"
  curl -fsSL "https://files.rcsb.org/download/${pdb^^}.cif" -o "$cif" || { echo "download failed $pdb"; return 1; }
  PDB="$pdb" CIF="$cif" RECEP="$recep" PEP="$pep" NLEN="$L" SPEC="$spec" python - <<'PY'
import os, gemmi, numpy as np
cif=os.environ['CIF']; recep=os.environ['RECEP']; pep=os.environ['PEP']; L=int(os.environ['NLEN']); spec=os.environ['SPEC']
st=gemmi.read_structure(cif); st.setup_entities(); st.assign_label_seq_id(); model=st[0]
def is_aa(res):
    info=gemmi.find_tabulated_residue(res.name); return bool(info) and info.is_amino_acid()
def get_chain(name):
    for ch in model:
        if ch.name==name: return ch
    return None
def hcoords(res):
    return np.array([[a.pos.x,a.pos.y,a.pos.z] for a in res if a.element.name!='H'], dtype=float)
recep_ids=[c.strip() for c in recep.split(',') if c.strip()]
pc=get_chain(pep)
if pc is None or all(get_chain(r) is None for r in recep_ids):
    polys=sorted(model, key=lambda c: sum(is_aa(r) for r in c), reverse=True)
    pc = pc or (polys[1] if len(polys)>1 else polys[0])
    if all(get_chain(r) is None for r in recep_ids): recep_ids=[polys[0].name]
pres=[r for r in pc if r.name not in ('HOH','WAT','H2O','DOD')]
P=np.vstack([hcoords(r) for r in pres if len(hcoords(r))]) if pres else np.zeros((0,3))
assert len(P), "empty peptide coords"
inc_lines=[]; bind_lines=[]; report=[]
for rname in recep_ids:
    rc=get_chain(rname)
    if rc is None: continue
    rres=[r for r in rc if is_aa(r)]
    pocket=[i+1 for i,res in enumerate(rres) if len(hcoords(res)) and np.sqrt(((hcoords(res)[:,None,:]-P[None,:,:])**2).sum(-1)).min()<5.0]
    pocket=sorted(set(pocket))
    if not pocket: continue
    inc_lines.append(f"        - chain:\n            id: {rc.name}")
    bind_lines.append(f"        - chain:\n            id: {rc.name}\n            binding: {','.join(map(str,pocket))}")
    report.append(f"{rc.name}(n={len(pocket)})")
assert bind_lines, "empty pocket"
lo=max(7, min(L-2, 10)); hi=min(16, max(lo+1, L+2))
open(spec,'w').write(f"""entities:
  - protein:
      id: X
      sequence: {lo}..{hi}
      cyclic: true
  - file:
      path: {cif}
      include:
{chr(10).join(inc_lines)}
      binding_types:
{chr(10).join(bind_lines)}
""")
print(f"{os.environ['PDB']}: recep=[{' '.join(report)}] pep={pc.name} len={lo}..{hi}")
PY
}

run_arm(){  # pdb arm [extra flags...]
  local pdb="$1" arm="$2"; shift 2
  stage "design_${arm}_${pdb}"
  boltzgen run "$ROOT/specs/${pdb}.yaml" --protocol peptide-anything \
    --num_designs "$NUM_DESIGNS" --budget "$BUDGET" \
    --output "$ROOT/out/${arm}/${pdb}" --cache "$ROOT/hf_cache" "$@" 2>&1 | tail -20 \
    && echo "ARM_OK ${arm} ${pdb}" || echo "ARM_FAIL ${arm} ${pdb}"
  sync_out
}

for t in "${TARGETS[@]}"; do
  [ -z "$t" ] && continue
  set -- $t; pdb="$1"; recep="$2"; pep="$3"; L="$4"
  stage "prep_${pdb}"
  build_spec "$pdb" "$recep" "$pep" "$L" || { echo "spec_failed $pdb"; continue; }
  boltzgen check "$ROOT/specs/${pdb}.yaml" 2>&1 | tail -3 || { echo "check_failed $pdb"; continue; }
  run_arm "$pdb" base
  run_arm "$pdb" ft --design_checkpoints "$ROOT/finetuned.ckpt"
done

stage aggregating
python - <<'PY'
import glob, os, json, csv
root='/opt/boltzgen-run/out'; summ={}
def best(csvf):
    try: rows=list(csv.DictReader(open(csvf)))
    except Exception: return None
    if not rows: return None
    def g(r,keys):
        for k in r:
            if any(s in k.lower() for s in keys):
                try: return float(r[k])
                except: pass
        return None
    r=max(rows, key=lambda x:(g(x,['iptm','i_ptm']) or -1))
    return {'n':len(rows),'iptm':g(r,['iptm','i_ptm']),'ptm':g(r,['design_ptm','ptm']),'filter_rmsd':g(r,['filter','rmsd'])}
for arm in ('base','ft'):
    for d in glob.glob(f'{root}/{arm}/*'):
        cs=glob.glob(d+'/**/*metrics*.csv',recursive=True) or glob.glob(d+'/**/*.csv',recursive=True)
        if cs: summ.setdefault(os.path.basename(d),{})[arm]=best(sorted(cs)[0])
comp={}
for tgt,a in summ.items():
    if a.get('base') and a.get('ft'):
        bi,fi=a['base'].get('iptm'),a['ft'].get('iptm'); br,fr=a['base'].get('filter_rmsd'),a['ft'].get('filter_rmsd')
        comp[tgt]={'base':a['base'],'ft':a['ft'],
                   'd_iptm':round(fi-bi,3) if (fi is not None and bi is not None) else None,
                   'd_filter_rmsd':round(fr-br,3) if (fr is not None and br is not None) else None}
import statistics as st
di=[c['d_iptm'] for c in comp.values() if c['d_iptm'] is not None]
out={'n_targets_compared':len(comp),'mean_d_iptm':round(st.mean(di),3) if di else None,
     'per_target':summ,'head_to_head_ft_minus_base':comp,
     'note':'d_iptm>0 => ft higher interface confidence on HELD-OUT targets (never seen in FT); d_filter_rmsd<0 => ft more designable. Expected per survey: modest/NULL (structure-prior plateaus on novel targets).'}
json.dump(out, open('/opt/boltzgen-run/status/loto_summary.json','w'), indent=2)
print(json.dumps({k:out[k] for k in ('n_targets_compared','mean_d_iptm')}))
PY
aws s3 cp "$ROOT/status/loto_summary.json" "$OUT_S3/loto_summary.json" --only-show-errors || true
stage loto_complete
echo "=== LOTO DONE -> $OUT_S3/ ==="
DRIVER

aws s3 cp "/tmp/loto_driver.$$" "$S3RUN/code/driver.sh" --only-show-errors; echo "shipped driver + targets -> $S3RUN/code/"
UD=$(cat <<EOF | base64
#!/bin/bash
systemd-run --unit=loto-deadline --on-active=${MAX_RUNTIME} /sbin/shutdown -h now || shutdown -h +300 &
exec > /var/log/loto-boot.log 2>&1
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/boltzgen-run
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/driver.sh /opt/boltzgen-run/driver.sh && break; sleep 10; done
chmod +x /opt/boltzgen-run/driver.sh
OUT_S3=$S3RUN FT_CKPT_S3=$FT_CKPT_S3 NUM_DESIGNS=$NUM_DESIGNS BUDGET=$BUDGET SMOKE=$SMOKE bash /opt/boltzgen-run/driver.sh
EOF
)
declare -a COMBO=(
  "g5.2xlarge subnet-0254e4c3634b41bfc" "g5.2xlarge subnet-09e4dce46682a6c60"
  "g6.2xlarge subnet-0b35a6e2c1cf02dc2" "g5.2xlarge subnet-03b277a7a08d388c1"
  "g4dn.2xlarge subnet-0254e4c3634b41bfc"
)
try(){ local mode=$1 c T S opt; for c in "${COMBO[@]}"; do set -- $c; T=$1; S=$2
  [ "$mode" = spot ] && opt=(--instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}') || opt=()
  IID=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$T" ${KEY:+--key-name $KEY} \
    --subnet-id "$S" --security-group-ids "$SG" --iam-instance-profile Name=AutoimmuneCorpusProfile \
    "${opt[@]}" --instance-initiated-shutdown-behavior terminate \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":200,"VolumeType":"gp3"}}]' \
    --user-data "$UD" --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
    --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED [$mode] $T $S -> $IID"; return 0; }
  echo "  no capacity ($T $S)"; done; return 1; }
IID=""; try spot || { echo "spot exhausted -> on-demand"; try ondemand; } || true
rm -f "/tmp/loto_driver.$$"
[ -z "$IID" ] && { echo "FATAL: no GPU capacity"; exit 1; }
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"; echo "poll: aws s3 cp $S3RUN/status/status.json -"; echo "result: aws s3 cp $S3RUN/loto_summary.json -"
