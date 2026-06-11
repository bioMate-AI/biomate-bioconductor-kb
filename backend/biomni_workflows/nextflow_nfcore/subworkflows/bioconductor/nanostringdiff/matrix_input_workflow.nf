#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NanoStringDiff — matrix_input_workflow
// Perform differential expression analysis on NanoString nCounter data imported from separate raw count matrices.
// Input: endogenous, positive, negative, housekeeping, designs
// Container: quay.io/biocontainers/bioconductor-nanostringdiff:1.40.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, NanoStringDiff
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load matrices and design data frame from the working
//  * 2. [Input & Preparation] Create a NanoStringSet object using createNanoStringSet
//  * 3. [Input & Preparation] Create the design matrix using model.matrix
//  * 4. [Input & Preparation] Estimate normalization factors using
//  * 5. [Input & Preparation] Perform differential expression analysis using glm.LRT

nextflow.enable.dsl = 2

process BIOC_NANOSTRINGDIFF_MATRIX_INPUT_WORKFLOW {
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
    .bm_deps <- c("Biobase", "NanoStringDiff")
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
    library(Biobase)
    library(NanoStringDiff)
    
    # Helper function to read matrix inputs robustly (supporting CSV and TSV)
    read_input_matrix <- function(base_name) {
      csv_file <- paste0(base_name, ".csv")
      tsv_file <- paste0(base_name, ".tsv")
      
      if (file.exists(csv_file)) {
        message("Reading ", csv_file, "...")
        return(as.matrix(read.csv(csv_file, row.names = 1, check.names = FALSE)))
      } else if (file.exists(tsv_file)) {
        message("Reading ", tsv_file, "...")
        return(as.matrix(read.delim(tsv_file, row.names = 1, check.names = FALSE)))
      } else if (file.exists(base_name)) {
        message("Reading ", base_name, "...")
        return(as.matrix(read.csv(base_name, row.names = 1, check.names = FALSE)))
      } else {
        stop(paste("Required input file not found for:", base_name))
      }
    }
    
    # Helper function to read design data frame robustly
    read_input_df <- function(base_name) {
      csv_file <- paste0(base_name, ".csv")
      tsv_file <- paste0(base_name, ".tsv")
      
      if (file.exists(csv_file)) {
        message("Reading ", csv_file, "...")
        return(read.csv(csv_file, check.names = FALSE))
      } else if (file.exists(tsv_file)) {
        message("Reading ", tsv_file, "...")
        return(read.delim(tsv_file, check.names = FALSE))
      } else if (file.exists(base_name)) {
        message("Reading ", base_name, "...")
        return(read.csv(base_name, check.names = FALSE))
      } else {
        stop(paste("Required input file not found for:", base_name))
      }
    }
    
    # --- Load matrices and design data frame from the working ---
    endogenous <- read_input_matrix("endogenous")
    positive <- read_input_matrix("positive")
    negative <- read_input_matrix("negative")
    housekeeping <- read_input_matrix("housekeeping")
    designs <- read_input_df("designs")
    
    # --- Create a NanoStringSet object using createNanoStringSet ---
    NanoStringData1=createNanoStringSet(endogenous,positive,
                                     negative,housekeeping,designs)
    
    # --- Create the design matrix using model.matrix ---
    pheno=pData(NanoStringData1)
    group=pheno\$group
    design.full=model.matrix(~0+group)
    
    # Define contrast vector (comparing the two groups)
    contrast=c(-1,1)
    
    # --- Estimate normalization factors using ---
    NanoStringData1=estNormalizationFactors(NanoStringData1)
    
    # --- Perform differential expression analysis using glm.LRT ---
    result=glm.LRT(NanoStringData1,design.full,contrast=contrast)
    
    # Write outputs
    message("Writing results to output files...")
    
    # Save the differential expression statistics table
    write.csv(result\$table, file = "differential_expression_results.csv", row.names = TRUE)
    
    # Save the full result list and normalized object as RDS
    saveRDS(result, file = "nanostring_diff_results.rds")
    saveRDS(NanoStringData1, file = "normalized_nanostring_data.rds")
    
    # Generate diagnostic and results plots
    pdf("differential_expression_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    
    # P-value histogram
    hist(result\$table\$pvalue, breaks = 50, col = "skyblue",
         main = "P-value Distribution", xlab = "p-value")
    
    # Volcano plot
    plot(result\$table\$logFC, -log10(result\$table\$pvalue), pch = 20, col = "grey",
         main = "Volcano Plot", xlab = "log2 Fold Change", ylab = "-log10(p-value)")
    sig <- result\$table\$qvalue < 0.05
    if (any(sig, na.rm = TRUE)) {
      points(result\$table\$logFC[sig], -log10(result\$table\$pvalue)[sig], pch = 20, col = "red")
    }
    
    dev.off()
    
    message("Workflow completed successfully.")

    writeLines(c(
        '"BIOC_NANOSTRINGDIFF_MATRIX_INPUT_WORKFLOW":',
        paste0('    NanoStringDiff: ', as.character(packageVersion('NanoStringDiff')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrix_input_workflow.csv versions.yml
    """
}

workflow BIOC_NANOSTRINGDIFF_MATRIX_INPUT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ endogenous, positive, negative, housekeeping, designs ] ]

    main:
    BIOC_NANOSTRINGDIFF_MATRIX_INPUT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_NANOSTRINGDIFF_MATRIX_INPUT_WORKFLOW.out.tables
    plots    = BIOC_NANOSTRINGDIFF_MATRIX_INPUT_WORKFLOW.out.plots
    objects  = BIOC_NANOSTRINGDIFF_MATRIX_INPUT_WORKFLOW.out.objects
    versions = BIOC_NANOSTRINGDIFF_MATRIX_INPUT_WORKFLOW.out.versions
}
