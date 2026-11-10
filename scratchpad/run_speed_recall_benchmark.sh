#!/usr/bin/env bash
# ==========================================================================
# proteomics DB-search speed+recall head-to-head  (Comet vs Sage vs Sage+Mokapot)
# on a LARGE human protein DB with entrapment. Runs entirely on the spot box in the
# exact license-clean quay biocontainers; streams every artifact to S3 as it goes.
#
# Fair-comparison controls (survey §14.4): identical target+entrapment+decoy FASTA,
# identical enzyme/mods/tolerances, same box + thread count, same downstream FDR
# estimator (scripts/score_proteomics_search_benchmark.py). Speed = /usr/bin/time -v
# (wall clock + peak RSS), machine-measured, never tool self-report.
# ==========================================================================
set -uo pipefail
S3=s3://biomate-nextflow-work/proteomics_speed_recall_20260929
REGION=us-west-2
THREADS=16
WORK=/mnt/bench
LOG=$WORK/run.log

mkdir -p $WORK && cd $WORK
exec > >(tee -a $LOG) 2>&1
echo "=== START $(date -u) on $(hostname) ==="
sync_s3(){ aws s3 cp "$1" "$S3/$2" --region $REGION --only-show-errors 2>&1 || true; }
note(){ echo "[$(date -u +%H:%M:%S)] $*"; }

# ---- 0. tools: docker + awscli already on AL2023 via user-data preamble ----
docker --version || { note "docker missing"; }
aws --version

COMET_IMG=quay.io/biocontainers/openms-thirdparty:3.4.1--h9ee0642_1
SAGE_IMG=quay.io/biocontainers/sage-proteomics:0.14.7--h031d066_0
MOKAPOT_IMG=quay.io/biocontainers/mokapot:0.10.0--pyhdfd78af_0
TRFP_IMG=quay.io/biocontainers/thermorawfileparser:1.4.5--h05cac1d_1
PY_IMG=quay.io/biocontainers/pyteomics:4.7.2--pyhdfd78af_0

note "pulling images"
for img in $COMET_IMG $SAGE_IMG $MOKAPOT_IMG $TRFP_IMG $PY_IMG; do docker pull -q $img || note "pull failed $img"; done

# ---- 1. LARGE DB: human UniProt reviewed (SwissProt ~20k) ----
note "download human SwissProt (reviewed)"
curl -sL --retry 5 -o human.fasta.gz \
  "https://rest.uniprot.org/uniprotkb/stream?query=reviewed:true+AND+organism_id:9606&format=fasta&compressed=true"
gunzip -f human.fasta.gz
NTARGET=$(grep -c '^>' human.fasta)
note "human.fasta proteins = $NTARGET"
sync_s3 human.fasta db/human.fasta

# ---- 2. build target + entrapment(shuffled) + decoy FASTA (identical for every engine) ----
note "build combined DB (entrapment ratio 1.0, decoys reversed)"
aws s3 cp $S3/code/prepare_search_db.py prepare_search_db.py --region $REGION --only-show-errors
aws s3 cp $S3/code/normalize_idxml.py normalize_idxml.py --region $REGION --only-show-errors
python3 prepare_search_db.py --target human.fasta \
  --entrapment-source shuffled_target --entrapment-ratio 1.0 --seed 42 \
  --out combined.fasta --map db_map.tsv
grep -c '^>' combined.fasta
sync_s3 db_map.tsv db/db_map.tsv

# Sage generates/reads decoys via decoy_tag; but to keep ONE identical searched FASTA
# across engines, we search 'combined.fasta' (target+entrapment+decoy) with all three
# and tell each engine NOT to generate its own decoys.
DB=$WORK/combined.fasta

# ---- 3. real DDA data: one ProteomeTools 1h HeLa-scale run -> mzML (license-clean TRFP) ----
note "download ProteomeTools DDA raw (~672MB)"
RAW=BA1_DDA_1h.raw
curl -sL --retry 5 -o $RAW \
  "https://ftp.pride.ebi.ac.uk/pride/data/archive/2019/05/PXD010595/01974C_BA1-TUM_missing_first_1_01_01-DDA-1h-R4.raw"
ls -la $RAW
note "convert raw -> mzML via ThermoRawFileParser (open source)"
docker run --rm -v $WORK:/d -w /d $TRFP_IMG \
  ThermoRawFileParser -i /d/$RAW -o /d -f 2 -m 0 || note "TRFP failed"
MZML=$(ls *.mzML | head -1)
note "mzML = $MZML  ($(du -h $MZML | cut -f1))"
NSPEC=$(grep -c 'MSLevel.*value=\"2\"\|ms level.*value=\"2\"' $MZML 2>/dev/null || echo "?")
sync_s3 $MZML data/$MZML

TResults=$WORK/results; mkdir -p $TResults

# =========================================================================
# ARM 1 — COMET baseline (OpenMS CometAdapter, NO fragment index)
# =========================================================================
note "=== ARM 1: COMET ==="
/usr/bin/time -v docker run --rm -v $WORK:/d -w /d $COMET_IMG bash -c "
  CometAdapter -in /d/$MZML -database /d/combined.fasta -out /d/results/comet.idXML \
    -threads $THREADS \
    -precursor_mass_tolerance 10 -precursor_error_units ppm \
    -fragment_mass_tolerance 0.02 -fragment_error_units Da \
    -enzyme Trypsin -missed_cleavages 2 \
    -fixed_modifications 'Carbamidomethyl (C)' -variable_modifications 'Oxidation (M)' \
    -pin_out /d/results/comet.pin
" 2> $TResults/comet.time.txt
grep -E "Elapsed|Maximum resident" $TResults/comet.time.txt
sync_s3 $TResults/comet.time.txt results/comet.time.txt
sync_s3 $TResults/comet.idXML results/comet.idXML
[ -f $TResults/comet.pin ] && sync_s3 $TResults/comet.pin results/comet.pin

# =========================================================================
# ARM 2 — SAGE (fragment-indexed, fast)
# =========================================================================
note "=== ARM 2: SAGE ==="
cat > $WORK/sage_config.json <<JSON
{
  "database": {
    "bucket_size": 8192,
    "enzyme": { "missed_cleavages": 2, "min_len": 6, "max_len": 50, "cleave_at": "KR", "restrict": "P" },
    "fragment_min_mz": 150.0, "fragment_max_mz": 2000.0,
    "peptide_min_mass": 500.0, "peptide_max_mass": 5000.0,
    "ion_kinds": ["b","y"], "min_ion_index": 2,
    "static_mods": { "C": 57.0215 },
    "variable_mods": { "M": [15.9949] }, "max_variable_mods": 2,
    "decoy_tag": "DECOY_", "generate_decoys": false,
    "fasta": "/d/combined.fasta"
  },
  "precursor_tol": { "ppm": [-10,10] },
  "fragment_tol": { "da": [-0.02,0.02] },
  "isotope_errors": [-1,3], "deisotope": false, "chimera": false,
  "predict_rt": true, "min_peaks": 15, "max_peaks": 150,
  "report_psms": 1, "output_directory": "/d/results"
}
JSON
/usr/bin/time -v docker run --rm -e RAYON_NUM_THREADS=$THREADS -v $WORK:/d -w /d $SAGE_IMG bash -c "
  sage /d/sage_config.json --write-pin /d/$MZML
" 2> $TResults/sage.time.txt
grep -E "Elapsed|Maximum resident" $TResults/sage.time.txt
ls -la $TResults/*.sage.* 2>/dev/null
sync_s3 $TResults/sage.time.txt results/sage.time.txt
[ -f $TResults/results.sage.tsv ] && cp $TResults/results.sage.tsv $TResults/sage.tsv
[ -f $TResults/results.sage.pin ] && cp $TResults/results.sage.pin $TResults/sage.pin
sync_s3 $TResults/sage.tsv results/sage.tsv
sync_s3 $TResults/sage.pin results/sage.pin

# =========================================================================
# ARM 3 — SAGE + MOKAPOT rescoring (recall lever) — reuses ARM2 pin (no re-search)
# =========================================================================
note "=== ARM 3: MOKAPOT on Sage pin ==="
/usr/bin/time -v docker run --rm -v $WORK:/d -w /d $MOKAPOT_IMG bash -c "
  mokapot --dest_dir /d/results --file_root sage --test_fdr 0.01 --seed 42 /d/results/sage.pin
" 2> $TResults/mokapot.time.txt
grep -E "Elapsed|Maximum resident" $TResults/mokapot.time.txt
ls -la $TResults/sage.mokapot.* 2>/dev/null
sync_s3 $TResults/mokapot.time.txt results/mokapot.time.txt
sync_s3 $TResults/sage.mokapot.psms.txt results/sage.mokapot.psms.txt
sync_s3 $TResults/sage.mokapot.peptides.txt results/sage.mokapot.peptides.txt

# =========================================================================
# 4. SCORE all arms with the SAME downstream estimator (normalize -> score)
# =========================================================================
note "=== normalize + score ==="
aws s3 cp $S3/code/normalize_psms.py normalize_psms.py --region $REGION --only-show-errors
aws s3 cp $S3/code/score_proteomics_search_benchmark.py score.py --region $REGION --only-show-errors

# Comet pepXML? CometAdapter emits idXML; for scoring we parse the pin (sage/comet)
# uniformly via a small idXML/pin normalizer inside pyteomics container.
docker run --rm -v $WORK:/d -w /d $PY_IMG bash -c "
  pip -q install pyteomics 2>/dev/null
  # Comet: parse idXML -> normalized table
  python3 /d/normalize_idxml.py --input /d/results/comet.idXML --dbmap /d/db_map.tsv --out /d/results/comet.psms.tsv || true
  # Sage raw: TSV -> normalized
  python3 /d/normalize_psms.py --engine sage --input /d/results/sage.tsv --dbmap /d/db_map.tsv --out /d/results/sage.psms.tsv || true
  # Sage+Mokapot: mokapot psms -> normalized
  python3 /d/normalize_psms.py --engine sage_mokapot --input /d/results/sage.mokapot.psms.txt --dbmap /d/db_map.tsv --out /d/results/sage_mokapot.psms.tsv || true
"
ls -la $TResults/*.psms.tsv

docker run --rm -v $WORK:/d -w /d $PY_IMG python3 /d/score.py \
  --psms /d/results/comet.psms.tsv /d/results/sage.psms.tsv /d/results/sage_mokapot.psms.tsv \
  --method-ids comet sage sage_mokapot \
  --entrapment-ratio 1.0 --claimed-fdr 0.01 \
  --out /d/results/scored 2>&1 | tee $TResults/score.stdout.txt

sync_s3 $TResults/score.stdout.txt results/score.stdout.txt
aws s3 cp $TResults/scored $S3/results/scored/ --recursive --region $REGION --only-show-errors
# also capture spectrum count + protein count summary
echo "n_target_proteins=$NTARGET" > $TResults/summary.env
echo "mzml=$MZML" >> $TResults/summary.env
sync_s3 $TResults/summary.env results/summary.env
sync_s3 $LOG results/run.log

note "=== DONE $(date -u) ==="
touch $WORK/DONE; sync_s3 $WORK/DONE results/DONE
