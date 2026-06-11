#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: YAPSA — stratified_signature_analysis
// Perform a stratified analysis of mutational signatures (SMC) to identify signature enrichment and depletion patterns across different genomic strata (e.g., muta
// Input: lymphoma_Nature2013_df, lymphoma_COSMIC_listsList, COSMIC_subgroups_df, BSgenome.Hsapiens.UCSC.hg19
// Container: quay.io/biocontainers/bioconductor-yapsa:1.36.1--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, YAPSA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_YAPSA_STRATIFIED_SIGNATURE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-yapsa:1.36.1--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "YAPSA")
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
    library(YAPSA)
    
    # Read user input files from the working directory
    lymphoma_Nature2013_df <- readRDS("lymphoma_Nature2013_df.rds")
    lymphoma_COSMIC_listsList <- readRDS("lymphoma_COSMIC_listsList.rds")
    COSMIC_subgroups_df <- readRDS("COSMIC_subgroups_df.rds")
    
    # Load reference genome object (try RDS first, fallback to library)
    if (file.exists("BSgenome.Hsapiens.UCSC.hg19.rds")) {
      BSgenome.Hsapiens.UCSC.hg19 <- readRDS("BSgenome.Hsapiens.UCSC.hg19.rds")
    } else {
      library(BSgenome.Hsapiens.UCSC.hg19)
    }
    
    # 1. Define exclusive strata categories based on intermutational distance
    lymphoma_Nature2013_df\$density_cat <- cut(
      lymphoma_Nature2013_df\$dist, 
      c(0, 1001, 100001, Inf), 
      right = FALSE, 
      labels = c("high", "intermediate", "background")
    )
    
    # 2. Run the Stratification of the Mutational Catalogue (SMC) analysis
    strata_order_ind <- c(1, 3, 2)
    mut_density_list <- run_SMC(
      lymphoma_Nature2013_df, 
      lymphoma_COSMIC_listsList\$cohort\$signatures, 
      lymphoma_COSMIC_listsList\$cohort\$out_sig_ind_df, 
      COSMIC_subgroups_df, 
      column_name = "density_cat", 
      refGenome = BSgenome.Hsapiens.UCSC.hg19, 
      cohort_method_flag = "norm_PIDs", 
      in_strata_order_ind = strata_order_ind
    )
    
    # 3. Perform statistical significance testing
    stat_mut_density_list <- stat_test_SMC(mut_density_list, in_flag = "norm")
    
    # Save outputs to the working directory
    saveRDS(mut_density_list, "mut_density_list.rds")
    saveRDS(stat_mut_density_list, "stat_mut_density_list.rds")
    
    # Export statistical test results as CSV tables if they are data frames
    if (is.list(stat_mut_density_list)) {
      for (name in names(stat_mut_density_list)) {
        df_test <- stat_mut_density_list[[name]]
        if (is.data.frame(df_test)) {
          write.csv(df_test, paste0("stat_test_SMC_", name, ".csv"), row.names = TRUE)
        }
      }
    }

    writeLines(c(
        '"BIOC_YAPSA_STRATIFIED_SIGNATURE_ANALYSIS":',
        paste0('        YAPSA: ', as.character(packageVersion("YAPSA")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stratified_signature_analysis.csv versions.yml
    """
}

workflow BIOC_YAPSA_STRATIFIED_SIGNATURE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ lymphoma_Nature2013_df, lymphoma_COSMIC_listsList, COSMIC_subgroups_df, BSgenome.Hsapiens.UCSC.hg19 ] ]

    main:
    BIOC_YAPSA_STRATIFIED_SIGNATURE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_YAPSA_STRATIFIED_SIGNATURE_ANALYSIS.out.tables
    plots    = BIOC_YAPSA_STRATIFIED_SIGNATURE_ANALYSIS.out.plots
    objects  = BIOC_YAPSA_STRATIFIED_SIGNATURE_ANALYSIS.out.objects
    versions = BIOC_YAPSA_STRATIFIED_SIGNATURE_ANALYSIS.out.versions
}
