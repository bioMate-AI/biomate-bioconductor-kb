#!/usr/bin/env nextflow
/*
 * genomics/check_ensembl_patterns
 * Check if gene identifiers follow Ensembl naming patterns
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Use demo h5ad file to check gene index patterns
params.gene_index = null
params.h5ad_file = "${projectDir}/../../../../lib/galaxy/datatypes/test/pbmc3k_tiny.h5ad"

process CHECK_ENSEMBL_PATTERNS {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("check_ensembl_patterns_results.json"), emit: results
    tuple val(meta), path("check_ensembl_patterns_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Disable numba JIT to avoid caching issues in Docker containers
    export NUMBA_DISABLE_JIT=1
    export NUMBA_CACHE_DIR=/tmp/numba_cache
    mkdir -p /tmp/numba_cache

    # Export parameters as environment variables
    export PARAM_GENE_INDEX="${params.gene_index?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_H5AD_FILE="${params.h5ad_file?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os
import re

def auto_convert(val):
    # Auto-convert string to appropriate type
    if val is None or val == '' or val == 'null':
        return None
    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    # Try float
    try:
        return float(val)
    except ValueError:
        pass
    # Return as string
    return val


def check_ensembl_patterns(gene_index=None, h5ad_file=None):
    '''Check if gene identifiers follow Ensembl naming patterns.

    Detects various gene ID formats:
    - Ensembl gene IDs: ENSG00000139618 (human), ENSMUSG00000029580 (mouse)
    - Ensembl transcript IDs: ENST00000380152
    - Gene symbols: BRCA1, TP53, GAPDH
    - RefSeq IDs: NM_007294, NP_009225
    - UniProt IDs: P38398, Q9Y6K1

    Parameters
    ----------
    gene_index : list or str
        List of gene IDs to check, or comma-separated string
    h5ad_file : str
        Path to H5AD file to extract gene index from

    Returns
    -------
    dict
        Pattern detection results with statistics
    '''
    # Build regex patterns using string construction to avoid heredoc escaping
    DEND = chr(92) + "d"
    DOT = chr(92) + "."
    END = chr(36)

    ensembl_patterns = {
        "human_gene": "^ENSG" + DEND + "{11}(" + DOT + DEND + "+)?" + END,
        "human_transcript": "^ENST" + DEND + "{11}(" + DOT + DEND + "+)?" + END,
        "human_protein": "^ENSP" + DEND + "{11}(" + DOT + DEND + "+)?" + END,
        "mouse_gene": "^ENSMUSG" + DEND + "{11}(" + DOT + DEND + "+)?" + END,
        "mouse_transcript": "^ENSMUST" + DEND + "{11}(" + DOT + DEND + "+)?" + END,
        "rat_gene": "^ENSRNOG" + DEND + "{11}(" + DOT + DEND + "+)?" + END,
        "zebrafish_gene": "^ENSDARG" + DEND + "{11}(" + DOT + DEND + "+)?" + END,
        "fly_gene": "^FBgn" + DEND + "{7}" + END,
        "worm_gene": "^WBGene" + DEND + "{8}" + END,
        "yeast_gene": "^Y[A-P][LR]" + DEND + "{3}[WC](-[A-Z])?" + END,
    }

    other_patterns = {
        "refseq_mrna": "^NM_" + DEND + "+(" + DOT + DEND + "+)?" + END,
        "refseq_protein": "^NP_" + DEND + "+(" + DOT + DEND + "+)?" + END,
        "refseq_ncrna": "^NR_" + DEND + "+(" + DOT + DEND + "+)?" + END,
        "uniprot": "^[OPQ][0-9][A-Z0-9]{3}[0-9]|[A-NR-Z][0-9]([A-Z][A-Z0-9]{2}[0-9]){1,2}" + END,
        "gene_symbol": "^[A-Z][A-Z0-9]{1,10}(-[A-Z0-9]+)?" + END,
        "gene_symbol_mixed": "^[A-Za-z][A-Za-z0-9]{1,15}" + END,
    }

    result = {
        "status": "success",
        "gene_index_source": None,
        "total_genes": 0,
        "pattern_matches": {},
        "ensembl_detected": False,
        "primary_pattern": None,
        "sample_genes": [],
    }

    genes = []

    # Try to get genes from H5AD file
    if h5ad_file and os.path.exists(h5ad_file):
        try:
            import scanpy as sc
            adata = sc.read_h5ad(h5ad_file)
            genes = list(adata.var_names)
            result["gene_index_source"] = f"h5ad_file: {h5ad_file}"
            result["h5ad_n_cells"] = adata.n_obs
            result["h5ad_n_genes"] = adata.n_vars
        except Exception as e:
            result["h5ad_error"] = str(e)

    # Try to get genes from gene_index parameter
    if not genes and gene_index:
        if isinstance(gene_index, str):
            genes = [g.strip() for g in gene_index.split(",")]
        elif isinstance(gene_index, list):
            genes = gene_index
        result["gene_index_source"] = "parameter"

    # Demo mode if no genes provided
    if not genes:
        result["status"] = "demo_mode"
        result["message"] = "No gene index provided. Showing pattern detection capabilities."
        result["demo_info"] = {
            "supported_ensembl_patterns": list(ensembl_patterns.keys()),
            "other_patterns": list(other_patterns.keys()),
            "example_ids": {
                "human_ensembl": "ENSG00000139618",
                "mouse_ensembl": "ENSMUSG00000029580",
                "gene_symbol": "BRCA1, TP53, GAPDH",
                "refseq": "NM_007294",
            },
            "usage": "Provide h5ad_file or gene_index parameter",
        }
        return result

    result["total_genes"] = len(genes)
    result["sample_genes"] = genes[:10]

    # Check patterns
    all_patterns = {**ensembl_patterns, **other_patterns}
    pattern_counts = {name: 0 for name in all_patterns}

    for gene in genes:
        gene_str = str(gene).strip()
        for pattern_name, pattern in all_patterns.items():
            if re.match(pattern, gene_str):
                pattern_counts[pattern_name] += 1
                break  # Count each gene only once

    # Filter to non-zero counts
    result["pattern_matches"] = {k: v for k, v in pattern_counts.items() if v > 0}

    # Determine primary pattern
    if result["pattern_matches"]:
        primary = max(result["pattern_matches"], key=result["pattern_matches"].get)
        result["primary_pattern"] = primary
        result["primary_pattern_count"] = result["pattern_matches"][primary]
        result["primary_pattern_pct"] = round(100 * result["pattern_matches"][primary] / len(genes), 1)

    # Check if Ensembl patterns detected
    ensembl_count = sum(pattern_counts[p] for p in ensembl_patterns.keys())
    result["ensembl_detected"] = ensembl_count > 0
    result["ensembl_count"] = ensembl_count
    result["ensembl_pct"] = round(100 * ensembl_count / len(genes), 1) if genes else 0

    # Count unmatched
    total_matched = sum(result["pattern_matches"].values())
    result["unmatched_count"] = len(genes) - total_matched
    result["unmatched_pct"] = round(100 * (len(genes) - total_matched) / len(genes), 1)

    # Sample unmatched genes
    unmatched = []
    for gene in genes[:100]:
        gene_str = str(gene).strip()
        matched = False
        for pattern in all_patterns.values():
            if re.match(pattern, gene_str):
                matched = True
                break
        if not matched:
            unmatched.append(gene_str)
    result["sample_unmatched"] = unmatched[:10]

    return result

# Execute the function
try:
    result = check_ensembl_patterns(
        gene_index=auto_convert(os.environ.get("PARAM_GENE_INDEX", "")),
        h5ad_file=auto_convert(os.environ.get("PARAM_H5AD_FILE", "")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "check_ensembl_patterns",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("check_ensembl_patterns_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("check_ensembl_patterns_output.txt", "w") as f:
    f.write("Biomni: Check Ensembl Patterns" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "check_ensembl_patterns"
    END_VERSIONS
    """
}

workflow CHECK_ENSEMBL_PATTERNS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CHECK_ENSEMBL_PATTERNS(ch_input)

    emit:
    results = CHECK_ENSEMBL_PATTERNS.out.results
    output = CHECK_ENSEMBL_PATTERNS.out.output
    versions = CHECK_ENSEMBL_PATTERNS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CHECK_ENSEMBL_PATTERNS_WORKFLOW(ch_input)

    CHECK_ENSEMBL_PATTERNS_WORKFLOW.out.output.view { "Output: $it" }
}
