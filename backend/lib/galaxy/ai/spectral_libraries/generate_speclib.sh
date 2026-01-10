#!/bin/bash
#
# Generate DIA-NN Spectral Libraries from UniProt FASTA files
#
# This script downloads FASTA files from S3, generates spectral libraries
# using DIA-NN, and uploads the results back to S3.
#
# Usage:
#   ./generate_speclib.sh human reviewed    # Generate human reviewed library
#   ./generate_speclib.sh mouse reviewed    # Generate mouse reviewed library
#   ./generate_speclib.sh all               # Generate all libraries
#
# Prerequisites:
#   - Docker or Singularity installed
#   - AWS CLI configured with write access to S3 bucket
#   - ~50GB disk space for temporary files
#
# Estimated time per library: 24-48 hours (CPU-dependent)

set -e

# Configuration
S3_BUCKET="knowledge-datasets-1759951976"
SPECLIB_PREFIX="spectral_libraries"
WORK_DIR="${HOME}/.biomate/speclib_generation"
DIANN_IMAGE="docker.io/biocontainers/diann:v1.8.1_cv1"
THREADS=${THREADS:-16}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Library definitions
declare -A FASTA_FILES
FASTA_FILES["human"]="uniprot/uniprot_sprot_human.fasta.gz"
FASTA_FILES["mouse"]="uniprot/uniprot_sprot_mouse.fasta.gz"
FASTA_FILES["rat"]="uniprot/uniprot_sprot_rat.fasta.gz"

declare -A OUTPUT_FILES
OUTPUT_FILES["human_reviewed"]="human_swissprot.speclib"
OUTPUT_FILES["human_phospho"]="human_swissprot_phospho.speclib"
OUTPUT_FILES["mouse_reviewed"]="mouse_swissprot.speclib"
OUTPUT_FILES["rat_reviewed"]="rat_swissprot.speclib"

# DIA-NN parameters for each variant
get_diann_params() {
    local variant=$1
    case $variant in
        "reviewed")
            echo "--cut K*,R* --missed-cleavages 1 --min-pep-length 7 --max-pep-length 30 --min-pr-charge 2 --max-pr-charge 4 --var-mods 2 --var-mod UniMod:35,15.994915,M --var-mod UniMod:1,42.010565,*n --fixed-mod UniMod:4,57.021464,C"
            ;;
        "phospho")
            echo "--cut K*,R* --missed-cleavages 2 --min-pep-length 7 --max-pep-length 30 --min-pr-charge 2 --max-pr-charge 4 --var-mods 3 --var-mod UniMod:35,15.994915,M --var-mod UniMod:1,42.010565,*n --var-mod UniMod:21,79.966331,STY --fixed-mod UniMod:4,57.021464,C"
            ;;
        *)
            log_error "Unknown variant: $variant"
            exit 1
            ;;
    esac
}

generate_library() {
    local organism=$1
    local variant=$2
    local output_key="${organism}_${variant}"

    log_info "Generating spectral library for ${organism}/${variant}"

    # Create work directory
    local job_dir="${WORK_DIR}/${organism}_${variant}_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$job_dir"
    cd "$job_dir"

    # Download FASTA from S3
    local fasta_s3="${FASTA_FILES[$organism]}"
    local fasta_local="$(basename ${fasta_s3})"
    local fasta_unzipped="${fasta_local%.gz}"

    log_info "Downloading FASTA from s3://${S3_BUCKET}/${fasta_s3}"
    aws s3 cp "s3://${S3_BUCKET}/${fasta_s3}" "$fasta_local"

    # Decompress if gzipped
    if [[ "$fasta_local" == *.gz ]]; then
        log_info "Decompressing FASTA..."
        gunzip -f "$fasta_local"
    fi

    # Get DIA-NN parameters
    local diann_params=$(get_diann_params "$variant")
    local output_file="${OUTPUT_FILES[$output_key]}"

    log_info "Running DIA-NN library generation (this will take 24-48 hours)..."
    log_info "Parameters: $diann_params"

    # Check if using Docker or Singularity
    if command -v docker &> /dev/null; then
        log_info "Using Docker..."
        docker run --rm \
            -v "$job_dir:/data" \
            -w /data \
            "$DIANN_IMAGE" \
            diann \
            --fasta "/data/${fasta_unzipped}" \
            --fasta-search \
            --predictor \
            --gen-spec-lib \
            --threads $THREADS \
            --out-lib "/data/${output_file%.speclib}" \
            $diann_params \
            2>&1 | tee diann.log
    elif command -v singularity &> /dev/null; then
        log_info "Using Singularity..."
        singularity exec \
            -B "$job_dir:/data" \
            "docker://${DIANN_IMAGE}" \
            diann \
            --fasta "/data/${fasta_unzipped}" \
            --fasta-search \
            --predictor \
            --gen-spec-lib \
            --threads $THREADS \
            --out-lib "/data/${output_file%.speclib}" \
            $diann_params \
            2>&1 | tee diann.log
    else
        log_error "Neither Docker nor Singularity found!"
        exit 1
    fi

    # Find the generated speclib file
    local speclib_file=$(ls *.predicted.speclib 2>/dev/null | head -1)
    if [[ -z "$speclib_file" ]]; then
        log_error "Spectral library generation failed - no .speclib file found"
        exit 1
    fi

    # Rename to expected filename
    mv "$speclib_file" "$output_file"

    # Calculate MD5
    local md5sum=$(md5sum "$output_file" | cut -d' ' -f1)
    local filesize=$(stat -c%s "$output_file")

    log_info "Generated: $output_file (${filesize} bytes, MD5: ${md5sum})"

    # Upload to S3
    local s3_dest="s3://${S3_BUCKET}/${SPECLIB_PREFIX}/${organism}/${output_file}"
    log_info "Uploading to ${s3_dest}..."
    aws s3 cp "$output_file" "$s3_dest"

    # Create metadata file
    cat > "${output_file}.meta.json" << EOF
{
    "organism": "${organism}",
    "variant": "${variant}",
    "filename": "${output_file}",
    "file_size_bytes": ${filesize},
    "md5": "${md5sum}",
    "generated_date": "$(date -Iseconds)",
    "diann_version": "1.8.1",
    "diann_params": "${diann_params}",
    "source_fasta": "${fasta_s3}"
}
EOF

    aws s3 cp "${output_file}.meta.json" "${s3_dest}.meta.json"

    log_info "Library generation complete for ${organism}/${variant}"
    log_info "S3 location: ${s3_dest}"

    # Cleanup
    cd -
    # Optionally keep the work directory for debugging
    # rm -rf "$job_dir"
}

# Main
case "${1:-help}" in
    "human"|"mouse"|"rat")
        generate_library "$1" "${2:-reviewed}"
        ;;
    "all")
        log_info "Generating all spectral libraries..."
        for org in human mouse rat; do
            generate_library "$org" "reviewed"
        done
        log_info "Generating phospho library for human..."
        generate_library "human" "phospho"
        ;;
    "help"|*)
        echo "Usage: $0 <organism> [variant]"
        echo ""
        echo "Organisms: human, mouse, rat, all"
        echo "Variants:  reviewed (default), phospho (human only)"
        echo ""
        echo "Examples:"
        echo "  $0 human reviewed     # Generate human SwissProt library"
        echo "  $0 human phospho      # Generate human phospho library"
        echo "  $0 mouse              # Generate mouse library (default: reviewed)"
        echo "  $0 all                # Generate all libraries"
        echo ""
        echo "Environment variables:"
        echo "  THREADS=16            # Number of CPU threads (default: 16)"
        ;;
esac
