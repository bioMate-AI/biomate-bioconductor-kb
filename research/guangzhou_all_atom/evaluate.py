"""Chemical identity audit for peptide and small-molecule generation attempts.

Input JSON contains an `attempts` list. Every attempted sample must be retained,
including failures (smiles=null). This is a graph audit, not a binding/3D assay.
"""
import argparse
import hashlib
import json
from pathlib import Path

from rdkit import Chem, DataStructs, rdBase
from rdkit.Chem import rdFingerprintGenerator


def identity(smiles):
    if not isinstance(smiles, str) or not smiles.strip():
        return None
    mol = Chem.MolFromSmiles(smiles)
    if mol is None or mol.GetNumAtoms() == 0:
        return None
    # Atom maps label provenance, not chemical identity. Preserve stereochemistry,
    # charge, isotopes, covalent crosslinks, and disconnected components.
    for atom in mol.GetAtoms():
        atom.SetAtomMapNum(0)
    mol = Chem.RemoveHs(mol)
    return mol, Chem.MolToSmiles(mol, canonical=True, isomericSmiles=True)


def audit(payload, training_smiles=None):
    attempts = payload.get('attempts')
    if not isinstance(attempts, list) or not attempts:
        raise ValueError('attempts must be a non-empty list including failed samples')
    ids = [r.get('sample_id') for r in attempts if isinstance(r, dict)]
    if (len(ids) != len(attempts) or any(not isinstance(i, str) or not i for i in ids)
            or len(set(ids)) != len(ids)):
        raise ValueError('Each attempt requires a unique non-empty string sample_id')
    if training_smiles is not None and not training_smiles:
        raise ValueError('An empty training reference cannot establish novelty')
    fingerprint = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048,
                                                            includeChirality=True)
    reference = {}
    for s in training_smiles or []:
        parsed = identity(s)
        if parsed is None:
            raise ValueError('Training reference contains an invalid molecule')
        mol, key = parsed
        reference[key] = fingerprint.GetFingerprint(mol)
    rows, unique = [], set()
    valid = connected = stereospecified = unseen = 0
    for record in attempts:
        parsed = identity(record.get('smiles'))
        row = {'sample_id': record['sample_id'], 'chemical_valid': parsed is not None}
        if parsed is None:
            row['failure_reason'] = record.get('failure_reason', 'missing_or_invalid_smiles')
            rows.append(row)
            continue
        mol, key = parsed
        valid += 1
        unique.add(key)
        n_fragments = len(Chem.GetMolFrags(mol))
        connected += n_fragments == 1
        unassigned = sum(info.specified == Chem.StereoSpecified.Unspecified
                         for info in Chem.FindPotentialStereo(mol))
        stereospecified += unassigned == 0
        row.update(canonical_isomeric_smiles=key, n_fragments=n_fragments,
                   unspecified_stereo_elements=unassigned)
        if training_smiles is not None:
            is_unseen = key not in reference
            unseen += is_unseen
            row.update(exact_training_match=not is_unseen,
                       nearest_training_tanimoto=max(DataStructs.BulkTanimotoSimilarity(
                           fingerprint.GetFingerprint(mol), list(reference.values()))))
        else:
            row.update(exact_training_match=None, nearest_training_tanimoto=None)
        rows.append(row)
    n = len(attempts)
    return {
        'schema_version': 1,
        'rdkit_version': rdBase.rdkitVersion,
        'n_attempted': n,
        'n_valid': valid,
        'n_unique_valid': len(unique),
        'chemical_validity_per_attempt': valid / n,
        'connected_valid_per_attempt': connected / n,
        'fully_specified_stereo_valid_per_attempt': stereospecified / n,
        'unique_valid_per_attempt': len(unique) / n,
        'uniqueness_among_valid': len(unique) / valid if valid else None,
        'exact_unseen_valid_per_attempt': unseen / n if training_smiles is not None else None,
        'training_reference_unique_count': len(reference) if training_smiles is not None else None,
        'identity_policy': 'isomeric_graph; strip_atom_maps_and_removable_H; preserve_charge_isotope_fragments',
        'limits': ['No tautomer or salt-parent normalization',
                   'Exact graph novelty is not scaffold novelty or freedom to operate',
                   'Fingerprint similarity is not calibrated predictive uncertainty',
                   'No 3D geometry, peptide topology specification, potency, synthesis or safety evaluation',
                   'No proof that supplied attempts or training reference are complete'],
        'samples': rows,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('--training-smiles', type=Path,
                        help='One SMILES per nonblank line; no header')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    raw = args.input.read_bytes()
    train_raw = args.training_smiles.read_bytes() if args.training_smiles else None
    training = [s.strip() for s in train_raw.decode().splitlines() if s.strip()] if train_raw is not None else None
    report = audit(json.loads(raw), training)
    report['input_sha256'] = hashlib.sha256(raw).hexdigest()
    report['training_sha256'] = hashlib.sha256(train_raw).hexdigest() if train_raw is not None else None
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
