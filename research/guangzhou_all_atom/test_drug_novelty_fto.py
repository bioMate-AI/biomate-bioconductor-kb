"""Self-test for drug_novelty_fto: peptide->SMILES macrocyclization, axes, verdict logic."""
import drug_novelty_fto as nf


def test_peptide_to_smiles_cyclic_mw():
    # A few sequences spanning charged/aromatic/proline/glycine residues.
    for seq in ["GAYTSKSTGVTF", "GRGRNKYYP", "AAPEVLRKYTSLP", "SSRSSLGHLLG", "KGLRGRSG"]:
        smi, status = nf.peptide_to_smiles(seq, cyclic=True)
        assert smi is not None, (seq, status)
        assert status == "ok_cyclic", (seq, status)  # MW-validated head-to-tail ring
    print("ok: cyclic peptide SMILES built + MW-validated for 5 sequences")


def test_cyclic_vs_linear_differ():
    smi_c, sc = nf.peptide_to_smiles("GAYTSKSTGVTF", cyclic=True)
    smi_l, sl = nf.peptide_to_smiles("GAYTSKSTGVTF", cyclic=False)
    assert smi_c != smi_l and sc == "ok_cyclic" and sl == "ok_linear"
    print("ok: cyclic != linear SMILES")


def test_self_similarity_is_one():
    # A molecule is a perfect match to itself in a one-item library => not novel.
    smi, _ = nf.peptide_to_smiles("KGLRGRSG", cyclic=True)
    qfp = nf._morgan(smi)
    lib = nf.KnownActivesLibrary(fps=[qfp], ids=["self"], smiles=[smi], tags=[{}])
    res = lib.nearest(qfp)
    assert res[0] == 1.0, res
    v = nf.score_candidate("c", seq="KGLRGRSG", library=lib).finalize() if False else \
        nf.score_candidate("c", seq="KGLRGRSG", library=lib)
    assert v.occupied is True and v.verdict == "known_active", (v.occupied, v.verdict)
    print("ok: self-match => occupied/known_active (tanimoto=1.0)")


def test_distinct_scaffold_is_novel():
    # aspirin library vs a peptide query => clearly novel.
    asp = nf._morgan("CC(=O)Oc1ccccc1C(=O)O")
    lib = nf.KnownActivesLibrary(fps=[asp], ids=["aspirin"], smiles=["CC(=O)Oc1ccccc1C(=O)O"], tags=[{}])
    v = nf.score_candidate("c", seq="GRGRNKYYP", library=lib)
    assert v.structure_status == "ok" and v.max_tanimoto < 0.85 and v.verdict == "novel", \
        (v.structure_status, v.max_tanimoto, v.verdict)
    print("ok: distinct scaffold => novel (max_tanimoto=%.3f)" % v.max_tanimoto)


def test_sequence_identity():
    assert nf.sequence_identity("ABCDEF", "ABCDEF") == 1.0
    assert nf.sequence_identity("ABCDEF", "ABCDEX") >= 0.8
    assert nf.sequence_identity("ABCDEF", "ZZZZZZ") == 0.0
    v = nf.score_candidate("c", seq="GRGRNKYYP", ref_seqs=["GRGRNKYYP"], library=None)
    assert v.max_seq_identity == 1.0 and v.occupied is True and v.verdict == "sequence_match"
    print("ok: sequence identity + sequence_match verdict")


def test_fail_open_when_nothing_runs():
    v = nf.score_candidate("c", seq="GRGRNKYYP", library=None)  # no library, no patents, no ref
    assert v.occupied is None and v.verdict == "unknown", (v.occupied, v.verdict)
    print("ok: nothing-ran => occupied=None/unknown (fail-open)")


if __name__ == "__main__":
    test_peptide_to_smiles_cyclic_mw()
    test_cyclic_vs_linear_differ()
    test_self_similarity_is_one()
    test_distinct_scaffold_is_novel()
    test_sequence_identity()
    test_fail_open_when_nothing_runs()
    print("\nALL PASS")
