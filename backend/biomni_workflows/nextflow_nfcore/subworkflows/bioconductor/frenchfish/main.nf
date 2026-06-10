#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: frenchfish — correct_automated_counts
// Correct automatically counted FISH spots from FISHalyseR CSV output using a homogenous Poisson Point Process model and nuclear volume correction.
// Input: SampleFISH.jpg_data.csv
// Container: quay.io/biocontainers/bioconductor-frenchfish:1.22.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FRENCHFISH_CORRECT_AUTOMATED_COUNTS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-frenchfish:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("frenchfish")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required library
    library(frenchFISH)
    
    # Define the input file path (must be in the working directory as specified)
    fishalyserCsvPath <- "SampleFISH.jpg_data.csv"
    
    # Check if the input file exists before proceeding
    if (!file.exists(fishalyserCsvPath)) {
      stop(paste("Required input file missing:", fishalyserCsvPath))
    }
    
    # 1. Convert FISHalyseR CSV to a formatted count matrix
    automatic_counts <- convertFishalyserCsvToCountMatrix(fishalyserCsvPath)
    
    # 2. Set random seed for reproducibility
    set.seed(366)
    
    # Define parameters
    nuclear_radius <- 40
    section_height <- 5
    
    # 3. Run the homogenous Poisson Point Process model with nuclear volume correction
    corrected_automatic_counts <- getAutomaticCountsEstimates(automatic_counts, 
                                                              nuclear_radius, 
                                                              section_height)
    
    # 4. Print the corrected spot counts
    print(corrected_automatic_counts)
    
    # Write the meaningful results to output files
    write.csv(corrected_automatic_counts, 
              file = "corrected_automatic_counts.csv", 
              row.names = FALSE)
    
    saveRDS(corrected_automatic_counts, 
            file = "corrected_automatic_counts.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_FRENCHFISH_CORRECT_AUTOMATED_COUNTS":
        frenchfish: \$(Rscript -e 'cat(as.character(packageVersion("frenchfish")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_correct_automated_counts.csv versions.yml
    """
}

workflow BIOC_FRENCHFISH_CORRECT_AUTOMATED_COUNTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SampleFISH.jpg_data.csv ] ]

    main:
    BIOC_FRENCHFISH_CORRECT_AUTOMATED_COUNTS(ch_input)

    emit:
    tables   = BIOC_FRENCHFISH_CORRECT_AUTOMATED_COUNTS.out.tables
    plots    = BIOC_FRENCHFISH_CORRECT_AUTOMATED_COUNTS.out.plots
    objects  = BIOC_FRENCHFISH_CORRECT_AUTOMATED_COUNTS.out.objects
    versions = BIOC_FRENCHFISH_CORRECT_AUTOMATED_COUNTS.out.versions
}
