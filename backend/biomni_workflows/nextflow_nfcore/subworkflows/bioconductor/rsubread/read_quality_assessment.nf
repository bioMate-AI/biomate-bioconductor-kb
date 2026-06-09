#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rsubread — read_quality_assessment
// Assess base quality scores of sequencing reads.
// Input: reads.txt.gz
// Container: quay.io/biocontainers/bioconductor-rsubread:2.24.0--r45h01b2380_0
// Requires: Rsubread
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract and display quality scores using qualityScores

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
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
    # 1. Save the full quality scores matrix as a CSV file
    write.csv(x, file="quality_scores.csv", row.names=FALSE)
    
    # 2. Save the matrix as an RDS object for downstream R analysis
    saveRDS(x, file="quality_scores.rds")
    
    # 3. Generate a PDF plot showing the distribution of quality scores per base position
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
