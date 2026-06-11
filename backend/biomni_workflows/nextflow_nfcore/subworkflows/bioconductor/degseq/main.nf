#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: degseq — deg_analysis_from_matrices
// Identify differentially expressed genes from pre-calculated gene expression matrices using MA-plot-based methods (MARS or MATR).
// Input: GeneExpExample5000.txt
// Container: quay.io/biocontainers/bioconductor-degseq:1.64.0--r45ha27e39d_0
// R packages: DEGseq
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEGSEQ_DEG_ANALYSIS_FROM_MATRICES {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-degseq:1.64.0--r45ha27e39d_0"

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
    .bm_deps <- c("DEGseq")
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
    
    # Check for the required user input file in the working directory
    input_file <- "GeneExpExample5000.txt"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the current working directory."))
    }
    
    # Load the DEGseq library
    library(DEGseq)
    
    # 1. Read gene expression data from file into R matrices using readGeneExp
    geneExpFile <- input_file
    geneExpMatrix1 <- readGeneExp(file=geneExpFile, geneCol=1, valCol=c(7,9,12,15,18))
    geneExpMatrix2 <- readGeneExp(file=geneExpFile, geneCol=1, valCol=c(8,10,11,13,16))
    
    # Print subset of matrices as documented
    write.table(geneExpMatrix1[30:31,], row.names=FALSE)
    write.table(geneExpMatrix2[30:31,], row.names=FALSE)
    
    # Save the processed expression matrices to CSV and RDS files
    write.csv(geneExpMatrix1, "geneExpMatrix1.csv", row.names=FALSE)
    write.csv(geneExpMatrix2, "geneExpMatrix2.csv", row.names=FALSE)
    saveRDS(geneExpMatrix1, "geneExpMatrix1.rds")
    saveRDS(geneExpMatrix2, "geneExpMatrix2.rds")
    
    # Open a PDF device to capture the generated plots
    pdf("DEGseq_analysis_plots.pdf", width=10, height=12)
    
    # 2. Run differential expression analysis using DEGexp with the MARS method
    layout(matrix(c(1,2,3,4,5,6), 3, 2, byrow=TRUE))
    par(mar=c(2, 2, 2, 2))
    DEGexp(geneExpMatrix1=geneExpMatrix1, geneCol1=1, expCol1=c(2,3,4,5,6), groupLabel1="kidney",
           geneExpMatrix2=geneExpMatrix2, geneCol2=1, expCol2=c(2,3,4,5,6), groupLabel2="liver",
           method="MARS")
    
    # 3. Run differential expression analysis using DEGexp with the MATR method
    layout(matrix(c(1,2,3,4,5,6), 3, 2, byrow=TRUE))
    par(mar=c(2, 2, 2, 2))
    DEGexp(geneExpMatrix1=geneExpMatrix1, expCol1=2, groupLabel1="kidneyR1L1", 
           geneExpMatrix2=geneExpMatrix2, expCol2=2, groupLabel2="liverR1L2",
           replicateExpMatrix1=geneExpMatrix1, expColR1=3, replicateLabel1="kidneyR1L3", 
           replicateExpMatrix2=geneExpMatrix1, expColR2=4, replicateLabel2="kidneyR1L7",
           method="MATR")
    
    # Close the PDF device
    dev.off()

    writeLines(c(
        '"BIOC_DEGSEQ_DEG_ANALYSIS_FROM_MATRICES":',
        paste0('        degseq: ', as.character(packageVersion("degseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deg_analysis_from_matrices.csv versions.yml
    """
}

workflow BIOC_DEGSEQ_DEG_ANALYSIS_FROM_MATRICES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GeneExpExample5000.txt ] ]

    main:
    BIOC_DEGSEQ_DEG_ANALYSIS_FROM_MATRICES(ch_input)

    emit:
    tables   = BIOC_DEGSEQ_DEG_ANALYSIS_FROM_MATRICES.out.tables
    plots    = BIOC_DEGSEQ_DEG_ANALYSIS_FROM_MATRICES.out.plots
    objects  = BIOC_DEGSEQ_DEG_ANALYSIS_FROM_MATRICES.out.objects
    versions = BIOC_DEGSEQ_DEG_ANALYSIS_FROM_MATRICES.out.versions
}
