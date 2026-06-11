#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MethReg — regulon_based_analysis
// Identify and evaluate regulatory CpGs by linking them to target genes and TFs using established regulon databases (e.g., Dorothea) and TF activity scores.
// Input: dnam_matrix.rds, gene_exp_matrix.rds
// Container: quay.io/biocontainers/bioconductor-methreg:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MethReg, SummarizedExperiment, dorothea, dplyr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert DNA methylation matrix to a RangedSummarizedExperiment using make_dnam_se
//  * 2. [Core Analysis] Convert gene expression matrix to a RangedSummarizedExperiment using make_exp_se
//  * 3. [Core Analysis] Calculate TF enrichment scores using get_tf_ES
//  * 4. [Input & Preparation] Create triplets using create_triplet_regulon_based
//  * 5. [Core Analysis] Fit robust linear interaction models using interaction_model

nextflow.enable.dsl = 2

process BIOC_METHREG_REGULON_BASED_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("MethReg", "dplyr", "dorothea")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required libraries
        library(MethReg)
        library(dplyr)
        library(dorothea)
        
        # 1. Read user input files from the working directory
        if (!file.exists("dnam_matrix.rds") || !file.exists("gene_exp_matrix.rds")) {
          stop("Required input files 'dnam_matrix.rds' and/or 'gene_exp_matrix.rds' are missing in the working directory.")
        }
        
        dna.met.chr21 <- readRDS("dnam_matrix.rds")
        gene.exp.chr21.log2 <- readRDS("gene_exp_matrix.rds")
        
        # 2. Convert DNA methylation matrix to a RangedSummarizedExperiment
        dna.met.chr21.se <- make_dnam_se(
          dnam = dna.met.chr21,
          genome = "hg38",
          arrayType = "450k",
          betaToM = FALSE, # transform beta to m-values 
          verbose = FALSE # hide informative messages
        )
        
        # 3. Convert gene expression matrix to a RangedSummarizedExperiment
        gene.exp.chr21.se <- make_exp_se(
          exp = gene.exp.chr21.log2,
          genome = "hg38",
          verbose = FALSE
        )
        
        # 4. Load regulons from Dorothea
        regulons.dorothea <- dorothea::dorothea_hs
        
        # 5. Calculate TF enrichment scores
        rnaseq.tf.es <- get_tf_ES(
          exp = gene.exp.chr21.se %>% SummarizedExperiment::assay(),
          regulons = regulons.dorothea
        )
        
        # Save TF enrichment scores
        saveRDS(rnaseq.tf.es, "tf_enrichment_scores.rds")
        
        # 6. Create triplets using regulon-based approach
        triplet.regulon <- create_triplet_regulon_based(
          region = dna.met.chr21.se,
          genome = "hg38",  
          motif.search.window.size = 400,
          tf.target = regulons.dorothea,
          max.distance.region.target = 10^6 # 1Mbp
        )
        
        # Save triplets
        write.csv(triplet.regulon, "triplets_regulon.csv", row.names = FALSE)
        saveRDS(triplet.regulon, "triplets_regulon.rds")
        
        # 7. Fit robust linear interaction models
        results.interaction.model <- interaction_model(
            triplet = triplet.regulon, 
            dnam = dna.met.chr21.se,
            exp = gene.exp.chr21.se,
            dnam.group.threshold = 0.1,
            sig.threshold = 0.05,
            fdr = TRUE,
            stage.wise.analysis = FALSE,
            filter.correlated.tf.exp.dnam = FALSE,
            filter.triplet.by.sig.term = TRUE,
            tf.activity.es = rnaseq.tf.es
        )
        
        # Save interaction model results
        write.csv(results.interaction.model, "interaction_model_results.csv", row.names = FALSE)
        saveRDS(results.interaction.model, "interaction_model_results.rds")
        
        # 8. Stratified analysis and plotting (if significant triplets are found)
        if (nrow(results.interaction.model) > 0) {
          tryCatch({
            results.stratified.model <- stratified_model(
                triplet = results.interaction.model,
                dnam = dna.met.chr21.se,
                exp = gene.exp.chr21.se,
                dnam.group.threshold = 0.25,
                tf.activity.es = rnaseq.tf.es
            )
            write.csv(results.stratified.model, "stratified_model_results.csv", row.names = FALSE)
            saveRDS(results.stratified.model, "stratified_model_results.rds")
          }, error = function(e) {
            message("Stratified model fitting failed: ", e\$message)
          })
        
          tryCatch({
            plots <- plot_interaction_model(
                triplet.results = results.interaction.model[1,], 
                dnam = dna.met.chr21.se, 
                exp = gene.exp.chr21.se,
                dnam.group.threshold = 0.25,
                tf.activity.es = rnaseq.tf.es
            )
            
            pdf("interaction_plots.pdf", width = 11, height = 8)
            lapply(plots, print)
            dev.off()
          }, error = function(e) {
            message("Plotting failed: ", e\$message)
          })
        } else {
          message("No significant triplets found to plot or run stratified model.")
        }
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_METHREG_REGULON_BASED_ANALYSIS":',
        paste0('    MethReg: ', as.character(packageVersion('MethReg')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regulon_based_analysis.csv versions.yml
    """
}

workflow BIOC_METHREG_REGULON_BASED_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dnam_matrix.rds, gene_exp_matrix.rds ] ]

    main:
    BIOC_METHREG_REGULON_BASED_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METHREG_REGULON_BASED_ANALYSIS.out.tables
    plots    = BIOC_METHREG_REGULON_BASED_ANALYSIS.out.plots
    objects  = BIOC_METHREG_REGULON_BASED_ANALYSIS.out.objects
    versions = BIOC_METHREG_REGULON_BASED_ANALYSIS.out.versions
}
