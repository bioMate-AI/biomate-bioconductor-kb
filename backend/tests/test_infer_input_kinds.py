"""data_perception.infer_input_kinds — map the user's ACTUALLY-attached datasets to the closed
input_kinds vocabulary, so workflow routing (step 8a) checks compatibility against the real data
shape instead of guessing from prose. The principled processed-vs-raw fix (docs 2026-11-09): a
processed abundance TABLE must not route to a raw LC-MS pipeline.

Run: cd backend && PYTHONPATH=lib pytest tests/test_infer_input_kinds.py -v --import-mode=importlib
"""
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.data_perception import (  # noqa: E402
    infer_input_kinds,
    has_primary_input_kind,
    resolve_effective_input_kinds,
)
from galaxy.ai.chain_composer.input_kinds_classifier import INPUT_KINDS  # noqa: E402


def test_raw_extensions_map_to_raw_kinds():
    assert infer_input_kinds([{"name": "s_R1.fastq.gz"}, {"name": "s_R2.fastq.gz"}]) == ["fastq"]
    assert infer_input_kinds([{"s3_uri": "s3://b/run.raw"}, {"name": "r2.mzML"}]) == ["raw_spectra"]
    assert infer_input_kinds([{"file_path": "/d/calls.vcf"}]) == ["vcf"]
    assert infer_input_kinds([{"name": "movie_0001.mrc"}]) == ["raw_images"]
    assert infer_input_kinds([{"name": "adata.h5ad"}]) == ["h5ad"]
    assert infer_input_kinds([{"name": "run.idat"}]) == ["idat"]


def test_processed_tables_map_to_processed_kinds():
    # A proteomics protein table → protein_table (+ the canonical counts_matrix for integration).
    assert set(infer_input_kinds([{"name": "proteinGroups.txt"}])) == {"protein_table", "counts_matrix"}
    assert set(infer_input_kinds([{"name": "protein_abundance_matrix.tsv"}])) == {"protein_table", "counts_matrix"}
    # Generic abundance / DE / counts tables → counts_matrix (omics-agnostic processed matrix).
    assert infer_input_kinds([{"name": "abundance_matrix.csv"}]) == ["counts_matrix"]
    assert infer_input_kinds([{"name": "deseq2_de_results.csv"}]) == ["counts_matrix"]
    # Modality-specific tables add their precise kind.
    assert set(infer_input_kinds([{"name": "metabolite_feature_table.tsv"}])) == {"metabolite_table", "counts_matrix"}
    assert infer_input_kinds([{"name": "EWAS_beta_values.csv"}]) == ["beta_values"]


def test_design_sheet_and_cueless_remote_table_yield_nothing():
    # A sample/design sheet is NOT a processed data matrix — it must never demote a raw pipeline.
    assert infer_input_kinds([{"name": "samplesheet.csv"}]) == []
    assert infer_input_kinds([{"name": "sample_metadata.tsv"}]) == []
    # A cue-less table with no readable local file: do not guess a processed kind (fall back to prose).
    assert infer_input_kinds([{"s3_uri": "s3://b/data.csv"}]) == []


def test_mixed_raw_plus_sheet_keeps_only_raw_kind():
    # FASTQ + its samplesheet → {fastq}; the sheet contributes nothing, so a raw pipeline stays
    # compatible (mixed raw+processed would wrongly look like a conflict otherwise).
    assert infer_input_kinds([{"name": "reads.fastq.gz"}, {"name": "samplesheet.csv"}]) == ["fastq"]


def test_cueless_local_numeric_matrix_is_counts_matrix():
    d = tempfile.mkdtemp()
    p = os.path.join(d, "data.csv")  # no filename cue, but the content IS a numeric matrix
    with open(p, "w") as f:
        f.write("gene,s1,s2,s3\nA,10,20,30\nB,5,6,7\nC,1,2,3\n")
    assert infer_input_kinds([{"file_path": p}]) == ["counts_matrix"]
    q = os.path.join(d, "notes.csv")  # free-text table → not a matrix → no kind
    with open(q, "w") as f:
        f.write("note,author\nhello,me\nbye,you\n")
    assert infer_input_kinds([{"file_path": q}]) == []


def test_only_closed_vocabulary_is_emitted():
    kinds = infer_input_kinds([
        {"name": "x.fastq.gz"}, {"name": "run.raw"}, {"name": "proteinGroups.txt"},
        {"name": "adata.h5ad"}, {"name": "calls.vcf"}, {"name": "movie.mrc"},
    ])
    assert set(kinds) <= set(INPUT_KINDS)


def test_robust_to_empty_and_malformed_input():
    assert infer_input_kinds(None) == []
    assert infer_input_kinds([]) == []
    assert infer_input_kinds([{}, {"name": ""}, "not-a-dict-without-ext", 123]) == []
    # a bare path string is accepted
    assert infer_input_kinds(["/x/run.mzML"]) == ["raw_spectra"]


# ── PRIMARY vs AUXILIARY / reference inputs (committee review 2026-11-09, finding 3) ──
# A reference/auxiliary file (reference genome, gene model, ligand library, structure) must not, on
# its own, override a prose-described PRIMARY shape; a raw file or a processed table must.

def test_has_primary_input_kind_classifies_primary_vs_auxiliary():
    # raw instrument output + processed matrices/objects + per-sample results are PRIMARY
    assert has_primary_input_kind(["fastq"]) is True
    assert has_primary_input_kind(["protein_table", "counts_matrix"]) is True
    assert has_primary_input_kind(["vcf"]) is True
    # reference genome / annotation / ligand library / structure are AUXILIARY only
    assert has_primary_input_kind(["fasta"]) is False
    assert has_primary_input_kind(["annotation"]) is False
    assert has_primary_input_kind(["molecules", "structure"]) is False
    assert has_primary_input_kind(["fasta", "annotation"]) is False
    assert has_primary_input_kind([]) is False
    assert has_primary_input_kind(None) is False
    # a raw read alongside a reference is still primary (the reference merely rides along)
    assert has_primary_input_kind(["fastq", "fasta"]) is True


def test_reference_files_infer_only_auxiliary_kinds():
    # .fa → fasta, .gtf → annotation, .sdf → molecules, .pdb → structure — all AUXILIARY.
    assert infer_input_kinds([{"name": "GRCh38.primary_assembly.fa"}]) == ["fasta"]
    assert set(infer_input_kinds([
        {"name": "GRCh38.fa"}, {"name": "gencode.v44.annotation.gtf"}
    ])) == {"fasta", "annotation"}
    assert infer_input_kinds([{"name": "fragment_library.sdf"}]) == ["molecules"]
    assert infer_input_kinds([{"name": "receptor.pdb"}]) == ["structure"]


def test_resolve_merges_auxiliary_but_keeps_prose_primary():
    # Finding 3: prose says RNA-seq FASTQ reads, user also attaches a reference genome + GTF.
    # The auxiliary kinds are MERGED — the prose {fastq} is NOT discarded.
    datasets = [{"name": "GRCh38.fa"}, {"name": "gencode.v44.annotation.gtf"}]
    eff = resolve_effective_input_kinds(["fastq"], datasets)
    assert "fastq" in eff                       # prose primary survives
    assert set(eff) == {"fastq", "fasta", "annotation"}


def test_resolve_primary_attachment_overrides_prose():
    # A processed abundance TABLE is PRIMARY → it OVERRIDES a (wrong) prose raw guess (McGill).
    eff = resolve_effective_input_kinds(["raw_spectra"], [{"name": "proteinGroups.txt"}])
    assert set(eff) == {"protein_table", "counts_matrix"}   # raw_spectra discarded
    # Raw files attached + prose → raw primary overrides too.
    assert resolve_effective_input_kinds(["counts_matrix"], [{"name": "reads.fastq.gz"}]) == ["fastq"]


def test_resolve_design_sheet_and_nothing_profilable_leave_prose_unchanged():
    # A design/sample sheet infers [] → prose returned unchanged (headline: sheet never demotes raw).
    assert resolve_effective_input_kinds(["fastq"], [{"name": "samplesheet.csv"}]) == ["fastq"]
    # Nothing attached / nothing profilable → prose preserved exactly (None / [] semantics intact).
    assert resolve_effective_input_kinds(None, []) is None
    assert resolve_effective_input_kinds([], None) == []
    assert resolve_effective_input_kinds(["protein_table"], [{"s3_uri": "s3://b/data.csv"}]) == ["protein_table"]
