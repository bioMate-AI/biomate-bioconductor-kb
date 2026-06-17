#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: annotationTools — cross_species_expression_integration
// Map differentially expressed probe sets from a source species to a target species and select the best representative orthologous probe sets based on expression 
// Input: table_mouse, table_human, ortho
// Container: quay.io/biocontainers/bioconductor-annotationtools:1.84.0--r45hdfd78af_0
// R packages: annotationTools
// Bioconductor: 3.20 | R: 4.4
// Requires: annotationTools
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Select top differentially expressed probe sets from the
//  * 2. [Input & Preparation] Retrieve orthologous probe sets in the target species
//  * 3. [Input & Preparation] Create a modified target species data frame containing
//  * 4. [Input & Preparation] Resolve multi-mapping probe sets by selecting the one
//  * 5. [Input & Preparation] Extract and compare the matched expression values between

nextflow.enable.dsl = 2

process BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_EXPRESSION_INTEGRATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("annotationTools")
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
    
    # Load required library
    library(annotationTools)
    
    # Helper function to find and read the input files from the working directory
    find_and_read <- function(base_name) {
      possible_files <- c(
        base_name,
        paste0(base_name, ".csv"),
        paste0(base_name, ".tsv"),
        paste0(base_name, ".txt")
      )
      for (f in possible_files) {
        if (file.exists(f)) {
          # Determine separator and read
          if (grepl("\\\\.csv\$", f)) {
            return(read.csv(f, header = TRUE, stringsAsFactors = FALSE, check.names = FALSE))
          } else {
            return(read.delim(f, header = TRUE, stringsAsFactors = FALSE, check.names = FALSE))
          }
        }
      }
      stop(paste("Required input file not found in working directory:", base_name))
    }
    
    # Read exactly the declared user input files
    table_mouse <- find_and_read("table_mouse")
    table_human <- find_and_read("table_human")
    ortho <- find_and_read("ortho")
    
    # Ensure ortho columns are character vectors to prevent matching issues
    ortho[] <- lapply(ortho, as.character)
    
    # --- Select top differentially expressed probe sets from the ---
    selection <- 1:8
    ps_mouse <- table_mouse\$Probe.Set.ID[selection]
    
    # --- Retrieve orthologous probe sets in the target species ---
    orthops <- getOrthologousProbesets(ps_mouse, table_human, ortho)
    
    # --- Create a modified target species data frame containing ---
    table_human_absM <- data.frame(I(table_human[, 1]), I(abs(table_human[, 2])))
    
    # --- Resolve multi-mapping probe sets by selecting the one ---
    # using getOrthologousProbesets with forceProbesetSelection=TRUE
    orthops_maxAbsM <- getOrthologousProbesets(ps_mouse, table_human_absM,
                                               ortho, max, forceProbesetSelection = TRUE)
    
    # --- Extract and compare the matched expression values between ---
    orthops_maxAbsM_ind <- match(unlist(orthops_maxAbsM[[1]]), table_human[, 1])
    matched_target_values <- table_human[orthops_maxAbsM_ind, 2]
    
    # --- Write Outputs ---
    
    # Save RDS objects of the mapping results
    saveRDS(orthops, "orthops_all.rds")
    saveRDS(orthops_maxAbsM, "orthops_maxAbsM.rds")
    
    # Create and write a summary CSV table of the mapped results
    results_df <- data.frame(
      Source_Probe_Set = ps_mouse,
      Target_Probe_Set = unlist(orthops_maxAbsM[[1]]),
      Source_Stat = table_mouse[selection, 2],
      Target_Stat = matched_target_values,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "mapped_orthologs_expression.csv", row.names = FALSE)
    
    # Generate a PDF plot comparing the expression statistics between the two species
    pdf("cross_species_expression_comparison.pdf", width = 6, height = 6)
    plot(table_mouse[selection, 2], matched_target_values,
         pch = 19, col = "darkblue", cex = 1.5,
         xlab = "Expression Statistic (Source Species)",
         ylab = "Expression Statistic (Target Species)",
         main = "Cross-Species Expression Integration")
    abline(h = 0, lty = 2, col = "gray")
    abline(v = 0, lty = 2, col = "gray")
    abline(0, 1, lty = 3, col = "red")
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written to 'mapped_orthologs_expression.csv', 'cross_species_expression_comparison.pdf', 'orthops_all.rds', and 'orthops_maxAbsM.rds'.\n")

    writeLines(c(
        '"BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_EXPRESSION_INTEGRATION":',
        paste0('    annotationTools: ', as.character(packageVersion('annotationTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cross_species_expression_integration.csv versions.yml
    """
}

workflow BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_EXPRESSION_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ table_mouse, table_human, ortho ] ]

    main:
    BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_EXPRESSION_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_EXPRESSION_INTEGRATION.out.tables
    plots    = BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_EXPRESSION_INTEGRATION.out.plots
    objects  = BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_EXPRESSION_INTEGRATION.out.objects
    versions = BIOC_ANNOTATIONTOOLS_CROSS_SPECIES_EXPRESSION_INTEGRATION.out.versions
}
