#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epialleler — methylation_calling_unannotated_bams
// Call cytosine methylation and add XG/XM tags to BAM files lacking them (e.g., from bwa-meth or BSMAP).
// Input: input.bam, reference.fasta.gz
// Container: quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0
// R packages: epialleleR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIALLELER_METHYLATION_CALLING_UNANNOTATED_BAMS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0"

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
    .bm_deps <- c("epialleleR")
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
    library(epialleleR)
    
    # Define input files from the working directory
    input_file <- "input.bam"
    reference_file <- "reference.fasta.gz"
    
    # Define output files
    output_file <- "output.bam"
    stats_file <- "calling_statistics.rds"
    report_file <- "methylation_report.csv"
    
    # 1. Preprocess reference genome using preprocessGenome
    message("Preprocessing reference genome...")
    genome <- preprocessGenome(reference_file)
    
    # 2. Call methylation and write to a new BAM file using callMethylation
    message("Calling methylation and writing to output BAM...")
    calling_stats <- callMethylation(input_file, output_file, genome)
    
    # Save the calling statistics
    saveRDS(calling_stats, file = stats_file)
    
    # 3. Generate a downstream cytosine report to produce meaningful tabular output
    message("Generating cytosine methylation report...")
    bam_data <- preprocessBam(output_file)
    report <- generateCytosineReport(bam_data, threshold.reads = FALSE)
    
    # Write the report to a CSV file
    write.csv(report, file = report_file, row.names = FALSE)
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_EPIALLELER_METHYLATION_CALLING_UNANNOTATED_BAMS":',
        paste0('        epialleler: ', as.character(packageVersion("epialleler")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylation_calling_unannotated_bams.csv versions.yml
    """
}

workflow BIOC_EPIALLELER_METHYLATION_CALLING_UNANNOTATED_BAMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input.bam, reference.fasta.gz ] ]

    main:
    BIOC_EPIALLELER_METHYLATION_CALLING_UNANNOTATED_BAMS(ch_input)

    emit:
    tables   = BIOC_EPIALLELER_METHYLATION_CALLING_UNANNOTATED_BAMS.out.tables
    plots    = BIOC_EPIALLELER_METHYLATION_CALLING_UNANNOTATED_BAMS.out.plots
    objects  = BIOC_EPIALLELER_METHYLATION_CALLING_UNANNOTATED_BAMS.out.objects
    versions = BIOC_EPIALLELER_METHYLATION_CALLING_UNANNOTATED_BAMS.out.versions
}
