#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: prebs — manufacturer_cdf_probeset_expression
// Calculate probe set-level expression values from RNA-seq BAM files using a manufacturer's CDF mapping to achieve comparability with microarray data.
// Input: bam_files.bam, manufacturer_cdf_mapping.txt
// Container: quay.io/biocontainers/bioconductor-prebs:1.50.0--r45hdfd78af_0
// R packages: Biobase, prebs
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, prebs
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the prebs package
//  * 2. [Core Analysis] Run calc_prebs with BAM files, the manufacturer's CDF mapping file, and optionally the explicit cdf_name
//  * 3. [Core Analysis] Retrieve the expression values from the resulting ExpressionSet

nextflow.enable.dsl = 2

process BIOC_PREBS_MANUFACTURER_CDF_PROBESET_EXPRESSION {
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
    .bm_deps <- c("Biobase", "prebs")
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
    
    # 1. Load the required packages
    library(prebs)
    library(Biobase)
    
    # Define input files exactly as specified by the user
    bam_files <- "bam_files.bam"
    manufacturer_cdf_mapping <- "manufacturer_cdf_mapping.txt"
    
    # Verify that the required input files exist in the working directory
    if (!file.exists(bam_files)) {
      stop("Error: Input BAM file 'bam_files.bam' not found in the working directory.")
    }
    if (!file.exists(manufacturer_cdf_mapping)) {
      stop("Error: Input mapping file 'manufacturer_cdf_mapping.txt' not found in the working directory.")
    }
    
    # 2. Run calc_prebs with BAM files and the manufacturer's CDF mapping file
    # (Function call and argument names are kept exactly as documented)
    message("Calculating PREBS values from BAM file using manufacturer CDF mapping...")
    prebs_values <- calc_prebs(bam_files, manufacturer_cdf_mapping)
    
    # 3. Retrieve the expression values from the resulting ExpressionSet
    expression_matrix <- exprs(prebs_values)
    
    # Print a preview of the expression values to the console
    message("Preview of calculated expression values:")
    print(head(expression_matrix))
    
    # 4. Write named output files for the results
    output_txt <- "prebs_values.txt"
    output_rds <- "prebs_values.rds"
    
    message(paste("Saving expression matrix to text file:", output_txt))
    write.table(expression_matrix, file = output_txt, quote = FALSE, sep = "\t", col.names = NA)
    
    message(paste("Saving complete ExpressionSet object to RDS file:", output_rds))
    saveRDS(prebs_values, file = output_rds)
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_PREBS_MANUFACTURER_CDF_PROBESET_EXPRESSION":',
        paste0('    prebs: ', as.character(packageVersion('prebs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_manufacturer_cdf_probeset_expression.csv versions.yml
    """
}

workflow BIOC_PREBS_MANUFACTURER_CDF_PROBESET_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam_files.bam, manufacturer_cdf_mapping.txt ] ]

    main:
    BIOC_PREBS_MANUFACTURER_CDF_PROBESET_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_PREBS_MANUFACTURER_CDF_PROBESET_EXPRESSION.out.tables
    plots    = BIOC_PREBS_MANUFACTURER_CDF_PROBESET_EXPRESSION.out.plots
    objects  = BIOC_PREBS_MANUFACTURER_CDF_PROBESET_EXPRESSION.out.objects
    versions = BIOC_PREBS_MANUFACTURER_CDF_PROBESET_EXPRESSION.out.versions
}
