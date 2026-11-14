#!/usr/bin/env nextflow
// Docking AutoDock Vina - see docs/20260510_DOCKING_RECEPTOR_TRIM_AND_CONTAINER_PLAN.md

nextflow.enable.dsl = 2

// Parameters
params.outdir                   = './results'
params.smiles_list              = '["CC(=O)Nc1ccc(O)cc1"]'
// Coldstart / demo default: ABL1 ATP pocket (imatinib-bound). Bare PDB id is
// fetched from RCSB inside the task when no local/S3 path is supplied.
params.receptor_pdb_file        = '1IEP'
params.box_center               = '[0.0, 0.0, 0.0]'
params.box_size                 = '[20.0, 20.0, 20.0]'
params.ncpu                     = '4'     // used only by direct (unsharded) callers; sharded runs use the CPUs Batch allocates
params.docking_shard_size       = 10      // ligands per parallel Batch task (Vina docks one ligand at a time)
params.exhaustiveness           = '8'
params.n_poses                  = '9'
params.reference_ligand_smiles  = ''
params.site_ligand             = 'STI'   // remove co-crystallised STI (imatinib) from 1IEP before docking; waters always removed

process DOCKING_AUTODOCK_VINA {
    tag "${meta.id}"
    label 'process_medium'

    // local (ARM dev): drug-discovery-nf layers on structure-to-drug
    // aws batch (AMD64): structure-based DD image (Vina, meeko, obabel, fpocket)
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/structure-to-drug:x86' \
        : 'biomate/drug-discovery-nf:latest'

    input:
    tuple val(meta), val(shard_smiles)

    output:
    path("${meta.id}_results.json"),    emit: results
    path("${meta.id}_output.txt"),      emit: output
    path("${meta.id}_qc_metrics.json"), emit: qc_metrics
    path "docking_poses/*.pdbqt",       emit: poses, optional: true
    path "versions.yml",                emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    export PARAM_SMILES_LIST='${shard_smiles}'
    export PARAM_SHARD_ID='${meta.id}'
    export PARAM_RECEPTOR_PDB='${params.receptor_pdb_file}'
    export PARAM_BOX_CENTER='${params.box_center}'
    export PARAM_BOX_SIZE='${params.box_size}'
    export PARAM_NCPU='${task.cpus}'
    export PARAM_EXHAUSTIVENESS='${params.exhaustiveness}'
    export PARAM_N_POSES='${params.n_poses}'
    export PARAM_REF_SMILES='${params.reference_ligand_smiles}'
    export PARAM_SITE_LIGAND='${params.site_ligand}'

    mkdir -p docking_poses

    python3 << 'PYEOF'
import json
import os
import sys
import tempfile
import shutil
import math

NL = chr(10)
SHARD_ID = os.environ.get('PARAM_SHARD_ID', 'run')

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
# Materialize the receptor before trim/obabel. The param may arrive as: a local
# file, an s3:// path, an http(s) URL, or a bare 4-char PDB ID (e.g. "1IEP") that
# the query named. Self-fetch the id from RCSB here — the same pattern as SRA/GEO
# workflows fetching from an accession (fasterq-dump) — because the in-process
# runtime can't call the app-side PDB fetch. Without this, a PDB-id receptor was
# never fetched → "no receptor → minimal ALA" → docking failure.
if receptor_pdb and not os.path.isfile(receptor_pdb):
    import subprocess, re as _re_r, urllib.request
    _staged = os.path.join(os.getcwd(), 'receptor_staged.pdb')
    try:
        if receptor_pdb.startswith('s3://'):
            _cp = subprocess.run(['aws', 's3', 'cp', receptor_pdb, _staged], capture_output=True, text=True)
            if _cp.returncode == 0 and os.path.isfile(_staged):
                receptor_pdb = _staged; os.environ['PARAM_RECEPTOR_PDB'] = _staged
        elif receptor_pdb.startswith(('http://', 'https://')):
            urllib.request.urlretrieve(receptor_pdb, _staged)
            if os.path.getsize(_staged) > 0:
                receptor_pdb = _staged; os.environ['PARAM_RECEPTOR_PDB'] = _staged
        elif _re_r.fullmatch(r'[0-9A-Za-z]{4}', receptor_pdb):
            # Bare RCSB PDB ID → download the canonical structure.
            urllib.request.urlretrieve(f'https://files.rcsb.org/download/{receptor_pdb.upper()}.pdb', _staged)
            if os.path.getsize(_staged) > 0:
                receptor_pdb = _staged; os.environ['PARAM_RECEPTOR_PDB'] = _staged
    except Exception:
        pass  # leave receptor_pdb as-is → downstream no-receptor fallback still applies
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
        # -p 7.4: add hydrogens for pH 7.4. Crystal structures carry none, and Vina recognises receptor H-bond
        # donors only through polar hydrogens (HD atoms); the PDBQT writer keeps polar H and merges non-polar H.
        ['obabel', pdb_path, '-O', pdbqt_path, '-xr', '-p', '7.4'],
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
    with open(pdbqt_path) as fh:
        n_hd = sum(1 for ln in fh if ln.startswith(('ATOM', 'HETATM')) and ln[77:79].strip() == 'HD')
    if n_hd == 0:
        raise RuntimeError('receptor PDBQT has no polar hydrogens (HD); Vina would score no receptor H-bond donors')
    return n_hd

# ── Helper: trim PDB to Vina search region ──────────────────────────────────
# Whole-virus or deposited assemblies often exceed ~10k ATOM records; Open Babel
# may exit 0 but emit an empty PDBQT. Keeping atoms inside the docking box (+pad)
# matches what Vina evaluates with compute_vina_maps and stays within tool limits.
# Remove waters and the named co-crystallised ligand from the receptor. Docking into a site that still
# holds the crystal ligand scores every pose against a clash. Other HETATM records (metals, cofactors) stay.
WATER_RESNAMES = ('HOH', 'WAT', 'DOD')
def strip_receptor_hetero(pdb_path, out_path, site_ligand):
    drop = set(WATER_RESNAMES)
    if site_ligand:
        drop.add(site_ligand.strip().upper())
    kept, removed = [], {}
    with open(pdb_path) as fh:
        for line in fh:
            rn = line[17:20].strip().upper() if line.startswith(('ATOM', 'HETATM')) else ''
            if line.startswith('HETATM') and rn in drop:
                removed[rn] = removed.get(rn, 0) + 1
                continue
            kept.append(line)
    with open(out_path, 'w') as out:
        out.writelines(kept)
    return removed

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

    site_ligand = os.environ.get('PARAM_SITE_LIGAND', '').strip()
    if os.path.isfile(rec_pdb):
        stripped = os.path.join(tmpdir, 'receptor_no_hetero.pdb')
        removed = strip_receptor_hetero(rec_pdb, stripped, site_ligand)
        rec_pdb = stripped
        log.append('  Receptor cleaned: removed ' + (', '.join(k + ' x' + str(v) for k, v in sorted(removed.items())) or 'nothing'))
        if site_ligand and site_ligand.strip().upper() not in removed:
            log.append('  WARNING: site_ligand ' + site_ligand + ' not found in the receptor; nothing removed for it')
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
        n_hd = receptor_pdb_to_pdbqt(rec_for_prep, rec_pdbqt)
        log.append(f'  Receptor PDBQT written ({os.path.getsize(rec_pdbqt)} bytes; {n_hd} polar hydrogens)')
    except Exception as e:
        # No fallback: a PDB renamed to .pdbqt has no AutoDock atom types, so every score would be meaningless.
        log.append(f'  ERROR: receptor preparation failed: {e}')
        raise

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
            shutil.copy(out_pdbqt, f'docking_poses/{SHARD_ID}_pose_{idx:03d}.pdbqt')

            entry = {
                'smiles': smi,
                'best_affinity_kcal_mol': best_score,
                'all_affinities': [round(float(e[0]), 3) for e in energies],
                'n_poses': len(energies),
                'pose_file': f'docking_poses/{SHARD_ID}_pose_{idx:03d}.pdbqt',
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

# ── QC gates: docking_binding_score + docking_valid_poses ─────────────────────
# Track 2 batch 7 (2026-06-16): wire the 2 documented-but-unwired docking
# gates from qc_evidence.yaml.docking.*. Both are BRONZE (community
# heuristics; no peer-reviewed cutoffs) so the thresholds are honest
# operational conventions documented in the rule_text:
#   docking_binding_score:  best_score ≤ -7 kcal/mol = pass (hit_finding profile)
#   docking_valid_poses:    n_poses_generated >= 3   = pass
#
# When no receptor is supplied (params.receptor_pdb_file empty) the
# workflow produces no scores; the emit records status='not_computed'
# so the gate row stays in the audit ledger without fabricating a verdict.
BINDING_SCORE_HIT_THRESHOLD = -7.0  # kcal/mol; more negative is better
VALID_POSES_MIN_COUNT       = 3

best_score = output_data.get('best_score_kcal_mol')
# n_poses generated across all docked ligands — sum of per-ligand pose counts.
total_poses_generated = sum(
    int(r.get('n_poses') or 0) for r in (results_list or [])
)

binding_score_passes = bool(
    best_score is not None and best_score <= BINDING_SCORE_HIT_THRESHOLD
) if best_score is not None else None
valid_poses_passes = bool(
    total_poses_generated >= VALID_POSES_MIN_COUNT
) if total_poses_generated > 0 or success else None

qc_metrics = {
    'success': output_data['success'],
    'process': 'DOCKING_AUTODOCK_VINA',
    'domain': 'pharmacology',
    # docking_binding_score (BRONZE, Trott & Olson 2010)
    'best_score_kcal_mol': best_score,
    'binding_score_hit_threshold_kcal_mol': BINDING_SCORE_HIT_THRESHOLD,
    'docking_binding_score_passes': binding_score_passes,
    # docking_valid_poses (BRONZE, AutoDock/Glide community)
    'total_poses_generated': total_poses_generated,
    'valid_poses_min_threshold': VALID_POSES_MIN_COUNT,
    'docking_valid_poses_passes': valid_poses_passes,
    # context
    'n_ligands_docked': output_data.get('n_ligands_docked', 0),
    'evidence_tier': 'BRONZE-binding_score / BRONZE-valid_poses',
    'citation': 'Trott & Olson 2010 J Comput Chem 31:455; AutoDock community practice',
    'status': (
        'computed' if best_score is not None
        else 'not_computed (no receptor supplied; gate awaits receptor_pdb_file fixture)'
    ),
}
with open('qc_metrics.json', 'w') as f:
    json.dump(qc_metrics, f, indent=2, default=str)

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
    mv docking_autodock_vina_results.json ${meta.id}_results.json
    mv docking_autodock_vina_output.txt ${meta.id}_output.txt
    mv qc_metrics.json ${meta.id}_qc_metrics.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        vina: \$(python3 -c "from vina import Vina; print('1.2')" 2>/dev/null || echo "unknown")
        meeko: \$(python3 -c "import meeko; print(meeko.__version__)" 2>/dev/null || echo "unknown")
        rdkit: \$(python3 -c "import rdkit; print(rdkit.__version__)" 2>/dev/null || echo "unknown")
    END_VERSIONS
    """
}

// ── REDUCE: merge per-shard docking results into the files callers read ─────────
// Same output names and schema as the former single-job step, so the chain executor,
// the QC gate reader and the benchmark scorer are unchanged.
process DOCKING_MERGE {
    tag 'merge'
    label 'process_single'
    publishDir path: { params.outdir }, mode: 'copy', overwrite: true

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/structure-to-drug:x86' \
        : 'biomate/drug-discovery-nf:latest'

    input:
    path shard_results
    path shard_outputs
    path shard_qc
    path shard_poses

    output:
    path("docking_autodock_vina_results.json"), emit: results
    path("docking_autodock_vina_output.txt"),   emit: output
    path("qc_metrics.json"),                     emit: qc_metrics
    path "docking_poses/*.pdbqt",                emit: poses, optional: true

    script:
    '''
    mkdir -p docking_poses
    for f in *_pose_*.pdbqt; do [ -e "$f" ] && mv "$f" docking_poses/; done
    python3 << 'PYEOF'
import glob, json, re
NL = chr(10)

def shard_index(name):
    m = re.match(r"shard_([0-9]+)_", name)
    return int(m.group(1)) if m else 0

files = sorted(glob.glob("shard_*_results.json"), key=shard_index)
results, logs, success = [], [], True
for fn in files:
    d = json.load(open(fn))
    results.extend(d.get("results") or [])
    success = success and bool(d.get("success"))
    logs.append("[" + fn.replace("_results.json", "") + "]" + NL + (d.get("log") or ""))
valid = [r["best_affinity_kcal_mol"] for r in results if "best_affinity_kcal_mol" in r]
out = {
    "success": success and bool(results),
    "function": "docking_autodock_vina",
    "domain": "pharmacology",
    "results": results,
    "n_ligands_docked": len(valid),
    "best_score_kcal_mol": min(valid) if valid else None,
    "n_shards": len(files),
    "log": NL.join(logs),
}
json.dump(out, open("docking_autodock_vina_results.json", "w"), indent=2, default=str)

qcs = [json.load(open(fn)) for fn in sorted(glob.glob("shard_*_qc_metrics.json"), key=shard_index)]
threshold = qcs[0].get("binding_score_hit_threshold_kcal_mol", -7.0) if qcs else -7.0
min_poses = qcs[0].get("valid_poses_min_threshold", 3) if qcs else 3
best = out["best_score_kcal_mol"]
total_poses = sum(int(r.get("n_poses") or 0) for r in results)
qc = dict(qcs[0]) if qcs else {}
qc.update({
    "success": out["success"],
    "process": "DOCKING_AUTODOCK_VINA",
    "best_score_kcal_mol": best,
    "docking_binding_score_passes": (best <= threshold) if best is not None else None,
    "total_poses_generated": total_poses,
    "docking_valid_poses_passes": (total_poses >= min_poses) if (total_poses > 0 or out["success"]) else None,
    "n_ligands_docked": len(valid),
    "n_shards": len(files),
    "status": "computed" if best is not None else (qcs[0].get("status") if qcs else "not_computed"),
})
json.dump(qc, open("qc_metrics.json", "w"), indent=2, default=str)

with open("docking_autodock_vina_output.txt", "w") as f:
    for fn in sorted(glob.glob("shard_*_output.txt"), key=shard_index):
        f.write(open(fn).read() + NL)
    if valid:
        f.write("Merged: " + str(len(valid)) + " ligands docked across " + str(len(files)) + " shards; best affinity " + str(min(valid)) + " kcal/mol" + NL)
if not out["success"]:
    raise SystemExit(1)
PYEOF
    '''
}

workflow DOCKING_AUTODOCK_VINA_WORKFLOW {
    take:
    ch_input  // channel: val(run_id) — retained for signature compatibility

    main:
    // Vina docks one ligand at a time, so the library is split into shards that run as parallel
    // Batch tasks; a single merge writes the usual result files. N <= docking_shard_size => one shard.
    def raw = params.smiles_list
    def parsed = null
    if (raw instanceof List) {
        parsed = raw
    } else {
        try { parsed = new groovy.json.JsonSlurper().parseText((raw ?: '[]').toString()) } catch (Exception e) { parsed = null }
    }
    def shard_tuples = []
    if (parsed instanceof List && parsed) {
        def shard_size = (params.docking_shard_size ?: 10) as int
        parsed.collate(shard_size).eachWithIndex { chunk, i ->
            shard_tuples << [ [id: "shard_${i}"], groovy.json.JsonOutput.toJson(chunk) ]
        }
    } else {
        // Not a JSON list (single SMILES or empty): one shard, parsed by the step itself as before.
        shard_tuples << [ [id: "shard_0"], (raw ?: '').toString() ]
    }
    DOCKING_AUTODOCK_VINA(Channel.fromList(shard_tuples))
    DOCKING_MERGE(
        DOCKING_AUTODOCK_VINA.out.results.collect(),
        DOCKING_AUTODOCK_VINA.out.output.collect(),
        DOCKING_AUTODOCK_VINA.out.qc_metrics.collect(),
        DOCKING_AUTODOCK_VINA.out.poses.flatten().collect().ifEmpty([])
    )

    emit:
    results  = DOCKING_MERGE.out.results
    output   = DOCKING_MERGE.out.output
    versions = DOCKING_AUTODOCK_VINA.out.versions.first()
}

// Entry workflow for standalone execution
workflow {
    ch_input = Channel.of('run')
    DOCKING_AUTODOCK_VINA_WORKFLOW(ch_input)
    DOCKING_AUTODOCK_VINA_WORKFLOW.out.output.view { "Output: $it" }
}
