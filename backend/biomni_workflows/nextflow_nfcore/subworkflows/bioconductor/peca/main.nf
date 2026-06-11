#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PECA — peca_proteomics_tsv
// Identify differential protein expression from peptide-level measurements in a TSV file.
// Input: peptides.tsv
// Container: quay.io/biocontainers/bioconductor-peca:1.42.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PECA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define sample groups
//  * 2. [Core Analysis] Run PECA on the TSV file using PECA_tsv

nextflow.enable.dsl = 2

process BIOC_PECA_PECA_PROTEOMICS_TSV {
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
    
    # Load the required library
    library(PECA)
    
    # Define the input file path as specified in the user input requirements
    filePath <- "peptides.tsv"
    
    # Verify that the input file exists before proceeding
    if (!file.exists(filePath)) {
      stop(paste("Error: Input file", filePath, "not found in the working directory."))
    }
    
    # Read a few rows to determine column names and types
    data_sample <- read.csv(filePath, sep = "\t", nrows = 5)
    
    # Exclude the first column (Protein IDs)
    potential_samples <- colnames(data_sample)[-1]
    
    # Keep only numeric columns as sample columns (ignores columns like 'Sequence')
    is_num <- sapply(data_sample[potential_samples], is.numeric)
    sample_cols <- potential_samples[is_num]
    
    # Split the sample columns into two groups for comparison
    half <- length(sample_cols) %/% 2
    group1 <- sample_cols[1:half]
    group2 <- sample_cols[(half + 1):length(sample_cols)]
    
    # Run PECA on the TSV file
    results <- PECA_tsv(filePath, group1, group2)
    
    # Write the meaningful results to output files
    write.csv(results, file = "peca_results.csv", row.names = TRUE)
    saveRDS(results, file = "peca_results.rds")
    
    # Generate a diagnostic plot of the p-value distribution
    tryCatch({
      pdf("peca_pvalues_histogram.pdf")
      hist(results\$p, breaks = 50, col = "skyblue",
           main = "Histogram of PECA p-values",
           xlab = "p-value")
      dev.off()
    }, error = function(e) {
      message("Could not generate PDF plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_PECA_PECA_PROTEOMICS_TSV":',
        paste0('    PECA: ', as.character(packageVersion('PECA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peca_proteomics_tsv.csv versions.yml
    """
}

workflow BIOC_PECA_PECA_PROTEOMICS_TSV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peptides.tsv ] ]

    main:
    BIOC_PECA_PECA_PROTEOMICS_TSV(ch_input)

    emit:
    tables   = BIOC_PECA_PECA_PROTEOMICS_TSV.out.tables
    plots    = BIOC_PECA_PECA_PROTEOMICS_TSV.out.plots
    objects  = BIOC_PECA_PECA_PROTEOMICS_TSV.out.objects
    versions = BIOC_PECA_PECA_PROTEOMICS_TSV.out.versions
}
