"""Execute the canonical workflow's exact Python body, not a duplicate algorithm.

These local scientific contracts do not substitute for a real dev Nextflow run.
"""
import csv
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / 'backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/calculate_physicochemical_properties/main.nf'


class PhysicochemicalWorkflow(unittest.TestCase):
    def run_body(self, smiles):
        source = WORKFLOW.read_text()
        bodies = re.findall(r"python3 << 'PYEOF'\n(.*?)^PYEOF\s*$", source, re.M | re.S)
        self.assertEqual(len(bodies), 1)
        with tempfile.TemporaryDirectory(prefix='biomate-properties-contract-') as folder:
            result = subprocess.run([sys.executable, '-c', bodies[0]], cwd=folder,
                                    env={**os.environ, 'PARAM_SMILES_STRING': smiles},
                                    capture_output=True, text=True, timeout=30)
            output = json.loads((Path(folder) / 'calculate_physicochemical_properties_results.json').read_text())
            csv_path = Path(folder) / 'physicochemical_properties.csv'
            with csv_path.open(newline='') if csv_path.exists() else open(os.devnull) as handle:
                rows = list(csv.reader(handle))
            return result, output, rows

    def test_ethanol_identity_and_reference_descriptors(self):
        result, output, rows = self.run_body('CCO')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIs(output['success'], True)
        self.assertEqual(rows[0], ['Property', 'Value'])
        values = dict(rows[1:])
        self.assertEqual(values['SMILES'], 'CCO')
        self.assertAlmostEqual(float(values['Molecular Weight']), 46.07, places=2)
        self.assertEqual(int(values['Heavy Atoms']), 3)
        self.assertEqual(int(values['H-Bond Donors']), 1)
        self.assertEqual(int(values['H-Bond Acceptors']), 1)
        self.assertEqual(int(values['Ring Count']), 0)
        self.assertGreater(float(values['QED']), 0)
        self.assertLess(float(values['QED']), 1)
        self.assertAlmostEqual(float(values['Molar Refractivity']), 12.76, places=2)

    def test_ionizable_compound_does_not_get_fabricated_logd_or_mislabeled_score(self):
        result, output, rows = self.run_body('CC(=O)O')
        self.assertEqual(result.returncode, 0, result.stderr)
        values = dict(rows[1:])
        self.assertNotIn('Estimated logD7.4', values)
        self.assertNotIn('Drug-likeness Score', values)
        self.assertNotIn('Estimated Acidic Groups', values)
        self.assertIn('pKa were not calculated', output['result'])

    def test_invalid_missing_and_empty_molecules_fail_the_real_wrapper(self):
        for smiles in ('not-a-molecule', '', 'null'):
            with self.subTest(smiles=smiles):
                result, output, rows = self.run_body(smiles)
                self.assertNotEqual(result.returncode, 0)
                self.assertIs(output['success'], False)
                self.assertTrue(output.get('error', '').startswith('ERROR:'))
                self.assertEqual(rows, [])

    def test_scientific_csv_is_declared_and_exposed(self):
        source = WORKFLOW.read_text()
        self.assertIn('path("physicochemical_properties.csv"), emit: properties', source)
        self.assertIn('properties = CALCULATE_PHYSICOCHEMICAL_PROPERTIES.out.properties', source)


if __name__ == '__main__':
    unittest.main(verbosity=2)
