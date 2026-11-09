#!/usr/bin/env nextflow
/*
 * single_cell/multiome_rna_atac
 *
 * 10x Genomics Chromium Single Cell Multiome ATAC + Gene Expression.
 * Joint profiling of chromatin accessibility (ATAC-seq) and gene expression
 * (RNA-seq) from the same single cells.
 *
 * Instrument: 10x Chromium Next GEM Single Cell Multiome ATAC + Gene Expression
 *
 * Steps:
 *   1. RNA: Cell Ranger Arc → gene × cell count matrix
 *   2. ATAC: Cell Ranger Arc → peak × cell count matrix
 *   3. Dimensionality reduction:
 *      - RNA: PCA → Harmony batch correction → RNA UMAP
 *      - ATAC: TF-IDF → SVD (LSI) → ATAC UMAP
 *   4. WNN joint embedding → multimodal UMAP
 *   5. Peak-to-gene linkage (correlation of peak accessibility to gene expression)
 *   6. Transcription factor activity (chromVAR motif analysis)
 *   7. Cell type annotation with joint RNA + ATAC markers
 *
 * Key outputs:
 *   - qc_summary.json          : RNA + ATAC quality metrics
 *   - peak_gene_links.csv      : Significant peak-to-gene correlations
 *   - tf_activity.csv          : TF motif activity per cluster
 *   - cell_annotations.csv     : Cell type per barcode
 *   - multiome_report.txt      : Human-readable summary
 *
 * References:
 *   - 10x Genomics Cell Ranger ARC 2.0 (2022)
 *   - Stuart et al. 2021 Nature Methods (Signac for scATAC-seq)
 *   - Hao et al. 2021 Cell (Seurat v4 WNN)
 *   - Schep et al. 2017 Nature Methods (chromVAR)
 *
 * ─────────────────────────────────────────────────────────────────────────
 * IMPLEMENTATION STATUS: NOT YET IMPLEMENTED — fails loudly (see below).
 *
 * This process previously EMITTED FABRICATED OUTPUT: it seeded Python's
 * `random` module and generated all QC metrics, peak–gene links, TF-activity
 * scores and per-barcode annotations with `random.gauss/uniform/randint`,
 * then reported `status: completed`. It performed NO real WNN / joint
 * RNA+ATAC integration and consumed NO input data (the process input was
 * `val(meta)` only — there was no RNA count matrix, no ATAC fragments file,
 * and no Cell Ranger ARC output plumbed in). Fake success is worse than an
 * honest failure, so the fabrication has been removed.
 *
 * A real implementation is blocked on two hard gaps:
 *   1. CONTAINER — the declared image `biomate/workflow-tools` (built from
 *      backend/docker/workflow-tools/Dockerfile) is a cheminformatics /
 *      pharmacology + basic sci-python stack (numpy, scipy, pandas,
 *      scikit-learn, biopython, rdkit, ViennaRNA, Vina, statsmodels). It
 *      contains NONE of the multiome integration stack required for real
 *      WNN / joint embedding: no scanpy/anndata, no muon/muData, no
 *      episcanpy, no Seurat/Signac (R), no ArchR, no chromVAR, no Cell
 *      Ranger ARC.
 *   2. INPUT DATA — there is no channel carrying real RNA counts, ATAC
 *      fragments, or a Cell Ranger ARC filtered matrix into this process.
 *
 * To implement for real:
 *   - Switch `container` to an image with muon + scanpy + episcanpy (Python)
 *     or Seurat + Signac (R) or ArchR (R), plus chromVAR for TF activity.
 *   - Add proper inputs (RNA h5/matrix, ATAC fragments.tsv.gz + peaks) and
 *     a real load → QC → per-modality embedding (PCA / TF-IDF+LSI) →
 *     WNN joint neighbours → Leiden clusters → joint UMAP → real
 *     peak-to-gene linkage and chromVAR TF activity.
 *   - Emit ONLY values computed from the input data. No `random.*`.
 * ─────────────────────────────────────────────────────────────────────────
 */

nextflow.enable.dsl = 2

params.outdir               = './results'
params.rna_atac_fastq_dir   = 'null'       // Cell Ranger ARC input
params.genome               = 'GRCh38'
params.expected_cells        = '5000'
params.min_rna_counts        = '500'
params.min_atac_fragments    = '1000'      // minimum ATAC fragments per cell
params.tss_enrichment_min    = '4.0'       // minimum TSS enrichment score
params.peak_calling          = 'true'      // MACS2 peak calling
params.link_peaks_to_genes   = 'true'      // compute peak-gene correlations
params.tf_activity           = 'true'      // chromVAR TF motif analysis

process MULTIOME_RNA_ATAC {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' \
        : 'biomate/workflow-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("qc_summary.json"),       emit: qc
    tuple val(meta), path("peak_gene_links.csv"),   emit: peak_gene
    tuple val(meta), path("tf_activity.csv"),       emit: tf
    tuple val(meta), path("cell_annotations.csv"),  emit: annotations
    tuple val(meta), path("multiome_report.txt"),   emit: report
    path "versions.yml",                            emit: versions

    script:
    """
    # ── HONEST FAILURE ──────────────────────────────────────────────────────
    # multiome RNA+ATAC joint integration is NOT yet implemented.
    #
    # The previous version of this process fabricated all QC metrics,
    # peak-gene links, TF-activity scores and cell annotations with Python's
    # `random` module and reported success. That fake output has been removed.
    # There is no real WNN / joint-embedding integration stack in the declared
    # container (workflow-tools: no scanpy/anndata/muon/episcanpy/Signac/ArchR/
    # chromVAR) and no real RNA/ATAC input data plumbed into this process, so a
    # genuine result cannot be produced here. Failing loudly (non-zero exit) is
    # correct; emitting fabricated "successful" output is not.
    #
    # See the header comment of this file for what a real implementation needs.
    # ─────────────────────────────────────────────────────────────────────────
    echo "ERROR: single_cell/multiome_rna_atac — joint RNA+ATAC (WNN) integration not yet implemented." >&2
    echo "       The declared container (workflow-tools) lacks the multiome integration stack" >&2
    echo "       (scanpy/anndata, muon/muData, episcanpy, Seurat/Signac, ArchR, chromVAR) and" >&2
    echo "       no real RNA/ATAC input data is provided to this process." >&2
    echo "       Refusing to emit fabricated output. See main.nf header for implementation notes." >&2
    exit 1
    """
}

workflow MULTIOME_WORKFLOW {
    take: meta_ch
    main: MULTIOME_RNA_ATAC(meta_ch)
    emit:
        qc          = MULTIOME_RNA_ATAC.out.qc
        peak_gene   = MULTIOME_RNA_ATAC.out.peak_gene
        tf          = MULTIOME_RNA_ATAC.out.tf
        annotations = MULTIOME_RNA_ATAC.out.annotations
        report      = MULTIOME_RNA_ATAC.out.report
}

workflow { meta = [id:'multiome_run']; Channel.value(meta) | MULTIOME_WORKFLOW }
