#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rnamodr_ribomethseq — ribomethseq_analysis
// Detect and quantify 2'-O-methylations (Nm) from RiboMethSeq BAM files using the RNAmodR framework.
// Input: alignments.bam, annotation.gff3, reference.fasta
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RNAmodR.RiboMethSeq, rnamodr_ribomethseq, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and define input file paths
//  * 2. [Input & Preparation] Construct a ModSetRiboMethSeq object to process the BAM files against the reference genome and annotations
//  * 3. [Core Analysis] Detect modifications using the detectModifications function
//  * 4. [Visualization & Output] Plot data for a specific gene/transcript using plotData

nextflow.enable.dsl = 2

process BIOC_RNAMODR_RIBOMETHSEQ_RIBOMETHSEQ_ANALYSIS {
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
    .bm_deps <- c("RNAmodR.RiboMethSeq", "rtracklayer")
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
            library(RNAmodR.RiboMethSeq)
            
            # Define input file paths from the working directory
            files <- c(replicate1 = "alignments.bam")
            annotation <- "annotation.gff3"
            sequences <- "reference.fasta"
            
            # Construct ModSetRiboMethSeq object
            msr <- ModSetRiboMethSeq(files, annotation = annotation, sequences = sequences)
            
            # Detect modifications
            modifications <- modifications(msr)
            
            # Save the main outputs
            saveRDS(msr, "modset_ribomethseq.rds")
            saveRDS(modifications, "detected_modifications.rds")
            
            # Attempt to export modifications to a CSV file
            tryCatch({
              df_mods <- as.data.frame(modifications)
              write.csv(df_mods, "detected_modifications.csv", row.names = FALSE)
            }, error = function(e) {
              message("Could not export modifications to CSV: ", e\$message)
            })
            
            # Determine a valid transcript/sequence name for plotting
            plot_name <- "transcript_id"
            tryCatch({
              if (length(modifications) > 0) {
                plot_name <- names(modifications)[1]
              }
            }, error = function(e) {
              tryCatch({
                library(rtracklayer)
                gff <- rtracklayer::import(annotation)
                plot_name <- gff\$ID[1]
              }, error = function(e2) {})
            })
            
            # Plot data for the identified transcript/sequence
            pdf("ribomethseq_plot.pdf")
            tryCatch({
              print(plotData(msr, name = plot_name))
            }, error = function(e) {
              message("Could not generate plot: ", e\$message)
            })
            dev.off()

    writeLines(c(
        '"BIOC_RNAMODR_RIBOMETHSEQ_RIBOMETHSEQ_ANALYSIS":',
        paste0('    rnamodr_ribomethseq: ', as.character(packageVersion('rnamodr_ribomethseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ribomethseq_analysis.csv versions.yml
    """
}

workflow BIOC_RNAMODR_RIBOMETHSEQ_RIBOMETHSEQ_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ alignments.bam, annotation.gff3, reference.fasta ] ]

    main:
    BIOC_RNAMODR_RIBOMETHSEQ_RIBOMETHSEQ_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RNAMODR_RIBOMETHSEQ_RIBOMETHSEQ_ANALYSIS.out.tables
    plots    = BIOC_RNAMODR_RIBOMETHSEQ_RIBOMETHSEQ_ANALYSIS.out.plots
    objects  = BIOC_RNAMODR_RIBOMETHSEQ_RIBOMETHSEQ_ANALYSIS.out.objects
    versions = BIOC_RNAMODR_RIBOMETHSEQ_RIBOMETHSEQ_ANALYSIS.out.versions
}
