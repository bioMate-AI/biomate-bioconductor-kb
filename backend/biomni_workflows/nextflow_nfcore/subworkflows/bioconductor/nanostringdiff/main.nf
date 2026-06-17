#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NanoStringDiff — csv_input_workflow
// Perform differential expression analysis on NanoString nCounter data imported from a combined CSV file.
// Input: Mori.csv, designs
// Container: quay.io/biocontainers/bioconductor-nanostringdiff:1.40.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, NanoStringDiff
// Visualizations: volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Specify the path to the combined CSV file and define the
//  * 2. [Input & Preparation] Create a NanoStringSet object from the CSV file using
//  * 3. [Input & Preparation] Create the design matrix using model.matrix
//  * 4. [Input & Preparation] Estimate normalization factors using
//  * 5. [Input & Preparation] Perform differential expression analysis using glm.LRT

nextflow.enable.dsl = 2

process BIOC_NANOSTRINGDIFF_CSV_INPUT_WORKFLOW {
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
    .bm_deps <- c("Biobase", "NanoStringDiff")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library("Biobase")
    library("NanoStringDiff")
    
    # --- Specify the path to the combined CSV file and define the ---
    path <- "Mori.csv"
    
    # Read the designs data frame from the working directory
    if (file.exists("designs.csv")) {
      designs <- read.csv("designs.csv", header = TRUE)
    } else if (file.exists("designs")) {
      designs <- read.csv("designs", header = TRUE)
    } else {
      # Fallback to the documented default if file is missing
      designs <- data.frame(group=c("Normal","Normal","Tumor","Tumor"))
    }
    
    # --- Create a NanoStringSet object from the CSV file using ---
    NanoStringData=createNanoStringSetFromCsv(path,header=TRUE,designs)
    
    # --- Create the design matrix using model.matrix ---
    pheno=pData(NanoStringData)
    design.full=model.matrix(~0+pheno\$group)
    
    # --- Estimate normalization factors using ---
    NanoStringData=estNormalizationFactors(NanoStringData)
    
    # --- Perform differential expression analysis using glm.LRT ---
    result=glm.LRT(NanoStringData,design.full,contrast=c(1,-1))
    
    # Write named output files
    # Save the full result object
    saveRDS(result, file = "NanoStringDiff_results.rds")
    
    # Save the normalized NanoStringData object
    saveRDS(NanoStringData, file = "NanoStringData_normalized.rds")
    
    # Save the differential expression table as a CSV file
    write.csv(result\$table, file = "differential_expression_results.csv", row.names = TRUE)
    
    # Generate a PDF plot of the results (Volcano Plot)
    pdf("volcano_plot.pdf", width = 7, height = 7)
    plot(result\$table\$logFC, -log10(result\$table\$pvalue),
         xlab = "log2 Fold Change",
         ylab = "-log10 P-value",
         main = "Volcano Plot (Tumor vs Normal)",
         pch = 20,
         col = ifelse(result\$table\$qvalue < 0.05, "red", "black"))
    abline(h = -log10(0.05), col = "blue", lty = 2)
    legend("topright", legend = c("FDR < 0.05", "FDR >= 0.05"), col = c("red", "black"), pch = 20)
    dev.off()

    writeLines(c(
        '"BIOC_NANOSTRINGDIFF_CSV_INPUT_WORKFLOW":',
        paste0('    NanoStringDiff: ', as.character(packageVersion('NanoStringDiff')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_csv_input_workflow.csv versions.yml
    """
}

workflow BIOC_NANOSTRINGDIFF_CSV_INPUT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Mori.csv, designs ] ]

    main:
    BIOC_NANOSTRINGDIFF_CSV_INPUT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_NANOSTRINGDIFF_CSV_INPUT_WORKFLOW.out.tables
    plots    = BIOC_NANOSTRINGDIFF_CSV_INPUT_WORKFLOW.out.plots
    objects  = BIOC_NANOSTRINGDIFF_CSV_INPUT_WORKFLOW.out.objects
    versions = BIOC_NANOSTRINGDIFF_CSV_INPUT_WORKFLOW.out.versions
}
