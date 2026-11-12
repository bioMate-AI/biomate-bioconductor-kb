"""Near-miss routing guards: the three classes reproduced live on dev 2026-11-11.

1. FORMAT near-miss — "Design nanobody candidates against this epitope." (6Z43.pdb + candidate
   FASTA + CDR constraints) produced a `bispecific_antibody_design` card (panel format
   "nanobody_fusion", target indication "oncology"). A bispecific pipeline builds a two-arm
   construct against TWO targets; the request has one epitope and a single-domain format. The
   confusion is lexical: the bispecific description lists every format it can emit, including
   "nanobody fusion", so it matches a request for any one of them.
2. PLUMBING in the retrieval text — the same request scored "Run Audit Export" into the top 5,
   because the chat composer's "[Uploaded datasets: … s3://biomate-nextflow-work/uploads/…]" block
   was tokenised into the FTS query.
3. OPERATION near-miss on processed data — "Quantify differential protein abundance between my two
   groups." with a MaxQuant proteinGroups.txt still routed live to the Chemoproteomics Pulldown
   enrichment-QC workflow: the operation-phrase bonus added in §4.2 (+5 +3) left a margin of ~1.6
   points, less than the Pass-0 LLM re-rank (up to +3.0) plus the dense bonus can hand back.

Rows are the real catalog texts (galaxy_ai_tools.db ids 12911, 12856, 13106, 10804). No database
is needed: the rows are scored directly with _calculate_score on identical search signals.

Run:
    cd backend && PYTHONPATH=lib pytest lib/galaxy/ai/tests/test_near_miss_routing.py -v
"""
import sys
from pathlib import Path

_AI_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_AI_ROOT))
sys.path.insert(0, str(_AI_ROOT.parent.parent.parent))  # backend/lib/

import pytest

from unified_workflow_search import (
    UnifiedWorkflowSearch,
    biologic_format_conflict,
    strip_plumbing_blocks,
)

NANOBODY_QUERY = (
    "Design nanobody candidates against this epitope.\n"
    "[Attached files: 6Z43.pdb, 6Z43.fasta, 1HZH.fasta, nanobody_candidates.fasta, "
    "nanobody_constraints.json]\n"
    "[Prepared inputs: Use experimental H11-D4 nanobody-SARS-CoV-2 spike complex 6Z43. Target is "
    "spike RBD; epitope is the spike residues within 5 A of nanobody chain X. Preserve the supplied "
    "CDR sequence constraints; the human IgG b12 framework source is 1HZH.fasta.]"
)

BISPECIFIC = dict(
    name="bispecific_antibody_design",
    description=("Bispecific antibody (BsAb) design pipeline supporting BiTE, CrossMab, DART, "
                 "DVD-Ig, Knob-into-Hole, and nanobody fusion formats. CDR grafting, linker "
                 "optimization, Rosetta interface scoring, developability."),
    tools=[], tags=["bispecific", "antibody", "BsAb", "BiTE", "CDR design", "antibody engineering"],
    source="biomate-ai-tools", workflow_domain="drug_discovery",
    input_kinds=frozenset({"fasta"}), is_subworkflow=False, real_exec_status=None,
)
SCFV_DESIGN = dict(
    name="scfv_antibody_design",
    description=("AI-driven scFv intrabody design using ProteinMPNN + AlphaFold2. Converts "
                 "conventional antibodies to functional single-chain Fv intrabodies. Input: "
                 "antibody PDB. Output: designed scFv sequences (FASTA) + predicted structures."),
    tools=[], tags=["scFv", "antibody design", "ProteinMPNN", "AlphaFold2", "CDR"],
    source="biomate-ai-tools", workflow_domain="drug_discovery",
    input_kinds=frozenset({"structure"}), is_subworkflow=False, real_exec_status=None,
)


def _score(search, query, row, fts_score, user_input_kinds):
    return search._calculate_score(
        query, row["name"], row["description"], row["tools"], row["tags"], row["source"],
        row["workflow_domain"], fts_score, preferred_domains=["drug_discovery"],
        penalized_domains=[], input_types=None, input_kinds=row["input_kinds"],
        user_input_kinds=user_input_kinds, is_subworkflow=row["is_subworkflow"],
        real_exec_status=row["real_exec_status"])


# ── 1. Therapeutic-format conflict ───────────────────────────────────────────────────────────────

@pytest.mark.parametrize("query,name,conflict", [
    # the live defect: single-epitope nanobody request vs a bispecific pipeline
    (NANOBODY_QUERY, "bispecific_antibody_design", True),
    ("Design nanobody candidates against this epitope.", "Bispecific Antibody Design", True),
    ("humanise this nanobody and keep affinity", "bispecific_format_triage", True),
    ("设计针对该表位的纳米抗体候选", "bispecific_antibody_design", True),
    ("design an scFv against this antigen", "bispecific_antibody_design", True),
    # the reverse: a bispecific request must not land on a single-format workflow
    ("Engineer a CrossMab bispecific antibody for HER2xHER3", "scfv_antibody_design", True),
    # a request that names BOTH sides is not on one side — the bispecific pipeline is right
    ("Design a nanobody-nanobody bispecific fusion targeting albumin", "bispecific_antibody_design", False),
    ("Design a nanobody-nanobody bispecific fusion targeting albumin", "scfv_antibody_design", False),
    # same family → no conflict
    (NANOBODY_QUERY, "scfv_antibody_design", False),
    (NANOBODY_QUERY, "Antibody Antigen Complex", False),
    # workflows that declare no format are never penalised here
    (NANOBODY_QUERY, "antibody_developability", False),
    (NANOBODY_QUERY, "boltz", False),
    # no format named in the request at all
    ("run nf-core/rnaseq on my FASTQs", "bispecific_antibody_design", False),
])
def test_biologic_format_conflict(query, name, conflict):
    assert biologic_format_conflict(query, name) is conflict


def test_nanobody_request_ranks_the_design_workflow_above_the_bispecific_pipeline(tmp_path):
    search = UnifiedWorkflowSearch(db_path=tmp_path / "empty.db")
    # Live bm25 for this request against the catalog FTS index: the bispecific row matches the
    # request's words BETTER (its description lists the nanobody format), which is what made it win.
    bispecific = _score(search, NANOBODY_QUERY, BISPECIFIC, -47.25, ["structure", "fasta"])
    scfv = _score(search, NANOBODY_QUERY, SCFV_DESIGN, -39.15, ["structure", "fasta"])
    assert scfv > bispecific, (scfv, bispecific)


# ── 2. Plumbing blocks are not part of the request ───────────────────────────────────────────────

def test_strip_plumbing_blocks_removes_upload_wiring_and_keeps_the_request():
    text = ("Design nanobody candidates against this epitope.\n"
            "[Attached files: 6Z43.pdb, nanobody_candidates.fasta]\n"
            "[Uploaded datasets: 6Z43.pdb: dataset_id=772f1ebf-bdc8-4f6d-8bbc-3d45d27e32f2, "
            "galaxy_dataset_id=61612e311c53402a, s3_uri=s3://biomate-nextflow-work/uploads/"
            "772f1ebf/6Z43.pdb]\n[Inline parameters:\nfile_path: s3://biomate-nextflow-work/x]\n"
            "[Prepared inputs: Target is spike RBD.]")
    out = strip_plumbing_blocks(text)
    assert "Design nanobody candidates against this epitope." in out
    assert "[Attached files: 6Z43.pdb, nanobody_candidates.fasta]" in out   # filenames carry signal
    assert "Target is spike RBD." in out                                    # prepared context kept
    for noise in ("s3://", "dataset_id", "galaxy_dataset_id", "Inline parameters", "uploads"):
        assert noise not in out, noise


def test_strip_plumbing_blocks_is_a_no_op_for_ordinary_text():
    for text in ("run nf-core/rnaseq on my FASTQs", "", "[Attached files: a.csv]"):
        assert strip_plumbing_blocks(text) == text


# ── 3. Operation the workflow cannot perform (processed data only) ───────────────────────────────

PULLDOWN = dict(
    name="Chemoproteomics Pulldown",
    description=("proteomics/chemoproteomics_pulldown Chemoproteomics affinity enrichment "
                 "(pulldown) QC. Accepts a MaxQuant proteinGroups.txt from a bead-pulldown "
                 "experiment and computes per-protein enrichment ratios."),
    tools=[], tags=["proteomics", "biomni", "nextflow", "chemoproteomics_pulldown"],
    source="biomni_nextflow", workflow_domain="proteomics",
    input_kinds=frozenset({"protein_table"}), is_subworkflow=False, real_exec_status=None,
)
DEQMS_LFQ = dict(
    name="deqms_maxquant_lfq",
    description=("Perform differential protein expression analysis using MaxQuant label-free "
                 "quantification (LFQ) output."),
    tools=[], tags=["deqms", "maxquant", "lfq"],
    source="bioconductor", workflow_domain="proteomics",
    input_kinds=frozenset({"protein_table"}), is_subworkflow=True, real_exec_status="fixture_failed",
)
DE_QUERY = ("Quantify differential protein abundance between my two groups.\n"
            "[Attached files: proteinGroups.txt, proteomics_design.csv]\n"
            "[Prepared inputs: Use the real LFQ-Analyst MaxQuant proteinGroups.txt. Compare H "
            "versus L groups with five samples each. Filter contaminants/reverse hits and report "
            "missingness and batch/sample QC.]")


def test_de_request_on_a_processed_table_clears_the_qc_workflow_by_more_than_a_rerank(tmp_path):
    search = UnifiedWorkflowSearch(db_path=tmp_path / "empty.db")
    de = _score(search, DE_QUERY, DEQMS_LFQ, -41.62, ["protein_table"])
    qc = _score(search, DE_QUERY, PULLDOWN, -46.12, ["protein_table"])
    # Pass-0 gives the top-ranked workflow +3.0 and the dense bonus up to +0.5: the margin has to
    # survive both, which the +5/+3 phrase bonus alone did not (live, 2026-11-11).
    assert de - qc > 3.5, (de, qc)


def test_raw_data_request_keeps_its_pipelines(tmp_path):
    """The guard is gated on a KNOWN, PROCESSED data shape: a user with FASTQs asking for
    differential expression must keep nf-core/rnaseq, which does the alignment+quantification the
    operation needs first."""
    search = UnifiedWorkflowSearch(db_path=tmp_path / "empty.db")
    rnaseq = dict(
        name="nf-core/rnaseq",
        description="RNA sequencing analysis pipeline: alignment, quantification and QC.",
        tools=[], tags=["rnaseq"], source="nfcore", workflow_domain="transcriptomics",
        input_kinds=frozenset({"fastq"}), is_subworkflow=False, real_exec_status="ok",
    )
    q = "Find the differentially expressed genes in my FASTQ reads"
    with_shape = _score(search, q, rnaseq, -30.0, ["fastq"])
    no_shape = _score(search, q, rnaseq, -30.0, None)
    assert with_shape >= no_shape, (with_shape, no_shape)


@pytest.mark.parametrize("row,performs", [
    (DEQMS_LFQ, True),
    (PULLDOWN, False),
    (dict(name="msqrob2", description="Robust statistical inference for quantitative LFQ proteomics.",
          tools=[], tags=[]), True),                       # named after a differential tool
    (dict(name="msquality", description="Quality metrics for mass spectrometry runs.",
          tools=[], tags=[]), False),
])
def test_performs_differential_test_reads_the_workflows_own_text(row, performs):
    from unified_workflow_search import canonicalize_operation_phrases
    hay = " " + canonicalize_operation_phrases(
        f"{row['name']} {row['description']}".lower().replace("-", " ")) + " "
    assert UnifiedWorkflowSearch._performs_differential_test(
        hay, row["tools"], [t.lower() for t in row["tags"]]) is performs
