#!/usr/bin/env bash
# download_benchmarks.sh — Clone and download all external benchmark repos
#
# Requirements: git, python3 (with datasets library), docker
# All bioinformatics tools (fasterq-dump, seqtk, FastQC, MultiQC) run via Docker
# in inject_qc_defects.py — no local installs needed.
#
# Usage:
#   bash scripts/download_benchmarks.sh
#   bash scripts/download_benchmarks.sh --skip-large   # skip large dataset downloads
#   bash scripts/download_benchmarks.sh --bixbench-only
#
# After this script:
#   evaluation/external/bixbench/         BixBench repo + cached HF data
#   evaluation/external/bixbench_verified/ Phylo's 50-question verified subset
#   evaluation/external/bioagentbench/    BioAgentBench repo
#   evaluation/external/sciagentbench/    ScienceAgentBench repo
#   evaluation/external/pharmabench/      PharmaBench datasets (CSV files)
#   evaluation/external/biomni_eval1/     BiomniEval1 loader (from Biomni monorepo)
#   evaluation/external/sgi_bench/        SGI-Bench samples (already on disk)

set -euo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTERNAL_DIR="$EVAL_DIR/external"

SKIP_LARGE=false
BIXBENCH_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --skip-large)    SKIP_LARGE=true ;;
        --bixbench-only) BIXBENCH_ONLY=true ;;
    esac
done

mkdir -p "$EXTERNAL_DIR"
cd "$EXTERNAL_DIR"

echo "=== BioMate Evaluation — Download External Benchmarks ==="
echo "  Target: $EXTERNAL_DIR"
echo

# ─────────────────────────────────────────────────────────────────────────────
# 1. BixBench
# ─────────────────────────────────────────────────────────────────────────────
echo "1. BixBench (arXiv:2503.00096)"
if [ -d "bixbench/.git" ]; then
    echo "   Already cloned — pulling latest"
    git -C bixbench pull --ff-only 2>/dev/null || echo "   (pull skipped — local changes)"
else
    git clone --depth 1 https://github.com/context-dependent-biology/bixbench.git bixbench
    echo "   Cloned"
fi

# Cache HuggingFace dataset locally
echo "   Caching HuggingFace dataset (Phylo/BixBench-Verified-50)..."
python3 - <<'PYEOF'
import sys
try:
    from datasets import load_dataset
    ds = load_dataset("Phylo/BixBench-Verified-50", split="train")
    print(f"   Cached {len(ds)} questions (verified subset)")
except ImportError:
    print("   WARNING: 'datasets' library not installed — run: pip install datasets")
except Exception as e:
    print(f"   WARNING: Could not cache dataset: {e}")
PYEOF

if $BIXBENCH_ONLY; then
    echo
    echo "Done (--bixbench-only mode)"
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. BioAgentBench (arXiv:2601.21800)
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "2. BioAgentBench (arXiv:2601.21800)"
if [ -d "bioagentbench/.git" ]; then
    echo "   Already cloned"
    git -C bioagentbench pull --ff-only 2>/dev/null || true
else
    # Main repo — check if public
    if git clone --depth 1 https://github.com/snap-stanford/BioAgentBench.git bioagentbench 2>/dev/null; then
        echo "   Cloned"
    else
        echo "   WARNING: Repo not publicly available yet — creating placeholder"
        mkdir -p bioagentbench
        cat > bioagentbench/README.md <<'EOF'
# BioAgentBench placeholder
Repo not yet public. Check https://arxiv.org/abs/2601.21800 for availability.
When available: git clone https://github.com/snap-stanford/BioAgentBench.git
EOF
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. ScienceAgentBench (ICLR 2025)
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "3. ScienceAgentBench (ICLR 2025)"
if [ -d "sciagentbench/.git" ]; then
    echo "   Already cloned"
    git -C sciagentbench pull --ff-only 2>/dev/null || true
else
    if git clone --depth 1 https://github.com/OSU-NLP-Group/ScienceAgentBench.git sciagentbench 2>/dev/null; then
        echo "   Cloned"
    else
        echo "   WARNING: Clone failed — may require authentication"
        mkdir -p sciagentbench
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. PharmaBench datasets (Scientific Data 2024)
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "4. PharmaBench ADMET datasets"
PHARMA_DIR="pharmabench"
mkdir -p "$PHARMA_DIR"

if $SKIP_LARGE; then
    echo "   Skipped (--skip-large)"
else
    python3 - "$PHARMA_DIR" <<'PYEOF'
import sys, os, urllib.request, pathlib

datasets = {
    "ESOL":       "https://deepchemdata.s3-us-west-1.amazonaws.com/datasets/delaney-processed.csv",
    "FreeSolv":   "https://deepchemdata.s3-us-west-1.amazonaws.com/datasets/SAMPL.csv",
    "Lipophilicity": "https://deepchemdata.s3-us-west-1.amazonaws.com/datasets/Lipophilicity.csv",
    "BBBP":       "https://deepchemdata.s3-us-west-1.amazonaws.com/datasets/BBBP.csv",
    "Tox21":      "https://deepchemdata.s3-us-west-1.amazonaws.com/datasets/tox21.csv",
    "ClinTox":    "https://deepchemdata.s3-us-west-1.amazonaws.com/datasets/clintox.csv",
    "HIV":        "https://deepchemdata.s3-us-west-1.amazonaws.com/datasets/HIV.csv",
    "BACE":       "https://deepchemdata.s3-us-west-1.amazonaws.com/datasets/bace.csv",
    "SIDER":      "https://deepchemdata.s3-us-west-1.amazonaws.com/datasets/sider.csv",
    "MUV":        "https://deepchemdata.s3-us-west-1.amazonaws.com/datasets/muv.csv.gz",
    "hERG":       "https://deepchemdata.s3-us-west-1.amazonaws.com/datasets/herg_central_core.csv",
}

out_dir = pathlib.Path(sys.argv[1])
downloaded = 0
for name, url in datasets.items():
    fname = out_dir / (name.lower() + ("_" + url.split("/")[-1].split(".")[0] + ".csv" if name.lower() not in url.split("/")[-1].lower() else url.split("/")[-1]))
    if fname.exists():
        print(f"   {name}: already downloaded")
        downloaded += 1
        continue
    try:
        urllib.request.urlretrieve(url, fname)
        print(f"   {name}: OK ({fname.stat().st_size // 1024} KB)")
        downloaded += 1
    except Exception as e:
        print(f"   {name}: FAILED — {e}")

print(f"   Total: {downloaded}/{len(datasets)} datasets")
PYEOF
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. BiomniEval1 (check Biomni monorepo or HuggingFace)
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "5. BiomniEval1 loader"

# Check if the loader already exists in the repo
BIOMNI_LOADER="$(find /home/yzhang/biomate -name "biomni_eval1.py" 2>/dev/null | head -1)"
if [ -n "$BIOMNI_LOADER" ]; then
    echo "   Found existing loader at: $BIOMNI_LOADER"
    ln -sfn "$(dirname "$BIOMNI_LOADER")" "$EXTERNAL_DIR/biomni_eval1_src" 2>/dev/null || true
else
    echo "   Checking HuggingFace biomni/Eval1..."
    python3 - <<'PYEOF'
try:
    from datasets import load_dataset
    ds = load_dataset("biomni/Eval1", split="train")
    print(f"   HuggingFace biomni/Eval1: {len(ds)} tasks available")
except ImportError:
    print("   WARNING: 'datasets' not installed")
except Exception as e:
    print(f"   WARNING: {e}")
PYEOF
fi

# ─────────────────────────────────────────────────────────────────────────────
# 6. SGI-Bench — already on disk
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "6. SGI-Bench"
SGI_PATH=$(python3 -c "
import sys; sys.path.insert(0, '/home/yzhang/biomate')
try:
    from backend.lib.galaxy.ai.test_harness.sgi_bench_adapter import SGIBenchAdapter
    a = SGIBenchAdapter({})
    print(getattr(a, 'data_dir', 'not found'))
except Exception as e:
    print('not found: ' + str(e))
" 2>/dev/null || echo "not found")
echo "   Path: $SGI_PATH"
if [ "$SGI_PATH" != "not found" ] && [ -d "$SGI_PATH" ]; then
    COUNT=$(find "$SGI_PATH" -name "*.json" 2>/dev/null | wc -l)
    echo "   Found $COUNT sample files"
else
    echo "   WARNING: SGI-Bench data directory not found"
    echo "   Expected: backend/lib/galaxy/ai/test_harness/sgi_bench_data/"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "=== Download Summary ==="
for dir in bixbench bioagentbench sciagentbench pharmabench; do
    if [ -d "$EXTERNAL_DIR/$dir" ]; then
        N=$(find "$EXTERNAL_DIR/$dir" -type f 2>/dev/null | wc -l)
        echo "  $dir: $N files"
    else
        echo "  $dir: MISSING"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# 7. Pre-pull Docker images used by inject_qc_defects.py
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "7. Pre-pulling Docker images for QC tools"

if ! command -v docker &>/dev/null; then
    echo "   WARNING: docker not found — skipping image checks"
else
    # arm64-native local BioMate images — verify only:
    echo "   Verifying arm64-native local images:"
    echo "   biomate/biotools:arm64-comprehensive  [seqtk at /usr/local/bin/seqtk]"
    docker image inspect biomate/biotools:arm64-comprehensive &>/dev/null \
        && echo "   OK" || echo "   WARNING: not found"
    echo "   biomate/biotools:comprehensive  [multiqc 1.32 at /usr/local/bin/multiqc]"
    docker image inspect biomate/biotools:comprehensive &>/dev/null \
        && echo "   OK" || echo "   WARNING: not found"

    # amd64 images already on disk (run under QEMU emulation on arm64):
    echo "   Verifying amd64 images (QEMU emulation on arm64 — Java/FastQC works fine):"
    docker image inspect quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0 &>/dev/null \
        && echo "   OK: quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0" \
        || echo "   WARNING: fastqc image not found — run: docker pull quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0"

    # fasterq-dump: not in any local image — pull amd64 biocontainers under emulation:
    echo "   Pulling amd64 images for fasterq-dump (one-time SRA download, QEMU emulation):"
    TO_PULL=(
        "biocontainers/mulled-v2-5f89fe0cd045cb1d615630b9261a1d17943a9b6a:2f4a4c900edd6801ff0068c2b3048b4459d119eb-0"
        "biocontainers/sra-tools:3.1.0--h9f5acd7_0"
    )
    for img in "${TO_PULL[@]}"; do
        if docker image inspect "$img" &>/dev/null; then
            echo "   OK (already cached): $img"
        else
            echo "   Pulling $img ..."
            docker pull --platform linux/amd64 "$img" 2>&1 | tail -1
        fi
    done
    echo "   Done."
fi

echo
echo "Next step: python scripts/setup_eval_user.py"
echo "Then:      python runners/run_all.py --suite p0 --output results/"
echo "QC data:   python scripts/inject_qc_defects.py --all"
