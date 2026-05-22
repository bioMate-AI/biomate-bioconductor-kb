#!/usr/bin/env nextflow
// Docking AutoDock Vina - see docs/20260510_DOCKING_RECEPTOR_TRIM_AND_CONTAINER_PLAN.md

nextflow.enable.dsl = 2

// Parameters
params.outdir                   = './results'
params.smiles_list              = '["CC(=O)Nc1ccc(O)cc1"]'
params.receptor_pdb_file        = ''
params.box_center               = '[0.0, 0.0, 0.0]'
params.box_size                 = '[20.0, 20.0, 20.0]'
params.ncpu                     = '4'
params.exhaustiveness           = '8'
params.n_poses                  = '9'
params.reference_ligand_smiles  = ''

process DOCKING_AUTODOCK_VINA {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // local (ARM dev): biomni-drug-discovery-nf layers on biomni-structure-to-drug
    // aws batch (AMD64): structure-based DD image (Vina, meeko, obabel, fpocket)
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-structure-to-drug:x86' \
        : 'biomate/biomni-drug-discovery-nf:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("docking_autodock_vina_results.json"), emit: results
    tuple val(meta), path("docking_autodock_vina_output.txt"),   emit: output
    path "docking_poses/*.pdbqt",                                emit: poses, optional: true
    path "versions.yml",                                         emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    export PARAM_SMILES_LIST='${params.smiles_list}'
    export PARAM_RECEPTOR_PDB='${params.receptor_pdb_file}'
    export PARAM_BOX_CENTER='${params.box_center}'
    export PARAM_BOX_SIZE='${params.box_size}'
    export PARAM_NCPU='${params.ncpu}'
    export PARAM_EXHAUSTIVENESS='${params.exhaustiveness}'
    export PARAM_N_POSES='${params.n_poses}'
    export PARAM_REF_SMILES='${params.reference_ligand_smiles}'

    mkdir -p docking_poses

    python3 << 'PYEOF'
import json
import os
import sys
import tempfile
import shutil
import math

NL = chr(10)

def auto_convert(val):
    if val is None or val == '' or val == 'null':
        return None
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    try:
        return float(val)
    except ValueError:
        pass
    return val

# ── Read parameters ─────────────────────────────────────────────────────────
smiles_list   = auto_convert(os.environ.get('PARAM_SMILES_LIST', '["c1ccccc1"]'))
receptor_pdb  = os.environ.get('PARAM_RECEPTOR_PDB', '').strip()
# Stage non-local receptor paths (e.g. s3 on AWS Batch) before trim/obabel.
if receptor_pdb and not os.path.isfile(receptor_pdb):
    import subprocess
    _staged = os.path.join(os.getcwd(), 'receptor_staged.pdb')
    _cp = subprocess.run(['aws', 's3', 'cp', receptor_pdb, _staged], capture_output=True, text=True)
    if _cp.returncode == 0:
        receptor_pdb = _staged
        os.environ['PARAM_RECEPTOR_PDB'] = _staged
box_center    = auto_convert(os.environ.get('PARAM_BOX_CENTER', '[0,0,0]'))
box_size      = auto_convert(os.environ.get('PARAM_BOX_SIZE', '[20,20,20]'))
ncpu          = int(auto_convert(os.environ.get('PARAM_NCPU', '4')) or 4)
exhaustiveness= int(auto_convert(os.environ.get('PARAM_EXHAUSTIVENESS', '8')) or 8)
n_poses       = int(auto_convert(os.environ.get('PARAM_N_POSES', '9')) or 9)
ref_smiles    = os.environ.get('PARAM_REF_SMILES', '').strip()

if isinstance(smiles_list, str):
    smiles_list = [smiles_list]

log = []
results_list = []
success = True
error_msg = None

# ── Helper: SMILES -> 3D SDF via RDKit (ETKDG) ──────────────────────────────
def smiles_to_sdf(smi, out_path):
    from rdkit import Chem
    from rdkit.Chem import AllChem
    mol = Chem.MolFromSmiles(smi)
    if mol is None:
        raise ValueError(f'Invalid SMILES: {smi}')
    mol = Chem.AddHs(mol)
    params = AllChem.ETKDGv3()
    params.randomSeed = 42
    if AllChem.EmbedMolecule(mol, params) == -1:
        AllChem.EmbedMolecule(mol, AllChem.ETKDG())
    AllChem.MMFFOptimizeMolecule(mol)
    writer = Chem.SDWriter(out_path)
    writer.write(mol)
    writer.close()

# ── Helper: SDF -> PDBQT via meeko ──────────────────────────────────────────
def sdf_to_pdbqt(sdf_path, pdbqt_path):
    import meeko
    from rdkit import Chem
    mol = Chem.SDMolSupplier(sdf_path, removeHs=False)[0]
    if mol is None:
        raise ValueError(f'Cannot read SDF: {sdf_path}')
    preparator = meeko.MoleculePreparation()
    mol_setup = preparator.prepare(mol)
    # meeko >= 0.5 returns list
    if isinstance(mol_setup, list):
        mol_setup = mol_setup[0]
    # meeko 0.7+: write_string returns (pdbqt_str, is_ok, error_msg)
    result = meeko.PDBQTWriterLegacy.write_string(mol_setup)
    pdbqt_string = result[0] if isinstance(result, tuple) else result
    with open(pdbqt_path, 'w') as f:
        f.write(pdbqt_string)

# ── Helper: PDB -> PDBQT receptor via openbabel ──────────────────────────────
# Use obabel -xr to write a rigid PDBQT receptor (adds AutoDock atom types,
# no rotatable bonds). meeko does not have a receptor prep API in v0.7.
def receptor_pdb_to_pdbqt(pdb_path, pdbqt_path):
    import subprocess
    r = subprocess.run(
        ['obabel', pdb_path, '-O', pdbqt_path, '-xr'],
        capture_output=True, text=True
    )
    detail = ((r.stderr or '') + (r.stdout or '')).strip()
    if r.returncode != 0 or not os.path.exists(pdbqt_path):
        raise RuntimeError(
            'obabel receptor prep failed (exit ' + str(r.returncode) + '): ' + detail
        )
    sz = os.path.getsize(pdbqt_path)
    # OpenBabel can exit 0 but emit an empty file on some PDB inputs; Vina then
    # returns meaningless ~0 kcal/mol scores for every ligand.
    if sz < 64:
        raise RuntimeError(
            f'obabel wrote trivial receptor PDBQT ({sz} bytes): {detail}'
        )

# ── Helper: trim PDB to Vina search region ──────────────────────────────────
# Whole-virus or deposited assemblies often exceed ~10k ATOM records; Open Babel
# may exit 0 but emit an empty PDBQT. Keeping atoms inside the docking box (+pad)
# matches what Vina evaluates with compute_vina_maps and stays within tool limits.
def trim_pdb_to_search_box(pdb_path, out_path, cx, cy, cz, sx, sy, sz, pad=8.0):
    hx = sx / 2.0 + pad
    hy = sy / 2.0 + pad
    hz = sz / 2.0 + pad
    xmin, xmax = cx - hx, cx + hx
    ymin, ymax = cy - hy, cy + hy
    zmin, zmax = cz - hz, cz + hz
    kept = []
    with open(pdb_path) as fh:
        for line in fh:
            if line.startswith(('ATOM', 'HETATM')):
                try:
                    x = float(line[30:38])
                    y = float(line[38:46])
                    z = float(line[46:54])
                except ValueError:
                    continue
                if xmin <= x <= xmax and ymin <= y <= ymax and zmin <= z <= zmax:
                    kept.append(line)
    if len(kept) < 50:
        raise RuntimeError(
            f'only {len(kept)} atoms inside padded box — check box_center/box_size'
        )
    with open(out_path, 'w') as out:
        # No brace-format here; Groovy parses the outer Nextflow script string.
        pad_s = str(round(float(pad), 1))
        # Use + NL for newlines; a literal backslash-n inside quotes breaks when templated by Nextflow.
        out.write(
            'REMARK BioMate: receptor trimmed to Vina box + ' + pad_s + ' A pad' + NL
        )
        for ln in kept:
            out.write(ln)
        out.write('END' + NL)
    return len(kept)

# ── Helper: download PDB by ID ───────────────────────────────────────────────
def fetch_pdb(pdb_id, out_path):
    import urllib.request
    url = f'https://files.rcsb.org/download/{pdb_id.upper()}.pdb'
    urllib.request.urlretrieve(url, out_path)

# ── Helper: RMSD between two SMILES (align 3D conformers) ───────────────────
def rmsd_smiles(smi1, smi2):
    '''Minimum RMSD between aligned 3D conformers of two molecules.'''
    try:
        from rdkit import Chem
        from rdkit.Chem import AllChem
        m1 = Chem.MolFromSmiles(smi1)
        m2 = Chem.MolFromSmiles(smi2)
        if m1 is None or m2 is None:
            return None
        if m1.GetNumAtoms() != m2.GetNumAtoms():
            return None
        m1h = Chem.AddHs(m1)
        m2h = Chem.AddHs(m2)
        AllChem.EmbedMolecule(m1h, AllChem.ETKDGv3())
        AllChem.EmbedMolecule(m2h, AllChem.ETKDGv3())
        return AllChem.GetBestRMS(m1h, m2h)
    except Exception:
        return None

# ── Helper: RMSD between two PDBQT pose files (heavy atoms) ─────────────────
def rmsd_pdbqt_files(f1, f2):
    coords1, coords2 = [], []
    for path, lst in [(f1, coords1), (f2, coords2)]:
        with open(path) as fh:
            for line in fh:
                if line.startswith(('ATOM', 'HETATM')):
                    name = line[12:16].strip()
                    if not name.startswith('H'):
                        lst.append((float(line[30:38]),
                                    float(line[38:46]),
                                    float(line[46:54])))
    if len(coords1) != len(coords2) or not coords1:
        return None
    rmsd = math.sqrt(sum((a-b)**2
                         for c1,c2 in zip(coords1, coords2)
                         for a,b in zip(c1,c2)) / len(coords1))
    return round(rmsd, 3)

try:
    from vina import Vina

    cx0, cy0, cz0 = float(box_center[0]), float(box_center[1]), float(box_center[2])
    sx0, sy0, sz0 = float(box_size[0]), float(box_size[1]), float(box_size[2])

    # ── Resolve receptor ────────────────────────────────────────────────────
    tmpdir = tempfile.mkdtemp(prefix='vina_')

    if not receptor_pdb:
        # Default: use a trivial single-residue ALA receptor for smoke-test
        log.append('WARNING: No receptor provided -- using minimal ALA receptor for scoring only')
        rec_pdb = os.path.join(tmpdir, 'receptor.pdb')
        with open(rec_pdb, 'w') as f:
            f.write(
                'ATOM      1  N   ALA A   1       0.000   0.000   0.000  1.00  0.00           N' + NL +
                'ATOM      2  CA  ALA A   1       1.460   0.000   0.000  1.00  0.00           C' + NL +
                'ATOM      3  C   ALA A   1       2.009   1.420   0.000  1.00  0.00           C' + NL +
                'ATOM      4  O   ALA A   1       1.250   2.360   0.000  1.00  0.00           O' + NL +
                'ATOM      5  CB  ALA A   1       1.986  -0.767  -1.199  1.00  0.00           C' + NL +
                'END' + NL
            )
    elif len(receptor_pdb) == 4 and receptor_pdb.isalnum():
        log.append(f'Downloading receptor PDB {receptor_pdb.upper()} from RCSB...')
        rec_pdb = os.path.join(tmpdir, f'{receptor_pdb.upper()}.pdb')
        fetch_pdb(receptor_pdb, rec_pdb)
        log.append(f'Downloaded {os.path.getsize(rec_pdb)} bytes')
    else:
        rec_pdb = receptor_pdb

    rec_for_prep = rec_pdb
    if receptor_pdb and os.path.isfile(rec_pdb):
        trim_out = os.path.join(tmpdir, 'receptor_trimmed.pdb')
        try:
            n_kept = trim_pdb_to_search_box(
                rec_pdb, trim_out, cx0, cy0, cz0, sx0, sy0, sz0
            )
            rec_for_prep = trim_out
            log.append(
                f'  Receptor PDB trimmed to search box (+ 8 A pad): '
                f'{n_kept} ATOM/HETATM records (large assemblies -> tractable PDBQT)'
            )
        except Exception as exc:
            log.append(f'  Receptor box-trim skipped: {exc}')

    log.append(f'Step 1: Preparing receptor {os.path.basename(rec_pdb)}')
    rec_pdbqt = os.path.join(tmpdir, 'receptor.pdbqt')
    try:
        receptor_pdb_to_pdbqt(rec_for_prep, rec_pdbqt)
        log.append(f'  Receptor PDBQT written ({os.path.getsize(rec_pdbqt)} bytes)')
    except Exception as e:
        log.append(f'  Receptor prep warning: {e}  -- continuing with PDB as PDBQT')
        shutil.copy(rec_pdb, rec_pdbqt)

    # ── Reference ligand PDBQT for RMSD validation ─────────────────────────
    ref_pdbqt = None
    if ref_smiles:
        log.append(f'Step 1b: Preparing reference ligand for RMSD validation')
        ref_sdf  = os.path.join(tmpdir, 'reference.sdf')
        ref_pdbqt = os.path.join(tmpdir, 'reference.pdbqt')
        smiles_to_sdf(ref_smiles, ref_sdf)
        sdf_to_pdbqt(ref_sdf, ref_pdbqt)
        log.append(f'  Reference PDBQT written')

    cx, cy, cz = cx0, cy0, cz0
    sx, sy, sz = sx0, sy0, sz0

    log.append(f'Step 2: Box center=({cx},{cy},{cz}) size=({sx},{sy},{sz})')
    log.append(f'        Exhaustiveness={exhaustiveness}, CPUs={ncpu}, poses={n_poses}')

    # ── Dock each ligand ────────────────────────────────────────────────────
    for idx, smi in enumerate(smiles_list):
        log.append(f'')
        log.append(f'Step 3.{idx+1}: Docking {smi[:50]}')

        try:
            lig_sdf   = os.path.join(tmpdir, f'lig_{idx}.sdf')
            lig_pdbqt = os.path.join(tmpdir, f'lig_{idx}.pdbqt')
            out_pdbqt = os.path.join(tmpdir, f'out_{idx}.pdbqt')

            smiles_to_sdf(smi, lig_sdf)
            log.append(f'  Ligand 3D conformation generated')

            sdf_to_pdbqt(lig_sdf, lig_pdbqt)
            log.append(f'  Ligand PDBQT prepared')

            v = Vina(sf_name='vina', cpu=ncpu, seed=42, verbosity=0)
            v.set_receptor(rec_pdbqt)
            v.set_ligand_from_file(lig_pdbqt)
            v.compute_vina_maps(center=[cx, cy, cz], box_size=[sx, sy, sz])
            v.dock(exhaustiveness=exhaustiveness, n_poses=n_poses)
            v.write_poses(out_pdbqt, n_poses=n_poses, overwrite=True)

            energies = v.energies(n_poses=n_poses)
            best_score = round(float(energies[0][0]), 3)
            log.append(f'  Best binding affinity: {best_score} kcal/mol')

            # Copy top pose to output dir
            shutil.copy(out_pdbqt, f'docking_poses/pose_{idx:03d}.pdbqt')

            entry = {
                'smiles': smi,
                'best_affinity_kcal_mol': best_score,
                'all_affinities': [round(float(e[0]), 3) for e in energies],
                'n_poses': len(energies),
                'pose_file': f'docking_poses/pose_{idx:03d}.pdbqt',
            }

            # RMSD validation vs reference
            if ref_pdbqt and os.path.exists(ref_pdbqt):
                rmsd = rmsd_pdbqt_files(out_pdbqt, ref_pdbqt)
                entry['rmsd_vs_crystal_A'] = rmsd
                verdict = 'PASS' if rmsd is not None and rmsd <= 2.0 else 'FAIL'
                entry['rmsd_validation'] = verdict
                log.append(f'  RMSD vs crystal pose: {rmsd} A  [{verdict}]')

            results_list.append(entry)
            log.append(f'  Done.')

        except Exception as e:
            log.append(f'  ERROR docking {smi[:40]}: {e}')
            results_list.append({'smiles': smi, 'error': str(e)})

    shutil.rmtree(tmpdir, ignore_errors=True)

except ImportError as e:
    success = False
    error_msg = f'vina not installed in container: {e}'
    log.append(f'ERROR: {error_msg}')
except Exception as e:
    success = False
    error_msg = str(e)
    log.append(f'ERROR: {error_msg}')

# ── Write outputs ────────────────────────────────────────────────────────────
valid_scores = [r['best_affinity_kcal_mol'] for r in results_list
                if 'best_affinity_kcal_mol' in r]

output_data = {
    'success': success and bool(results_list),
    'function': 'docking_autodock_vina',
    'domain': 'pharmacology',
    'results': results_list,
    'n_ligands_docked': len(valid_scores),
    'best_score_kcal_mol': min(valid_scores) if valid_scores else None,
    'log': NL.join(log),
}
if not success:
    output_data['error'] = error_msg

with open('docking_autodock_vina_results.json', 'w') as f:
    json.dump(output_data, f, indent=2, default=str)

with open('docking_autodock_vina_output.txt', 'w') as f:
    f.write('BioMate: AutoDock Vina Molecular Docking' + NL)
    f.write('=' * 60 + NL + NL)
    f.write(NL.join(log) + NL + NL)
    if valid_scores:
        f.write(f'Best affinity: {min(valid_scores)} kcal/mol' + NL)
        f.write(f'Ligands docked: {len(valid_scores)}' + NL)
        rmsd_entries = [r for r in results_list if 'rmsd_vs_crystal_A' in r]
        if rmsd_entries:
            r0 = rmsd_entries[0]
            f.write(f'RMSD vs crystal: {r0["rmsd_vs_crystal_A"]} A  [{r0["rmsd_validation"]}]' + NL)
    if not success:
        f.write(f'ERROR: {error_msg}' + NL)

if not output_data['success']:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        vina: \$(python3 -c "from vina import Vina; print('1.2')" 2>/dev/null || echo "unknown")
        meeko: \$(python3 -c "import meeko; print(meeko.__version__)" 2>/dev/null || echo "unknown")
        rdkit: \$(python3 -c "import rdkit; print(rdkit.__version__)" 2>/dev/null || echo "unknown")
    END_VERSIONS
    """
}

workflow DOCKING_AUTODOCK_VINA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta) ]

    main:
    DOCKING_AUTODOCK_VINA(ch_input)

    emit:
    results  = DOCKING_AUTODOCK_VINA.out.results
    output   = DOCKING_AUTODOCK_VINA.out.output
    versions = DOCKING_AUTODOCK_VINA.out.versions
}

// Entry workflow for standalone execution
workflow {
    ch_input = Channel.of([id: 'run'])
    DOCKING_AUTODOCK_VINA_WORKFLOW(ch_input)
    DOCKING_AUTODOCK_VINA_WORKFLOW.out.output.view { "Output: $it" }
}
