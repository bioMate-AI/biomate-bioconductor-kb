#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MethReg — distance_based_analysis
// Identify and evaluate regulatory CpGs by linking them to target genes and TFs using genomic distance and motif matching.
// Input: dnam_matrix.rds, gene_exp_matrix.rds
// Container: quay.io/biocontainers/bioconductor-methreg:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MethReg, SummarizedExperiment, dplyr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert DNA methylation matrix to a RangedSummarizedExperiment using make_dnam_se
//  * 2. [Core Analysis] Convert gene expression matrix to a RangedSummarizedExperiment using make_exp_se
//  * 3. [Input & Preparation] Create CpG-TF-target gene triplets using create_triplet_distance_based
//  * 4. [Core Analysis] Fit robust linear interaction models to evaluate synergistic effects using interaction_model
//  * 5. [Core Analysis] Perform stratified analysis on high vs low methylation groups using stratified_model
//  * 6. [Visualization & Output] Visualize the interaction model results using plot_interaction_model

nextflow.enable.dsl = 2

process BIOC_METHREG_DISTANCE_BASED_ANALYSIS {
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
    library(MethReg)
    library(dplyr)
    
    # ----------------------------------------------------------------------
    # Step 0: Read User Input Files
    # ----------------------------------------------------------------------
    if (!file.exists("dnam_matrix.rds") || !file.exists("gene_exp_matrix.rds")) {
      stop("Required input files 'dnam_matrix.rds' and/or 'gene_exp_matrix.rds' are missing from the working directory.")
    }
    
    dna.met.chr21 <- readRDS("dnam_matrix.rds")
    gene.exp.chr21.log2 <- readRDS("gene_exp_matrix.rds")
    
    # Ensure inputs are in matrix format
    if (!is.matrix(dna.met.chr21)) {
      dna.met.chr21 <- as.matrix(dna.met.chr21)
    }
    if (!is.matrix(gene.exp.chr21.log2)) {
      gene.exp.chr21.log2 <- as.matrix(gene.exp.chr21.log2)
    }
    
    # ----------------------------------------------------------------------
    # Step 1: Convert DNA methylation matrix to RangedSummarizedExperiment
    # ----------------------------------------------------------------------
    dna.met.chr21.se <- make_dnam_se(
      dnam = dna.met.chr21,
      genome = "hg38",
      arrayType = "450k",
      betaToM = FALSE, # transform beta to m-values 
      verbose = FALSE # hide informative messages
    )
    
    # ----------------------------------------------------------------------
    # Step 2: Convert gene expression matrix to RangedSummarizedExperiment
    # ----------------------------------------------------------------------
    gene.exp.chr21.se <- make_exp_se(
      exp = gene.exp.chr21.log2,
      genome = "hg38",
      verbose = FALSE
    )
    
    # ----------------------------------------------------------------------
    # Step 3: Create CpG-TF-target gene triplets using genomic distance
    # ----------------------------------------------------------------------
    triplet.promoter <- create_triplet_distance_based(
      region = dna.met.chr21.se,
      target.method = "genes.promoter.overlap",
      genome = "hg38",
      target.promoter.upstream.dist.tss = 2000,
      target.promoter.downstream.dist.tss = 2000,
      motif.search.window.size = 400,
      motif.search.p.cutoff  = 1e-08,
      cores = 1  
    )
    
    # Save triplets intermediate object
    saveRDS(triplet.promoter, "triplet_promoter.rds")
    
    # ----------------------------------------------------------------------
    # Step 4: Fit robust linear interaction models
    # ----------------------------------------------------------------------
    results.interaction.model <- interaction_model(
        triplet = triplet.promoter, 
        dnam = dna.met.chr21.se,
        exp = gene.exp.chr21.se,
        dnam.group.threshold = 0.1,
        sig.threshold = 0.05,
        fdr = TRUE,
        stage.wise.analysis = FALSE,
        filter.correlated.tf.exp.dnam = FALSE,
        filter.triplet.by.sig.term = TRUE
    )
    
    # Save interaction model results
    saveRDS(results.interaction.model, "results_interaction_model.rds")
    write.csv(results.interaction.model, "results_interaction_model.csv", row.names = FALSE)
    
    # ----------------------------------------------------------------------
    # Step 5: Perform stratified analysis on high vs low methylation groups
    # ----------------------------------------------------------------------
    results.stratified.model <- data.frame()
    if (nrow(results.interaction.model) > 0) {
      results.stratified.model <- stratified_model(
          triplet = results.interaction.model,
          dnam = dna.met.chr21.se,
          exp = gene.exp.chr21.se,
          dnam.group.threshold = 0.25
      )
      saveRDS(results.stratified.model, "results_stratified_model.rds")
      write.csv(results.stratified.model, "results_stratified_model.csv", row.names = FALSE)
    } else {
      warning("No significant triplets found in interaction model. Stratified model was not run.")
    }
    
    # ----------------------------------------------------------------------
    # Step 6: Visualize the interaction model results
    # ----------------------------------------------------------------------
    if (nrow(results.interaction.model) > 0) {
      plots <- plot_interaction_model(
          triplet.results = results.interaction.model[1,], 
          dnam = dna.met.chr21.se, 
          exp = gene.exp.chr21.se,
          dnam.group.threshold = 0.25
      )
      
      # Save plots to PDF
      pdf("interaction_plots.pdf", width = 11, height = 8)
      if (inherits(plots, "list")) {
        for (p in plots) {
          # If it's a ggplot or gtable, print/draw it
          if (inherits(p, "gtable") || inherits(p, "ggplot")) {
            grid::grid.newpage()
            grid::grid.draw(p)
          } else {
            print(p)
          }
        }
      } else {
        print(plots)
      }
      dev.off()
    } else {
      warning("No significant triplets to plot.")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_METHREG_DISTANCE_BASED_ANALYSIS":',
        paste0('    MethReg: ', as.character(packageVersion('MethReg')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_distance_based_analysis.csv versions.yml
    """
}

workflow BIOC_METHREG_DISTANCE_BASED_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dnam_matrix.rds, gene_exp_matrix.rds ] ]

    main:
    BIOC_METHREG_DISTANCE_BASED_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METHREG_DISTANCE_BASED_ANALYSIS.out.tables
    plots    = BIOC_METHREG_DISTANCE_BASED_ANALYSIS.out.plots
    objects  = BIOC_METHREG_DISTANCE_BASED_ANALYSIS.out.objects
    versions = BIOC_METHREG_DISTANCE_BASED_ANALYSIS.out.versions
}
