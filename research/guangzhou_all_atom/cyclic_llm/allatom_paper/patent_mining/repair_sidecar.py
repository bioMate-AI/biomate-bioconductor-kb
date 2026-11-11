"""Versioned re-conversion of immutable K4 records; run on approved EC2 only.

No mining, source reconstruction, activity joining or prior admission is done.
Original rows are retained unchanged; the output must be a new exclusive path.
"""
import argparse
import hashlib
import json
from pathlib import Path

from rdkit import Chem
import seq2smiles


def sha256_file(path):
    value=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):
            value.update(chunk)
    return value.hexdigest()


def repair_record(original):
    if not isinstance(original,dict):
        raise ValueError('original K4 record must be a JSON object')
    candidate=dict(schema='k4-repair-sidecar-v1',converter_version=seq2smiles.CONVERTER_VERSION,
        reconstruction_status='unresolved',graph_parse_ok=False,source_structure_fidelity='unreviewed',
        activity_linkage_status='unreviewed',method_prior_eligible=False)
    text=original.get('structure_string') or ''
    fmt=original.get('structure_format')
    try:
        if fmt=='sequence' and text:
            smiles,_,n=seq2smiles.to_smiles(text)
            candidate['n_residues']=n
        elif fmt=='SMILES' and text:
            smiles=text
        else:
            candidate['unresolved_reason']='source lookup required for '+str(fmt)
            return dict(original=original,repair=candidate)
        molecule=Chem.MolFromSmiles(smiles)
        if molecule is None:
            raise seq2smiles.ConvertError('candidate graph does not parse')
        candidate.update(reconstruction_status='reconstructed_unreviewed',graph_parse_ok=True,
            canonical_smiles=Chem.MolToSmiles(molecule,isomericSmiles=True),
            unassigned_tetrahedral_centres=sum(label=='?' for _,label in
                Chem.FindMolChiralCenters(molecule,includeUnassigned=True)),
            has_graph_ring=molecule.GetRingInfo().NumRings()>0)
    except seq2smiles.ConvertError as error:
        candidate['unresolved_reason']=str(error)
    return dict(original=original,repair=candidate)


def repair_line(raw_line,input_sha256,line_number):
    """Preserve byte-level provenance, including source CRLF line endings."""
    if not isinstance(raw_line,bytes):
        raise TypeError('original line must be bytes')
    original=json.loads(raw_line.decode('utf-8'))
    repaired=repair_record(original)
    repaired.update(input_sha256=input_sha256,input_line=line_number,
        original_record_sha256=hashlib.sha256(raw_line).hexdigest())
    return repaired


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',required=True)
    parser.add_argument('--input-sha256',required=True)
    parser.add_argument('--output',required=True)
    args=parser.parse_args()
    if sha256_file(args.input)!=args.input_sha256:
        raise ValueError('original K4 input hash mismatch')
    # Exclusive creation protects original archives and any earlier repair output.
    with Path(args.output).open('x',encoding='utf-8') as out,Path(args.input).open('rb') as source:
        for line_number,line in enumerate(source,1):
            repaired=repair_line(line,args.input_sha256,line_number)
            out.write(json.dumps(repaired,allow_nan=False)+'\n')


if __name__=='__main__':
    main()
