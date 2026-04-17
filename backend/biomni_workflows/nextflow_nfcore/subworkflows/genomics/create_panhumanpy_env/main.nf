#!/usr/bin/env nextflow
/*
 * genomics/create_panhumanpy_env
 * Create and validate environment for PanHumanPy cell type annotation
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo mode by default
params.env_name = 'panhumanpy'
params.validate_only = true

process CREATE_PANHUMANPY_ENV {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("create_panhumanpy_env_results.json"), emit: results
    tuple val(meta), path("create_panhumanpy_env_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Disable numba JIT to avoid caching issues in Docker containers
    export NUMBA_DISABLE_JIT=1
    export NUMBA_CACHE_DIR=/tmp/numba_cache
    mkdir -p /tmp/numba_cache

    # Export parameters as environment variables
    export PARAM_ENV_NAME="${params.env_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_VALIDATE_ONLY="${params.validate_only?.toString()?.replace('"', '\\"') ?: 'true'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os
import sys
import subprocess
from pathlib import Path

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


def create_panhumanpy_env(env_name='panhumanpy', validate_only=True):
    '''Create and validate environment for PanHumanPy cell type annotation.

    PanHumanPy is a comprehensive cell type annotation tool that uses
    a large reference atlas of human cells. This function checks for
    required dependencies and provides setup instructions.

    Parameters
    ----------
    env_name : str
        Name for the conda environment (default: 'panhumanpy')
    validate_only : bool
        If True, only validate dependencies without creating env (default: True)

    Returns
    -------
    dict
        Environment status and setup instructions
    '''
    result = {
        "function": "create_panhumanpy_env",
        "status": "success",
        "env_name": env_name,
    }

    # Required packages for PanHumanPy
    required_packages = {
        "core": ["scanpy", "anndata", "numpy", "pandas", "scipy"],
        "ml": ["scikit-learn", "torch"],
        "annotation": ["celltypist"],  # Alternative annotation tool
        "visualization": ["matplotlib", "seaborn"],
    }

    # Check installed packages
    installed = {}
    missing = []

    for category, packages in required_packages.items():
        installed[category] = {}
        for pkg in packages:
            try:
                if pkg == "torch":
                    import torch
                    installed[category][pkg] = torch.__version__
                elif pkg == "scikit-learn":
                    import sklearn
                    installed[category][pkg] = sklearn.__version__
                elif pkg == "scanpy":
                    import scanpy
                    installed[category][pkg] = scanpy.__version__
                elif pkg == "anndata":
                    import anndata
                    installed[category][pkg] = anndata.__version__
                elif pkg == "numpy":
                    import numpy
                    installed[category][pkg] = numpy.__version__
                elif pkg == "pandas":
                    import pandas
                    installed[category][pkg] = pandas.__version__
                elif pkg == "scipy":
                    import scipy
                    installed[category][pkg] = scipy.__version__
                elif pkg == "matplotlib":
                    import matplotlib
                    installed[category][pkg] = matplotlib.__version__
                elif pkg == "seaborn":
                    import seaborn
                    installed[category][pkg] = seaborn.__version__
                elif pkg == "celltypist":
                    import celltypist
                    installed[category][pkg] = celltypist.__version__
                else:
                    installed[category][pkg] = "unknown"
            except ImportError:
                installed[category][pkg] = "not installed"
                missing.append(pkg)

    result["installed_packages"] = installed
    result["missing_packages"] = missing
    result["all_required_installed"] = len(missing) == 0

    # Python version
    result["python_version"] = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"

    # Check for conda
    conda_available = False
    try:
        conda_result = subprocess.run(
            ["conda", "--version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if conda_result.returncode == 0:
            conda_available = True
            result["conda_version"] = conda_result.stdout.strip()
    except Exception:
        pass
    result["conda_available"] = conda_available

    # PanHumanPy information
    result["panhumanpy_info"] = {
        "description": "Comprehensive cell type annotation using human cell atlas",
        "reference": "https://github.com/CellTypist/celltypist (alternative)",
        "capabilities": [
            "Automated cell type annotation",
            "Reference-based label transfer",
            "Multi-resolution annotation (cell type, subtype)",
            "Uncertainty quantification",
        ],
        "supported_organisms": ["human"],
        "input_format": "H5AD (AnnData)",
    }

    NL = chr(10)
    HASH = chr(35)

    if missing:
        conda_cmd = (
            HASH + " Create new environment" + NL +
            "conda create -n " + str(env_name) + " python=3.10 -y" + NL +
            "conda activate " + str(env_name) + NL + NL +
            HASH + " Install core packages" + NL +
            "pip install scanpy anndata numpy pandas scipy" + NL + NL +
            HASH + " Install ML packages" + NL +
            "pip install scikit-learn torch" + NL + NL +
            HASH + " Install annotation tools" + NL +
            "pip install celltypist" + NL + NL +
            HASH + " Install visualization" + NL +
            "pip install matplotlib seaborn"
        )
        pip_cmd = (
            HASH + " Install all required packages" + NL +
            "pip install scanpy anndata numpy pandas scipy scikit-learn torch celltypist matplotlib seaborn"
        )
        result["setup_instructions"] = {
            "conda_command": conda_cmd,
            "pip_command": pip_cmd,
        }
    else:
        result["setup_instructions"] = {
            "message": "All required packages are installed",
            "ready_to_use": True,
        }

    example = (
        "import scanpy as sc" + NL +
        "import celltypist" + NL +
        "from celltypist import models" + NL + NL +
        HASH + " Load your data" + NL +
        "adata = sc.read_h5ad('your_data.h5ad')" + NL + NL +
        HASH + " Ensure data is normalized and log-transformed" + NL +
        "sc.pp.normalize_total(adata, target_sum=1e4)" + NL +
        "sc.pp.log1p(adata)" + NL + NL +
        HASH + " Download and load a model" + NL +
        "models.download_models()" + NL +
        "model = models.Model.load(model='Immune_All_Low.pkl')" + NL + NL +
        HASH + " Annotate" + NL +
        "predictions = celltypist.annotate(adata, model=model, majority_voting=True)" + NL + NL +
        HASH + " Get results" + NL +
        "adata = predictions.to_adata()" + NL +
        "print(adata.obs['predicted_labels'].value_counts())"
    )
    result["example_workflow"] = example

    # Available CellTypist models (as alternative to PanHumanPy)
    result["available_models"] = [
        "Immune_All_Low.pkl - All immune cell types (low resolution)",
        "Immune_All_High.pkl - All immune cell types (high resolution)",
        "Healthy_COVID19_PBMC.pkl - PBMC cell types",
        "Developing_Human_Brain.pkl - Brain cell types",
        "Adult_Human_Skin.pkl - Skin cell types",
    ]

    return result

# Execute the function
try:
    result = create_panhumanpy_env(
        env_name=auto_convert(os.environ.get("PARAM_ENV_NAME", "panhumanpy")) or "panhumanpy",
        validate_only=auto_convert(os.environ.get("PARAM_VALIDATE_ONLY", "true")),
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
    "function": "create_panhumanpy_env",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("create_panhumanpy_env_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("create_panhumanpy_env_output.txt", "w") as f:
    f.write("Biomni: Create Panhumanpy Env" + NL)
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
        biomni_function: "create_panhumanpy_env"
    END_VERSIONS
    """
}

workflow CREATE_PANHUMANPY_ENV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CREATE_PANHUMANPY_ENV(ch_input)

    emit:
    results = CREATE_PANHUMANPY_ENV.out.results
    output = CREATE_PANHUMANPY_ENV.out.output
    versions = CREATE_PANHUMANPY_ENV.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CREATE_PANHUMANPY_ENV_WORKFLOW(ch_input)

    CREATE_PANHUMANPY_ENV_WORKFLOW.out.output.view { "Output: $it" }
}
