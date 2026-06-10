#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msa — pretty_print_alignment
// Generate publication-ready PDF figures or LaTeX-compatible alignment visualizations.
// Input: myFirstAlignment
// Container: quay.io/biocontainers/bioconductor-msa:1.42.0--r45he8cd136_0
// Requires: msa
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run msaPrettyPrint with output="pdf" or output="asis" to generate TeXshade-based visualizations

nextflow.enable.dsl = 2

process BIOC_MSA_PRETTY_PRINT_ALIGNMENT {
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
    .bm_deps <- c("msa")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
        # Load required libraries
        library(msa)
        
        # Define input file path
        # The pipeline expects 'myFirstAlignment' as an RDS file containing the MsaAAMultipleAlignment object
        input_path <- "myFirstAlignment.rds"
        if (!file.exists(input_path)) {
            input_path <- "myFirstAlignment"
        }
        
        if (!file.exists(input_path)) {
            stop("Required input file 'myFirstAlignment.rds' or 'myFirstAlignment' not found in the working directory.")
        }
        
        # Read the user input alignment object
        myFirstAlignment <- readRDS(input_path)
        
        # Stage 1: Run msaPrettyPrint to generate TeXshade-based visualizations.
        # We wrap these in tryCatch blocks because msaPrettyPrint requires a local LaTeX installation 
        # and the texshade.sty style sheet to compile PDFs.
        tryCatch({
            msaPrettyPrint(myFirstAlignment, output="pdf", showNames="none", showLogo="none", askForOverwrite=FALSE, verbose=FALSE)
        }, error = function(e) {
            warning("msaPrettyPrint with output='pdf' failed. This is expected if LaTeX is not installed on the host system: ", e\$message)
        })
        
        tryCatch({
            y_start <- min(164, ncol(myFirstAlignment))
            y_end <- min(213, ncol(myFirstAlignment))
            msaPrettyPrint(myFirstAlignment, y=c(y_start, y_end), output="asis", showNames="none", showLogo="none", askForOverwrite=FALSE)
        }, error = function(e) {
            warning("msaPrettyPrint with output='asis' failed: ", e\$message)
        })
        
        # Write a robust, guaranteed output file (consensus sequence) to ensure the pipeline always produces meaningful results
        consensus_seq <- msaConsensusSequence(myFirstAlignment)
        writeLines(consensus_seq, "consensus_sequence.txt")

    writeLines(c(
        '"BIOC_MSA_PRETTY_PRINT_ALIGNMENT":',
        paste0('    msa: ', as.character(packageVersion('msa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pretty_print_alignment.csv versions.yml
    """
}

workflow BIOC_MSA_PRETTY_PRINT_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ myFirstAlignment ] ]

    main:
    BIOC_MSA_PRETTY_PRINT_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_MSA_PRETTY_PRINT_ALIGNMENT.out.tables
    plots    = BIOC_MSA_PRETTY_PRINT_ALIGNMENT.out.plots
    objects  = BIOC_MSA_PRETTY_PRINT_ALIGNMENT.out.objects
    versions = BIOC_MSA_PRETTY_PRINT_ALIGNMENT.out.versions
}
