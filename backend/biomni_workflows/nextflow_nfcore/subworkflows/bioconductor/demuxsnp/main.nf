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
    library(HTODemux)
    library(Heatmap)
    library(Seurat)
    library(jsonlite)

    # --- Structure [] ---
    # Key functions: structure, viridis
    ---------------------------------------------------------------------
    colors <- structure(viridis(n = 3), names = c("-1", "0", "1"))
    # --- Data [] ---
    # Key functions: data, class
    ---------------------------------------------------------------------
    data(multiplexed_scrnaseq_sce,
         commonvariants_1kgenomes_subset,
         vartrix_consensus_snps,
         package = "demuxSNP")
    # --- Logcounts [] ---
    # Key functions: logcounts, counts, Seurat, HTODemux, factor
    ---------------------------------------------------------------------
    logcounts(multiplexed_scrnaseq_sce) <- counts(multiplexed_scrnaseq_sce)
    seurat <- as.Seurat(multiplexed_scrnaseq_sce)
    seurat <- HTODemux(seurat)
    seurat$hash.ID <- factor(as.character(seurat$hash.ID))
    # --- Dittoplot [] ---
    # Key functions: dittoPlot
    ---------------------------------------------------------------------
    dittoPlot(seurat, "nCount_HTO", group.by = "hash.ID")
    dittoPlot(seurat, "nCount_RNA", group.by = "hash.ID")
    # --- Common Genes [] ---
    # Key functions: common_genes
    ---------------------------------------------------------------------
    top_genes <- common_genes(sce = multiplexed_scrnaseq_sce, n = 100)
    top_genes[1:10]
    # --- Genome [] ---
    # Key functions: genome, subset_vcf
    ---------------------------------------------------------------------
    ensdb <- EnsDb.Hsapiens.v86::EnsDb.Hsapiens.v86
    genome(commonvariants_1kgenomes_subset)[1] == genome(ensdb)[1]
    new_vcf <- subset_vcf(commonvariants_1kgenomes_subset, top_genes = top_genes, ensdb)
    commonvariants_1kgenomes_subset
    # --- High Conf Calls [] ---
    # Key functions: high_conf_calls
    ---------------------------------------------------------------------
    multiplexed_scrnaseq_sce <- high_conf_calls(multiplexed_scrnaseq_sce)
    table(multiplexed_scrnaseq_sce$train)
    table(multiplexed_scrnaseq_sce$predict)
    table(multiplexed_scrnaseq_sce$labels)
    # --- Dim [] ---
    # Key functions: add_snps, altExp
    ---------------------------------------------------------------------
    dim(vartrix_consensus_snps)
    multiplexed_scrnaseq_sce <- add_snps(multiplexed_scrnaseq_sce, vartrix_consensus_snps, thresh = 0.95)
    altExp(multiplexed_scrnaseq_sce, "SNP")
    # --- Heatmap [] ---
    # Key functions: Heatmap, counts, altExp, draw, unit
    ---------------------------------------------------------------------
    hm <- Heatmap(counts(altExp(multiplexed_scrnaseq_sce, "SNP")),
        column_split = multiplexed_scrnaseq_sce$seurat,
        cluster_rows = FALSE,
        show_column_names = FALSE,
    # --- Droplevels [] ---
    # Key functions: droplevels
    ---------------------------------------------------------------------
    sce_test <- multiplexed_scrnaseq_sce[, multiplexed_scrnaseq_sce$train == TRUE]
    sce_test$knn <- NULL
    #sce_test$labels <- droplevels(sce_test$labels)
    sce_test
    # --- Reassign Centroid [] ---
    # Key functions: reassign_centroid
    ---------------------------------------------------------------------
    sce_test$knn <- reassign_centroid(sce_test, train_cells = sce_test$train2, predict_cells = sce_test$test, min_cells = 5)
    table(sce_test$labels[sce_test$test == TRUE], sce_test$knn[sce_test$test == TRUE])
    # --- Which [] ---
    # Key functions: reassign_centroid
    ---------------------------------------------------------------------
    sce_test$labels2[which(sce_test$labels2 == "Hashtag5")[1:25]] <- "Hashtag2"
    table(sce_test$labels, sce_test$labels2)
    sce_test$knn <- reassign_centroid(sce_test,
        train_cells = sce_test$train,
    # --- Heatmap [] ---
    # Key functions: Heatmap, counts, altExp, draw, unit
    ---------------------------------------------------------------------
    hm <- Heatmap(counts(altExp(sce_test, "SNP"))[, sce_test$knn == "Hashtag6"],
        column_split = sce_test$labels[sce_test$knn == "Hashtag6"],
        cluster_rows = FALSE,
        show_column_names = FALSE,

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
