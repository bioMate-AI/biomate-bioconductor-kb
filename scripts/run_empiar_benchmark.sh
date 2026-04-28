#!/usr/bin/env bash
# =============================================================================
# BioMate CryoSPARC Benchmark Harness — EMPIAR dataset download + pipeline run
# =============================================================================
#
# Downloads a subset of an EMPIAR dataset and runs the full BioMate
# CryoSPARC SPA pipeline, then extracts and prints benchmark metrics.
#
# Usage:
#   bash run_empiar_benchmark.sh [options]
#
# Options:
#   --empiar-id       ID      EMPIAR entry to benchmark (default: 10061)
#   --n-micrographs   N       Number of micrographs to download (default: 100)
#   --gpu-workers     N       Number of GPU workers for CryoSPARC (default: 1)
#   --mock                    Run in mock/CI mode (synthetic data, ~30 s)
#   --outdir          PATH    Output directory (default: ./benchmark_results/empiar_<ID>)
#   --pixel-size      FLOAT   Micrograph pixel size in Å (default: 0.885)
#   --voltage         INT     Accelerating voltage in kV (default: 300)
#   --symmetry        STR     Particle symmetry (default: D2)
#   --profile         STR     BioMate QC profile (default: cryoem_spa_purified)
#   --expected-res    FLOAT   Expected resolution in Å for comparison (default: 2.2)
#   --backend-url     URL     BioMate backend base URL (default: http://localhost:8081)
#   --api-key         KEY     BioMate API key (defaults to BIOMATE_API_KEY env var)
#   --keep-raw                Keep raw micrograph files after processing
#   -h, --help                Show this help and exit
#
# Environment variables (override defaults):
#   EMPIAR_ID, N_MICROGRAPHS, GPU_WORKERS, MOCK_MODE, OUTDIR,
#   PIXEL_SIZE, VOLTAGE, SYMMETRY, PROFILE, BIOMATE_API_KEY
#
# Examples:
#   # Full run on 50 micrographs from EMPIAR-10028
#   EMPIAR_ID=10028 N_MICROGRAPHS=50 bash run_empiar_benchmark.sh
#
#   # Fast CI smoke test (no external downloads, no GPU)
#   bash run_empiar_benchmark.sh --mock
#
#   # Custom expected resolution
#   bash run_empiar_benchmark.sh --expected-res 3.5 --profile cryoem_spa_membrane
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults (overridden by CLI flags or environment)
# ---------------------------------------------------------------------------
EMPIAR_ID="${EMPIAR_ID:-10061}"
N_MICROGRAPHS="${N_MICROGRAPHS:-100}"
GPU_WORKERS="${GPU_WORKERS:-1}"
MOCK_MODE="${MOCK_MODE:-false}"
OUTDIR="${OUTDIR:-}"
PIXEL_SIZE="${PIXEL_SIZE:-0.885}"
VOLTAGE="${VOLTAGE:-300}"
SYMMETRY="${SYMMETRY:-D2}"
PROFILE="${PROFILE:-cryoem_spa_purified}"
EXPECTED_RES="${EXPECTED_RES:-2.2}"
BACKEND_URL="${BACKEND_URL:-http://localhost:8081}"
API_KEY="${BIOMATE_API_KEY:-}"
KEEP_RAW=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[1;33m'
_CYAN='\033[0;36m'
_BOLD='\033[1m'
_RESET='\033[0m'

info()  { printf "${_CYAN}[INFO]${_RESET}  %s\n" "$*"; }
ok()    { printf "${_GREEN}[OK]${_RESET}    %s\n" "$*"; }
warn()  { printf "${_YELLOW}[WARN]${_RESET}  %s\n" "$*"; }
err()   { printf "${_RED}[ERROR]${_RESET} %s\n" "$*" >&2; }
die()   { err "$*"; exit 1; }
sep()   { printf "${_BOLD}%s${_RESET}\n" "$(printf '─%.0s' {1..70})"; }

# ---------------------------------------------------------------------------
# CLI argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --empiar-id)      EMPIAR_ID="$2";      shift 2 ;;
        --n-micrographs)  N_MICROGRAPHS="$2";  shift 2 ;;
        --gpu-workers)    GPU_WORKERS="$2";    shift 2 ;;
        --mock)           MOCK_MODE=true;      shift   ;;
        --outdir)         OUTDIR="$2";         shift 2 ;;
        --pixel-size)     PIXEL_SIZE="$2";     shift 2 ;;
        --voltage)        VOLTAGE="$2";        shift 2 ;;
        --symmetry)       SYMMETRY="$2";       shift 2 ;;
        --profile)        PROFILE="$2";        shift 2 ;;
        --expected-res)   EXPECTED_RES="$2";   shift 2 ;;
        --backend-url)    BACKEND_URL="$2";    shift 2 ;;
        --api-key)        API_KEY="$2";        shift 2 ;;
        --keep-raw)       KEEP_RAW=true;       shift   ;;
        -h|--help)
            head -60 "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
        *)
            die "Unknown argument: $1  (use --help for usage)"
            ;;
    esac
done

# Resolve output directory after flags are parsed
OUTDIR="${OUTDIR:-${REPO_ROOT}/benchmark_results/empiar_${EMPIAR_ID}}"
RAW_DIR="${OUTDIR}/raw_micrographs"
RESULTS_DIR="${OUTDIR}/pipeline_results"
METRICS_FILE="${OUTDIR}/metrics.json"
NF_LOG="${OUTDIR}/nextflow.log"

# ---------------------------------------------------------------------------
# Environment checks
# ---------------------------------------------------------------------------
check_env() {
    local missing=()

    if [[ "${MOCK_MODE}" == "false" ]]; then
        command -v nextflow  >/dev/null 2>&1 || missing+=("nextflow")
        command -v python3   >/dev/null 2>&1 || missing+=("python3")
    fi

    command -v python3 >/dev/null 2>&1 || missing+=("python3")

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required tools: ${missing[*]}"
    fi
}

# ---------------------------------------------------------------------------
# Step 1 — EMPIAR download
# ---------------------------------------------------------------------------
download_empiar() {
    info "Downloading up to ${N_MICROGRAPHS} micrographs from EMPIAR-${EMPIAR_ID}"
    mkdir -p "${RAW_DIR}"

    local BASE_URL="https://ftp.ebi.ac.uk/empiar/world_availability/${EMPIAR_ID}/data"
    local ASPERA_PATH="emp_ext2@hx-fasp-1.ebi.ac.uk:/pub/databases/empiar/archive/${EMPIAR_ID}/data"

    # Try Aspera first (fast); fall back to wget
    if command -v ascp >/dev/null 2>&1; then
        info "Aspera (ascp) found — using high-speed transfer"
        # Download only .mrc / .tif / .eer files up to N_MICROGRAPHS
        ascp \
            -QT \
            -l 500m \
            -P33001 \
            --mode recv \
            --partial-file-suffix=.partial \
            "${ASPERA_PATH}/" \
            "${RAW_DIR}/" 2>&1 | head -40 || true

        # Limit to requested number of files
        mapfile -t ALL_FILES < <(find "${RAW_DIR}" \
            -maxdepth 3 \
            -type f \
            \( -name "*.mrc" -o -name "*.tif" -o -name "*.tiff" -o -name "*.eer" \) \
            | sort | tail -n "+$((N_MICROGRAPHS + 1))")
        # Remove excess files
        for f in "${ALL_FILES[@]:-}"; do
            [[ -n "${f:-}" ]] && rm -f "${f}"
        done
    else
        warn "ascp not found — falling back to wget (slower)"
        info "Fetching file list from EBI FTP …"

        # Retrieve directory listing; parse hrefs for known micrograph extensions
        wget -q -O "${OUTDIR}/.empiar_index.html" \
            "${BASE_URL}/" \
            || die "Cannot reach EBI FTP at ${BASE_URL}/"

        mapfile -t FILE_NAMES < <(
            grep -oP 'href="\K[^"]+\.(?:mrc|tif|tiff|eer)' \
                "${OUTDIR}/.empiar_index.html" 2>/dev/null \
            | head -"${N_MICROGRAPHS}"
        )

        if [[ ${#FILE_NAMES[@]} -eq 0 ]]; then
            warn "No direct micrograph links found at ${BASE_URL}/"
            warn "The entry may use a subdirectory structure. Trying common subdirs …"
            local SUBDIRS=("data" "movies" "raw" "micrographs" "frames")
            for sub in "${SUBDIRS[@]}"; do
                wget -q -O "${OUTDIR}/.empiar_sub.html" \
                    "${BASE_URL}/${sub}/" 2>/dev/null || continue
                mapfile -t FILE_NAMES < <(
                    grep -oP 'href="\K[^"]+\.(?:mrc|tif|tiff|eer)' \
                        "${OUTDIR}/.empiar_sub.html" \
                    | sed "s|^|${sub}/|" \
                    | head -"${N_MICROGRAPHS}"
                )
                [[ ${#FILE_NAMES[@]} -gt 0 ]] && BASE_URL="${BASE_URL}/${sub}" && break
            done
        fi

        if [[ ${#FILE_NAMES[@]} -eq 0 ]]; then
            die "Could not find micrograph files on EBI FTP for EMPIAR-${EMPIAR_ID}. " \
                "Check the entry manually at https://www.ebi.ac.uk/empiar/EMPIAR-${EMPIAR_ID}/"
        fi

        info "Found ${#FILE_NAMES[@]} files; downloading …"
        local count=0
        for name in "${FILE_NAMES[@]}"; do
            local dest="${RAW_DIR}/$(basename "${name}")"
            if [[ ! -f "${dest}" ]]; then
                wget -q --show-progress -O "${dest}" "${BASE_URL}/${name}" || {
                    warn "Download failed for ${name}; skipping"
                    rm -f "${dest}"
                    continue
                }
            else
                info "  Already present: $(basename "${name}")"
            fi
            (( count++ )) || true
        done
        ok "Downloaded ${count} micrographs to ${RAW_DIR}"
    fi

    # Sanity check
    local n_downloaded
    n_downloaded=$(find "${RAW_DIR}" -maxdepth 3 -type f \
        \( -name "*.mrc" -o -name "*.tif" -o -name "*.tiff" -o -name "*.eer" \) \
        | wc -l)
    info "Micrographs on disk: ${n_downloaded}"
    [[ "${n_downloaded}" -gt 0 ]] || die "No micrograph files found in ${RAW_DIR}"
}

# ---------------------------------------------------------------------------
# Step 2 — Mock data generation (CI / no-GPU mode)
# ---------------------------------------------------------------------------
generate_mock_data() {
    info "Mock mode: generating synthetic micrograph stubs"
    mkdir -p "${RAW_DIR}" "${RESULTS_DIR}"

    python3 - <<PYEOF
import json, math, os, random, struct, time
import datetime as _dt
from pathlib import Path

random.seed(42)
raw_dir    = Path("${RAW_DIR}")
result_dir = Path("${RESULTS_DIR}")

n = int("${N_MICROGRAPHS}")

# Write minimal MRC header stubs (1024-byte header only)
MRC_HEADER_SIZE = 1024
for i in range(n):
    fpath = raw_dir / f"micrograph_{i:04d}.mrc"
    fpath.write_bytes(b'\x00' * MRC_HEADER_SIZE)

# Write synthetic FSC curve
fsc_path = result_dir / "validation_fsc.txt"
fsc_path.parent.mkdir(parents=True, exist_ok=True)
with open(fsc_path, "w") as fh:
    fh.write("# freq_inv_A  fsc\n")
    for i in range(129):
        freq = i / 128.0 * (1.0 / (2.0 * float("${PIXEL_SIZE}")))
        fsc  = math.exp(-6.0 * i / 128.0)  # crosses 0.143 around index ~65
        fh.write(f"{freq:.6f}  {fsc:.6f}\n")

# Write synthetic QC audit
audit_path = result_dir / "qc_audit.jsonl"
gates = [
    ("motion", "pass",     32.0, 50.0),
    ("ctf",    "pass",     0.82, 0.70),
    ("junk",   "advisory", 0.52, 0.70),
    ("fsc",    "pass",     None, None),
]
_now_iso = _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
with open(audit_path, "w") as fh:
    for gate, status, value, threshold in gates:
        evt = {
            "timestamp": _now_iso,
            "gate": gate,
            "status": status,
            "profile": "${PROFILE}",
        }
        if value is not None:
            evt["value"] = value
            evt["threshold"] = threshold
        fh.write(json.dumps(evt) + "\n")

# Simulate a short processing delay so elapsed time is non-zero
time.sleep(2)

# Write mock Nextflow timeline (simple HTML with timing comment)
timeline_path = result_dir / "timeline.html"
elapsed_ms = 28_000  # 28 s for mock
timeline_path.write_text(
    f"<!-- Nextflow mock timeline. Total elapsed: {elapsed_ms} ms -->\n"
)

# Write mock micrograph CTF STAR file (enables micrograph count extraction)
mic_star_path = result_dir / "micrographs_ctf.star"
with open(mic_star_path, "w") as fh:
    fh.write("data_\nloop_\n_rlnMicrographName\n_rlnCtfMaxResolution\n")
    for i in range(n):
        fh.write(f"micrograph_{i:04d}.mrc  4.5\n")

# Write mock particle star file
star_path = result_dir / "particles_selected.star"
with open(star_path, "w") as fh:
    fh.write("data_\nloop_\n_rlnImageName\n_rlnMicrographName\n")
    for j in range(500 * n):
        fh.write(f"{j:06d}@particles.mrcs  micrograph_0000.mrc\n")

print(f"Mock data written: {n} micrograph stubs, FSC, audit, particles, micrograph STAR")
PYEOF
    ok "Mock data generated in ${RAW_DIR} and ${RESULTS_DIR}"
}

# ---------------------------------------------------------------------------
# Step 3 — Nextflow pipeline run
# ---------------------------------------------------------------------------
run_nextflow_pipeline() {
    info "Launching BioMate CryoSPARC SPA pipeline via Nextflow"
    mkdir -p "${RESULTS_DIR}"

    local NF_MAIN="${REPO_ROOT}/backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf"
    [[ -f "${NF_MAIN}" ]] || die "Nextflow pipeline not found at: ${NF_MAIN}"

    local NF_PARAMS=(
        --movies_path     "${RAW_DIR}/*.mrc"
        --pixel_size      "${PIXEL_SIZE}"
        --voltage         "${VOLTAGE}"
        --symmetry        "${SYMMETRY}"
        --gpu_workers     "${GPU_WORKERS}"
        --qc_profile      "${PROFILE}"
        --outdir          "${RESULTS_DIR}"
    )

    local NF_OPTS=(
        -profile          "standard"
        -with-report      "${OUTDIR}/nextflow_report.html"
        -with-timeline    "${OUTDIR}/timeline.html"
        -with-trace       "${OUTDIR}/trace.tsv"
        -with-dag         "${OUTDIR}/dag.html"
        -ansi-log         false
        -resume
    )

    info "Nextflow params: ${NF_PARAMS[*]}"

    local T_START
    T_START=$(date +%s)

    nextflow run "${NF_MAIN}" \
        "${NF_OPTS[@]}" \
        "${NF_PARAMS[@]}" \
        2>&1 | tee "${NF_LOG}" \
        || { err "Nextflow run failed. Check ${NF_LOG}"; exit 1; }

    local T_END
    T_END=$(date +%s)
    ELAPSED_S=$(( T_END - T_START ))
    ok "Nextflow completed in ${ELAPSED_S}s"
}

# ---------------------------------------------------------------------------
# Step 4 — Mock pipeline (CI, runs in ~30 s)
# ---------------------------------------------------------------------------
run_mock_pipeline() {
    info "Mock pipeline: simulating SPA processing (no Nextflow required)"
    local T_START
    T_START=$(date +%s)

    # Already generated by generate_mock_data; just emit timing
    python3 - <<PYEOF
import time
steps = [
    ("Import movies",           0.5),
    ("Motion correction",       1.0),
    ("CTF estimation",          1.0),
    ("Particle picking",        1.5),
    ("2D classification",       2.0),
    ("3D initial model",        3.0),
    ("3D refinement",           3.0),
    ("FSC validation",          1.0),
    ("QC gate evaluation",      0.5),
]
for name, duration in steps:
    print(f"  [mock] {name} … ", end="", flush=True)
    time.sleep(duration)
    print("done")
print("Mock pipeline complete.")
PYEOF

    local T_END
    T_END=$(date +%s)
    ELAPSED_S=$(( T_END - T_START ))
    ok "Mock pipeline completed in ${ELAPSED_S}s"
}

# ---------------------------------------------------------------------------
# Step 5 — Extract metrics
# ---------------------------------------------------------------------------
extract_metrics() {
    info "Extracting benchmark metrics from ${RESULTS_DIR}"

    local EXTRACT_SCRIPT="${SCRIPT_DIR}/extract_benchmark_metrics.py"
    [[ -f "${EXTRACT_SCRIPT}" ]] \
        || die "Metric extraction script not found: ${EXTRACT_SCRIPT}"

    python3 "${EXTRACT_SCRIPT}" \
        --run-dir          "${RESULTS_DIR}" \
        --expected-resolution "${EXPECTED_RES}" \
        --output           "${METRICS_FILE}" \
        --empiar-id        "${EMPIAR_ID}" \
        --pixel-size       "${PIXEL_SIZE}"

    ok "Metrics written to ${METRICS_FILE}"
}

# ---------------------------------------------------------------------------
# Step 6 — Print summary
# ---------------------------------------------------------------------------
print_summary() {
    sep
    printf "${_BOLD}BioMate CryoSPARC Benchmark Summary — EMPIAR-%s${_RESET}\n" "${EMPIAR_ID}"
    sep

    if [[ ! -f "${METRICS_FILE}" ]]; then
        warn "No metrics file found at ${METRICS_FILE}; skipping summary."
        return
    fi

    python3 - <<PYEOF
import json, sys
from pathlib import Path

m = json.loads(Path("${METRICS_FILE}").read_text())

def fmt(val, unit=""):
    if val is None:
        return "n/a"
    if isinstance(val, float):
        return f"{val:.2f}{unit}"
    return str(val) + unit

print(f"  Micrographs processed   : {fmt(m.get('n_micrographs_processed'))}")
print(f"  Acceptance rate         : {fmt(m.get('acceptance_rate_pct'), '%')}")
print(f"  Final particle count    : {fmt(m.get('n_particles_final'))}")
print(f"  FSC resolution (Å)      : {fmt(m.get('fsc_resolution_A'), ' Å')}")
exp = m.get("expected_resolution_A")
if exp:
    delta = (m.get("fsc_resolution_A") or 0) - exp
    sign  = "+" if delta > 0 else ""
    print(f"    vs expected ({fmt(exp,' Å')})    : {sign}{delta:.2f} Å")
print(f"  Wall time               : {fmt(m.get('wall_time_s'), ' s')}")
print(f"  GPU hours               : {fmt(m.get('gpu_hours'), ' GPU·h')}")

qc = m.get("qc_gate_summary", {})
if qc:
    print()
    print("  QC Gate Results:")
    for gate, status in qc.items():
        icon = {"pass": "✓", "advisory": "!", "halt": "✗"}.get(status, "?")
        print(f"    [{icon}] {gate:<20} {status}")

regressions = m.get("regressions", [])
if regressions:
    print()
    print("  Regressions vs baseline:")
    for r in regressions:
        print(f"    • {r}")
else:
    print()
    print("  No regressions detected vs baseline.")
PYEOF

    sep
    ok "Benchmark complete. Full metrics: ${METRICS_FILE}"
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
cleanup_raw() {
    if [[ "${KEEP_RAW}" == "false" ]]; then
        info "Removing raw micrograph files (use --keep-raw to retain)"
        rm -rf "${RAW_DIR}"
    else
        info "Raw micrographs kept at: ${RAW_DIR}"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    sep
    printf "${_BOLD}BioMate CryoSPARC Benchmark Harness${_RESET}\n"
    printf "  EMPIAR ID    : EMPIAR-%s\n"  "${EMPIAR_ID}"
    printf "  Micrographs  : %s\n"          "${N_MICROGRAPHS}"
    printf "  GPU workers  : %s\n"          "${GPU_WORKERS}"
    printf "  QC profile   : %s\n"          "${PROFILE}"
    printf "  Mock mode    : %s\n"          "${MOCK_MODE}"
    printf "  Output dir   : %s\n"          "${OUTDIR}"
    sep

    mkdir -p "${OUTDIR}"

    check_env

    local T_TOTAL_START
    T_TOTAL_START=$(date +%s)

    if [[ "${MOCK_MODE}" == "true" ]]; then
        # ── CI / fast path ──────────────────────────────────────────────────
        generate_mock_data
        run_mock_pipeline
    else
        # ── Real path ───────────────────────────────────────────────────────
        download_empiar
        run_nextflow_pipeline
    fi

    extract_metrics
    print_summary
    cleanup_raw

    local T_TOTAL_END
    T_TOTAL_END=$(date +%s)
    ok "Total benchmark time: $(( T_TOTAL_END - T_TOTAL_START ))s"
}

main "$@"
