#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MassArray — massarray_data_analysis
// Import EpiTyper data, perform quality control, visualize methylation levels, and detect potential SNPs.
// Input: Example.txt, sequence
// Container: quay.io/biocontainers/bioconductor-massarray:1.62.0--r45hdfd78af_0
// Requires: MassArray
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define the amplicon sequence with primer boundaries and required sites. 2. Import the EpiTyper data file and sequence into a MassA

nextflow.enable.dsl = 2

process BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required library
    library(MassArray)
    
    # 1. Read user input files from the working directory
    if (!file.exists("sequence")) {
      stop("Error: Required input file 'sequence' not found in the working directory.")
    }
    if (!file.exists("Example.txt")) {
      stop("Error: Required input file 'Example.txt' not found in the working directory.")
    }
    
    # Read and clean the amplicon sequence string
    sequence_lines <- readLines("sequence", warn = FALSE)
    sequence <- paste(sequence_lines, collapse = "")
    sequence <- gsub("[ \t\r\n]", "", sequence)
    
    # 2. Import EpiTyper data and sequence into a MassArrayData object
    data <- new("MassArrayData", sequence, file = "Example.txt")
    
    # 3. Visualize methylation levels and save to a PDF file
    pdf("methylation_plots.pdf", width = 11, height = 8.5)
    plot(data, collapse = FALSE, bars = FALSE, scale = FALSE)
    plot(data, collapse = TRUE, bars = TRUE, scale = FALSE)
    plot(data, collapse = TRUE, bars = FALSE, scale = TRUE)
    dev.off()
    
    # 4. Evaluate potential SNPs
    SNP.results <- evaluateSNPs(data)
    
    # Save the complete SNP results object
    saveRDS(SNP.results, file = "SNP_results.rds")
    
    # Write a text summary of the SNP results
    sink("SNP_results_summary.txt")
    cat("=== SNP Evaluation Summary ===\n")
    cat("Total potential SNPs detected:", length(SNP.results), "\n\n")
    if (length(SNP.results) >= 2) {
      cat("Details for SNP Result [[2]]:\n")
      print(SNP.results[[2]])
    } else if (length(SNP.results) > 0) {
      cat("Details for SNP Result [[1]]:\n")
      print(SNP.results[[1]])
    } else {
      cat("No potential SNPs detected.\n")
    }
    sink()

    writeLines(c(
        '"BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS":',
        paste0('    MassArray: ', as.character(packageVersion('MassArray')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_massarray_data_analysis.csv versions.yml
    """
}

workflow BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Example.txt, sequence ] ]

    main:
    BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS.out.tables
    plots    = BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS.out.plots
    objects  = BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS.out.objects
    versions = BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS.out.versions
}
