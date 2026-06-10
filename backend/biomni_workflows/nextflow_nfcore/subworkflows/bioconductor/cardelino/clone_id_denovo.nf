#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cardelino — clone_id_denovo
// Infer clonal structure and assign cells to clones de-novo without a pre-defined clonal tree, typically using mitochondrial or high-coverage variants.
// Input: passed_ad.mtx, passed_dp.mtx, passed_variant_names.txt
// Container: quay.io/biocontainers/bioconductor-cardelino:1.12.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Matrix, cardelino, pheatmap
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read AD and DP matrices and assign variant and cell names
//  * 2. [Core Analysis] Run de-novo Bayesian clustering using clone_id with Config=NULL and specifying n_clone
//  * 3. [Core Analysis] Threshold the posterior configuration probability matrix
//  * 4. [Visualization & Output] Visualize cell assignments and clonal configurations using vc_heatmap

nextflow.enable.dsl = 2

process BIOC_CARDELINO_CLONE_ID_DENOVO {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(Matrix)
    library(cardelino)
    library(pheatmap)
    
    # Define input file paths in the working directory
    AD_file <- "passed_ad.mtx"
    DP_file <- "passed_dp.mtx"
    id_file <- "passed_variant_names.txt"
    
    # Verify input files exist
    if (!file.exists(AD_file)) {
      stop(paste("Required input file missing:", AD_file))
    }
    if (!file.exists(DP_file)) {
      stop(paste("Required input file missing:", DP_file))
    }
    if (!file.exists(id_file)) {
      stop(paste("Required input file missing:", id_file))
    }
    
    # Read input data
    AD <- Matrix::readMM(AD_file)
    DP <- Matrix::readMM(DP_file)
    var_ids <- read.table(id_file)
    
    # Assign variant and cell names
    rownames(AD) <- rownames(DP) <- var_ids[, 1]
    colnames(AD) <- colnames(DP) <- paste0('Cell', seq(ncol(DP)))
    
    # Calculate allele frequency matrix
    AF_mt <- as.matrix(AD / DP)
    
    # Save initial allele frequency heatmap
    pdf("AF_mt_heatmap.pdf", width = 8.5, height = 4.5)
    pheatmap::pheatmap(AF_mt)
    dev.off()
    
    # Run de-novo Bayesian clustering using clone_id
    set.seed(7)
    assign_mtClones <- clone_id(AD, DP, Config=NULL, n_clone = 3, keep_base_clone=FALSE)
    
    # Save the full results object
    saveRDS(assign_mtClones, "assign_mtClones.rds")
    
    # Save cell assignment probabilities
    write.csv(as.data.frame(assign_mtClones\$prob), "cell_assignment_probabilities.csv", row.names = TRUE)
    
    # Threshold the posterior configuration probability matrix
    Config_mt <- assign_mtClones\$Config_prob
    Config_mt[Config_mt >= 0.5] = 1
    Config_mt[Config_mt < 0.5] = 0
    
    # Save thresholded configuration matrix
    write.csv(as.data.frame(Config_mt), "Config_mt.csv", row.names = TRUE)
    
    # Visualize cell assignments and clonal configurations
    pdf("vc_heatmap_mtDNA.pdf", width = 7, height = 4.2)
    cardelino::vc_heatmap(AF_mt, assign_mtClones\$prob, Config_mt, show_legend=TRUE)
    dev.off()

    writeLines(c(
        '"BIOC_CARDELINO_CLONE_ID_DENOVO":',
        paste0('    cardelino: ', as.character(packageVersion('cardelino')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clone_id_denovo.csv versions.yml
    """
}

workflow BIOC_CARDELINO_CLONE_ID_DENOVO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ passed_ad.mtx, passed_dp.mtx, passed_variant_names.txt ] ]

    main:
    BIOC_CARDELINO_CLONE_ID_DENOVO(ch_input)

    emit:
    tables   = BIOC_CARDELINO_CLONE_ID_DENOVO.out.tables
    plots    = BIOC_CARDELINO_CLONE_ID_DENOVO.out.plots
    objects  = BIOC_CARDELINO_CLONE_ID_DENOVO.out.objects
    versions = BIOC_CARDELINO_CLONE_ID_DENOVO.out.versions
}
