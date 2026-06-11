#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hicool — hic_processing_pipeline
// Process raw paired-end Hi-C FASTQ files into binned, normalized contact matrices (.mcool) and interaction pairs (.pairs).
// Input: R1.fq.gz, R2.fq.gz
// Container: quay.io/biocontainers/bioconductor-hicool:1.6.0--r44hdfd78af_0
// R packages: S4Vectors, HiCool
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICOOL_HIC_PROCESSING_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-hicool:1.6.0--r44hdfd78af_0"

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
    .bm_deps <- c("S4Vectors", "HiCool")
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
    
    # Load the required libraries
    library(HiCool)
    library(S4Vectors)
    
    # Define input file paths from the working directory
    r1_input <- "R1.fq.gz"
    r2_input <- "R2.fq.gz"
    
    # Verify that the user input files exist before running the pipeline
    if (!file.exists(r1_input) || !file.exists(r2_input)) {
        stop(paste("Error: Required input files 'R1.fq.gz' and/or 'R2.fq.gz' not found in the working directory.",
                   "Please ensure they are present before running this pipeline."))
    }
    
    # Run the HiCool processing pipeline
    # This maps the reads, filters pairs, bins them, and normalizes the contact matrices.
    hcf <- HiCool(
        r1 = r1_input, 
        r2 = r2_input, 
        restriction = 'DpnII,HinfI', 
        binning = 1000, 
        genome = 'R64-1-1', 
        output = './HiCool/'
    )
    
    # Inspect the returned CoolFile object
    print("--- CoolFile Object Summary ---")
    print(hcf)
    
    # Inspect and extract the metadata
    hcf_metadata <- S4Vectors::metadata(hcf)
    print("--- CoolFile Metadata ---")
    print(hcf_metadata)
    
    # Save the meaningful results to the working directory
    # 1. Save the CoolFile S4 object as an RDS file
    saveRDS(hcf, file = "hicool_result.rds")
    
    # 2. Save the metadata as an RDS file
    saveRDS(hcf_metadata, file = "hicool_metadata.rds")
    
    # 3. Export processing statistics to a CSV file
    if (!is.null(hcf_metadata\$stats)) {
        stats_df <- as.data.frame(hcf_metadata\$stats)
        write.csv(stats_df, file = "hicool_processing_stats.csv", row.names = FALSE)
    }
    
    message("HiCool pipeline completed successfully. Outputs saved to './HiCool/' and the working directory.")

    writeLines(c(
        '"BIOC_HICOOL_HIC_PROCESSING_PIPELINE":',
        paste0('        hicool: ', as.character(packageVersion("hicool")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hic_processing_pipeline.csv versions.yml
    """
}

workflow BIOC_HICOOL_HIC_PROCESSING_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ R1.fq.gz, R2.fq.gz ] ]

    main:
    BIOC_HICOOL_HIC_PROCESSING_PIPELINE(ch_input)

    emit:
    tables   = BIOC_HICOOL_HIC_PROCESSING_PIPELINE.out.tables
    plots    = BIOC_HICOOL_HIC_PROCESSING_PIPELINE.out.plots
    objects  = BIOC_HICOOL_HIC_PROCESSING_PIPELINE.out.objects
    versions = BIOC_HICOOL_HIC_PROCESSING_PIPELINE.out.versions
}
