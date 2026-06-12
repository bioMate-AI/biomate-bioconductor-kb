#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rsubread — read_quality_assessment
// Assess base quality scores of sequencing reads.
// Input: reads.txt.gz
// Container: quay.io/biocontainers/bioconductor-rsubread:2.24.0--r45h01b2380_0
// R packages: Rsubread
// Bioconductor: 3.20 | R: 4.4
// Requires: Rsubread
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Save the full quality scores matrix as a CSV file
//  * 2. [Core Analysis] Save the matrix as an RDS object for downstream R analysis
//  * 3. [Core Analysis] Generate a PDF plot showing the distribution of quality

nextflow.enable.dsl = 2

process BIOC_RSUBREAD_READ_QUALITY_ASSESSMENT {
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
    .bm_deps <- c("Rsubread")
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
    
    # Load the required library
    library(Rsubread)
    
    # Define the input file as specified by the user
    reads <- "reads.txt.gz"
    
    # Verify that the input file exists before proceeding
    if (!file.exists(reads)) {
      stop(paste("Error: Input file", reads, "not found in the working directory."))
    }
    
    # Assess base quality scores using the exact documented function call
    x <- qualityScores(filename=reads,offset=64,nreads=1000)
    
    # Display the first 10 rows and 10 columns as documented
    cat("First 10 rows and 10 columns of quality scores:\n")
    print(x[1:10,1:10])
    
    # Write named output files for the results
    # --- Save the full quality scores matrix as a CSV file ---
    write.csv(x, file="quality_scores.csv", row.names=FALSE)
    
    # --- Save the matrix as an RDS object for downstream R analysis ---
    saveRDS(x, file="quality_scores.rds")
    
    # --- Generate a PDF plot showing the distribution of quality ---
    pdf("quality_scores_distribution.pdf", width=10, height=6)
    boxplot(x, 
            main="Distribution of Base Quality Scores",
            xlab="Base Position", 
            ylab="Phred Quality Score (Offset 64)",
            col="lightblue", 
            border="darkblue",
            las=1)
    dev.off()
    
    cat("Quality assessment completed successfully. Outputs saved to 'quality_scores.csv', 'quality_scores.rds', and 'quality_scores_distribution.pdf'.\n")

    writeLines(c(
        '"BIOC_RSUBREAD_READ_QUALITY_ASSESSMENT":',
        paste0('    Rsubread: ', as.character(packageVersion('Rsubread')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_read_quality_assessment.csv versions.yml
    """
}

workflow BIOC_RSUBREAD_READ_QUALITY_ASSESSMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reads.txt.gz ] ]

    main:
    BIOC_RSUBREAD_READ_QUALITY_ASSESSMENT(ch_input)

    emit:
    tables   = BIOC_RSUBREAD_READ_QUALITY_ASSESSMENT.out.tables
    plots    = BIOC_RSUBREAD_READ_QUALITY_ASSESSMENT.out.plots
    objects  = BIOC_RSUBREAD_READ_QUALITY_ASSESSMENT.out.objects
    versions = BIOC_RSUBREAD_READ_QUALITY_ASSESSMENT.out.versions
}
