#!/usr/bin/env nextflow
nextflow.enable.dsl=2

params.fasta  = 's3://biomate-nextflow-work/pilot/sequences/a2a.fasta'
params.outdir = 's3://biomate-nextflow-work/pilot/results/a2a-boltz'

process BOLTZ_ENSEMBLE {
    tag "a2a_boltz"
    label 'process_gpu'
    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:nextflow'
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path fasta

    output:
    path "boltz_ensemble.tar.gz", emit: ensemble
    path "versions.yml",          emit: versions

    script:
    """
    mkdir -p boltz_out ensemble_pdbs

    # Boltz predict — generates predictions/model_0.cif by default
    # Use --diffusion_samples for multiple conformers
    boltz predict \\
        ${fasta} \\
        --out_dir boltz_out/ \\
        --diffusion_samples 50 \\
        --num_workers ${task.cpus} \\
        --no_msa 2>&1 || \\
    boltz predict \\
        ${fasta} \\
        --out_dir boltz_out/ \\
        --num_workers ${task.cpus} 2>&1

    # Convert outputs to PDB ensemble
    python3 - << 'PYEOF'
import glob, os, shutil, subprocess

cifs = glob.glob("boltz_out/**/*.cif", recursive=True)
pdbs_in = glob.glob("boltz_out/**/*.pdb", recursive=True)
all_structs = sorted(cifs + pdbs_in)
print(f"Boltz output: {len(all_structs)} structures")

os.makedirs("ensemble_pdbs", exist_ok=True)
for i, f in enumerate(all_structs):
    ext = os.path.splitext(f)[1]
    dest = f"ensemble_pdbs/conf_{i:04d}{ext}"
    shutil.copy(f, dest)
    # Convert CIF to PDB if needed
    if ext == '.cif':
        try:
            import gemmi
            st = gemmi.read_structure(dest)
            pdb_dest = dest.replace('.cif', '.pdb')
            st.write_pdb(pdb_dest)
            os.remove(dest)
        except Exception:
            pass
PYEOF

    tar -czf boltz_ensemble.tar.gz -C ensemble_pdbs .

    python3 -c "
import subprocess, sys
ver = subprocess.run(['boltz','--version'], capture_output=True, text=True).stdout.strip()
print('BOLTZ_ENSEMBLE:')
print('    boltz: ' + (ver or 'unknown'))
" > versions.yml
    """
}

workflow {
    fasta_ch = Channel.value(file(params.fasta))
    BOLTZ_ENSEMBLE(fasta_ch)
}
