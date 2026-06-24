#!/usr/bin/env nextflow
/*
 * single_cell/scrnaseq_standard_endtoend
 *
 * End-to-end standard scRNA-seq analysis: raw 10X FASTQ → annotated cell-type
 * h5ad + interactive iSEE app + Methods report. Composes nf-core/scrnaseq
 * (workflow id 12777) as a sub-workflow for alignment, then adds BioMate's own
 * QC + Harmony integration + Leiden + celltypist annotation layer.
 *
 * Pipeline:
 *   1. Validate samplesheet + locate fastq pairs
 *   2. Sub-workflow call: nf-core/scrnaseq (12777) alignment + quantification
 *   3. Per-cell QC + scDblFinder doublet filter
 *   4. Normalize + HVGs + PCA + Harmony batch integration
 *   5. Leiden clustering + UMAP
 *   6. celltypist cell-type annotation
 *   7. Chained downstream: iSEE (id 11653) interactive Shiny app
 *
 * References:
 *   - Korsunsky et al. 2019 Nat Methods (Harmony)
 *   - Germain et al. 2021 F1000Research (scDblFinder)
 *   - Domínguez Conde et al. 2022 Science (celltypist)
 *   - Rue-Albrecht et al. 2018 F1000Research (iSEE)
 *
 * Spec doc: docs/20260616_SC_WORKFLOW_IMPLEMENTATION_REQUIREMENT_3_WORKFLOWS.md
 *           § Spec 1
 */

nextflow.enable.dsl = 2

params.outdir                   = './results'
params.fastq_dir                = null             // 10X paired-end fastq dir (required)
params.samplesheet              = null             // nf-core format CSV (required)
params.reference_genome         = 'GRCh38'         // FASTA path or canonical name
params.gtf_annotation           = 'GENCODE_v44'    // GTF path or canonical name
params.species                  = 'human'          // human | mouse
params.aligner                  = 'starsolo'       // starsolo | cellranger | salmon_alevin
params.min_genes_per_cell       = '200'
params.max_pct_mito             = '20'
params.doublet_score_threshold  = '0.3'
params.n_hvgs                   = '2000'
params.n_pcs                    = '50'
params.harmony_batch_key        = 'sample'         // accepts 'patient' for Merck dataset
params.leiden_resolution        = '0.5'
params.celltypist_model         = 'Immune_All_Low' // Immune_All_High for TME

process SCRNASEQ_STANDARD_ENDTOEND {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/scrnaseq-standard:v1' \
        : 'biomate/scrnaseq-standard:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("annotated.h5ad"),                  emit: annotated
    tuple val(meta), path("celltype_assignments.csv"),        emit: celltypes
    tuple val(meta), path("marker_genes_per_cluster.csv"),    emit: markers
    tuple val(meta), path("qc_metrics.csv"),                  emit: qc
    tuple val(meta), path("methods_report.html"),             emit: report
    tuple val(meta), path("umap_celltypes.png"),              emit: viz
    path "versions.yml",                                       emit: versions

    script:
    """
    # ---------------------------------------------------------------
    # STAGE 1 — Validate samplesheet + locate fastq pairs
    # ---------------------------------------------------------------
    python /opt/biomate/scrnaseq/validate_samplesheet.py \\
        --samplesheet ${params.samplesheet} \\
        --fastq_dir ${params.fastq_dir}

    # ---------------------------------------------------------------
    # STAGE 2 — Sub-workflow call: nf-core/scrnaseq (id 12777)
    # The orchestrator (Galaxy backend) is responsible for invoking
    # subworkflow id 12777 with the inputs prepared above and staging
    # its counts_matrix.h5ad + multiqc_report.html into this work dir.
    # ---------------------------------------------------------------

    # ---------------------------------------------------------------
    # STAGE 3 — Per-cell QC + scDblFinder doublet filter
    # ---------------------------------------------------------------
    Rscript /opt/biomate/scrnaseq/scdblfinder_qc.R \\
        --h5ad counts_matrix.h5ad \\
        --min_genes ${params.min_genes_per_cell} \\
        --max_pct_mito ${params.max_pct_mito} \\
        --doublet_threshold ${params.doublet_score_threshold} \\
        --out cells_passing_qc.h5ad \\
        --qc_table qc_metrics.csv \\
        --qc_plots qc_violin.png,doublet_hist.png

    # ---------------------------------------------------------------
    # STAGE 4 — Normalize + HVGs + PCA + Harmony
    # ---------------------------------------------------------------
    python /opt/biomate/scrnaseq/normalize_harmony.py \\
        --h5ad cells_passing_qc.h5ad \\
        --n_hvgs ${params.n_hvgs} \\
        --n_pcs ${params.n_pcs} \\
        --batch_key ${params.harmony_batch_key} \\
        --out integrated.h5ad \\
        --plots pc_variance.png,harmony_compare.png

    # ---------------------------------------------------------------
    # STAGE 5 — Leiden clustering + UMAP
    # ---------------------------------------------------------------
    python /opt/biomate/scrnaseq/leiden_umap.py \\
        --h5ad integrated.h5ad \\
        --resolution ${params.leiden_resolution} \\
        --out clustered.h5ad \\
        --plots umap_clusters.png,umap_samples.png \\
        --table umap_coords.csv

    # ---------------------------------------------------------------
    # STAGE 6 — celltypist annotation
    # ---------------------------------------------------------------
    python /opt/biomate/scrnaseq/celltypist_annotate.py \\
        --h5ad clustered.h5ad \\
        --model ${params.celltypist_model} \\
        --out annotated.h5ad \\
        --assignments celltype_assignments.csv \\
        --markers marker_genes_per_cluster.csv \\
        --plots umap_celltypes.png,marker_heatmap.png

    # ---------------------------------------------------------------
    # STAGE 7 — Methods Report (HTML)
    # Chained iSEE call (id 11653) handled by the orchestrator after
    # this process emits annotated.h5ad.
    # ---------------------------------------------------------------
    python /opt/biomate/scrnaseq/render_methods_report.py \\
        --annotated annotated.h5ad \\
        --qc qc_metrics.csv \\
        --params params.json \\
        --out methods_report.html

    cat <<EOF > versions.yml
    "${task.process}":
        scanpy: \$(python -c "import scanpy; print(scanpy.__version__)")
        harmony: \$(python -c "import harmony; print(harmony.__version__)")
        celltypist: \$(python -c "import celltypist; print(celltypist.__version__)")
        scDblFinder: \$(Rscript -e "cat(as.character(packageVersion('scDblFinder')))")
    EOF
    """
}
