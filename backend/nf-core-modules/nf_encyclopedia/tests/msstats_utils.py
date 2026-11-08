from __future__ import annotations

import numpy as np
import pandas as pd


def _msstats_input(tmp_path, peps: list[str], prots, stems, conditions):
    """
    Generates msstats input files from random data
    """
    rng = np.random.default_rng(42)
    quants = rng.normal(0, 1, size=(len(peps), len(stems))) ** 2 * 1e5

    mzml = [s + ".mzML" for s in stems]
    raw = ["s3://stuff/blah/" + s + ".raw" for s in stems]

    # The peptides.txt file:
    quant_df = pd.DataFrame(quants, columns=mzml)
    meta_df = pd.DataFrame({"Peptide": peps, "Protein": prots, "numFragments": 1})

    peptide_df = pd.concat([quant_df, meta_df], axis=1)
    peptide_file = tmp_path / "encyclopedia.peptides.txt"
    peptide_df.to_csv(peptide_file, sep="\t", index=False)

    protein_df = pd.DataFrame({"Protein": list(set(prots))})
    protein_file = tmp_path / "encyclopedia.proteins.txt"
    protein_df.to_csv(protein_file, sep="\t", index=False)

    # The annotation file:
    input_df = pd.DataFrame({"file": raw, "chrlib": False, "group": "default"})
    input_df["condition"] = conditions
    input_file = tmp_path / "input.csv"
    input_df.to_csv(input_file, index=False)

    # contrasts:
    uniq_conditions = sorted(list(set(conditions)))
    sample_contrast = [0 for _ in uniq_conditions]
    sample_contrast[0] = -1
    sample_contrast[1] = 1
    sample_contrast = tuple(sample_contrast)
    contrast_df = pd.DataFrame(
        [sample_contrast], columns=uniq_conditions, index=["test"]
    )
    contrast_file = tmp_path / "contrasts.csv"
    contrast_df.to_csv(contrast_file)

    return peptide_file, protein_file, input_file, contrast_file
