#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pfamanalyzer — pfam_domain_isotype_analysis
// Read Pfam domain prediction results and classify them into domain isotypes.
// Input: pfam_results.txt
// Container: quay.io/biocontainers/bioconductor-pfamanalyzer:1.10.0--r45hdfd78af_0
// R packages: dplyr, pfamAnalyzeR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PFAMANALYZER_PFAM_DOMAIN_ISOTYPE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-pfamanalyzer:1.10.0--r45hdfd78af_0"

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
    .bm_deps <- c("dplyr", "pfamAnalyzeR")
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
    library(pfamAnalyzeR)
    library(dplyr)
    
    # Define the path to the Pfam result file (User Input)
    pfamResultFile <- "pfam_results.txt"
    
    # Verify that the user input file exists
    if (!file.exists(pfamResultFile)) {
        stop(paste("Error: Input file '", pfamResultFile, "' not found in the working directory.", sep = ""))
    }
    
    # Run the isotype classification analysis using pfamAnalyzeR
    pfamRes <- pfamAnalyzeR(pfamResultFile)
    
    # Explore and display the head of the results
    result_head <- pfamRes %>% 
        select(seq_id, hmm_name, type, domain_isotype, domain_isotype_simple) %>% 
        head()
    
    cat("\n--- First few entries of the classified Pfam domains ---\n")
    print(result_head)
    
    # Summarize domain isotype
    isotype_table <- table(pfamRes\$domain_isotype)
    cat("\n--- Summary of domain isotypes ---\n")
    print(isotype_table)
    
    # Summarize simplified domain isotype
    isotype_simple_table <- table(pfamRes\$domain_isotype_simple)
    cat("\n--- Summary of simplified domain isotypes ---\n")
    print(isotype_simple_table)
    
    # Summarize domain type vs simplified domain isotype
    type_vs_isotype_table <- table(
        pfamRes\$type,
        pfamRes\$domain_isotype_simple
    )
    cat("\n--- Summary of domain type vs simplified domain isotype ---\n")
    print(type_vs_isotype_table)
    
    # Write meaningful results to output files
    write.csv(pfamRes, "pfam_isotype_results.csv", row.names = FALSE)
    saveRDS(pfamRes, "pfam_isotype_results.rds")
    
    # Save summary tables as CSV files
    write.csv(as.data.frame(isotype_table), "domain_isotype_summary.csv", row.names = FALSE)
    write.csv(as.data.frame(isotype_simple_table), "domain_isotype_simple_summary.csv", row.names = FALSE)
    write.csv(as.data.frame(type_vs_isotype_table), "type_vs_isotype_summary.csv", row.names = TRUE)
    
    cat("\nAnalysis complete. Outputs saved to:\n")
    cat("- pfam_isotype_results.csv\n")
    cat("- pfam_isotype_results.rds\n")
    cat("- domain_isotype_summary.csv\n")
    cat("- domain_isotype_simple_summary.csv\n")
    cat("- type_vs_isotype_summary.csv\n")

    writeLines(c(
        '"BIOC_PFAMANALYZER_PFAM_DOMAIN_ISOTYPE_ANALYSIS":',
        paste0('        pfamanalyzer: ', as.character(packageVersion("pfamanalyzer")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pfam_domain_isotype_analysis.csv versions.yml
    """
}

workflow BIOC_PFAMANALYZER_PFAM_DOMAIN_ISOTYPE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pfam_results.txt ] ]

    main:
    BIOC_PFAMANALYZER_PFAM_DOMAIN_ISOTYPE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PFAMANALYZER_PFAM_DOMAIN_ISOTYPE_ANALYSIS.out.tables
    plots    = BIOC_PFAMANALYZER_PFAM_DOMAIN_ISOTYPE_ANALYSIS.out.plots
    objects  = BIOC_PFAMANALYZER_PFAM_DOMAIN_ISOTYPE_ANALYSIS.out.objects
    versions = BIOC_PFAMANALYZER_PFAM_DOMAIN_ISOTYPE_ANALYSIS.out.versions
}
