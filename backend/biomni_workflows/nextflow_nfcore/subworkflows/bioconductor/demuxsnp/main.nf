#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: demuxSNP
// This package assists in demultiplexing scRNAseq data using both cell hashing and SNPs data. The SNP 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/demuxSNP/inst/doc/supervised_demultiplexing.R
// Upstream  : ComplexHeatmap, Seurat, dittoSeq, ggpubr, utils
// Downstream: none
//
// Install: BiocManager::install("demuxSNP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEMUXSNP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-demuxsnp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-demuxsnp:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-demuxsnp:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_demuxsnp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_demuxsnp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_demuxsnp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(demuxSNP)
    library(HTODemux)
    library(Heatmap)
    library(Seurat)
    library(jsonlite)

    # --- Gene Selection [] ---
    # Key functions: common_genes
    top_genes <- common_genes(
        sce = multiplexed_scrnaseq_sce,
        n = 100
    )

    # --- VCF Subsetting [] ---
    # Key functions: subset_vcf
    ensdb <- EnsDb.Hsapiens.v86::EnsDb.Hsapiens.v86
    new_vcf <- subset_vcf(
        vcf = commonvariants_1kgenomes_subset,
        top_genes = top_genes,
        ensdb = ensdb
    )

    # --- High Confidence Call Identification [] ---
    # Key functions: high_conf_calls
    multiplexed_scrnaseq_sce <- high_conf_calls(
        multiplexed_scrnaseq_sce
    )

    # --- SNP Matrix Integration [] ---
    # Key functions: add_snps
    multiplexed_scrnaseq_sce <- add_snps(
        multiplexed_scrnaseq_sce,
        vartrix_consensus_snps,
        thresh = 0.95
    )

    # --- Centroid Reassignment [] ---
    # Key functions: reassign_centroid
    multiplexed_scrnaseq_sce$labels <- as.character(
        multiplexed_scrnaseq_sce$labels
    )
    multiplexed_scrnaseq_sce$knn <- reassign_centroid(
        multiplexed_scrnaseq_sce,
        train_cells = multiplexed_scrnaseq_sce$train,
        predict_cells = multiplexed_scrnaseq_sce$predict,
        min_cells = 5
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_demuxsnp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_demuxsnp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_demuxsnp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEMUXSNP:", paste0("    demuxsnp: ", packageVersion("demuxSNP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_demuxsnp_results.csv
    touch ${prefix}_demuxsnp_output.rds
    echo "BIOC_DEMUXSNP:" > versions.yml
    echo "    demuxsnp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEMUXSNP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEMUXSNP(ch_input)

    emit:
    results  = BIOC_DEMUXSNP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEMUXSNP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEMUXSNP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEMUXSNP.out.versions  // channel: path(versions.yml)
}
