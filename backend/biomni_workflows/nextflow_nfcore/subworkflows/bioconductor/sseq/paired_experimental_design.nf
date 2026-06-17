#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sSeq — paired_experimental_design
// Perform differential expression analysis for paired experimental designs (e.g., tumor vs. normal tissue from the same patients).
// Input: countsTable, conds2, coLevels
// Container: quay.io/biocontainers/bioconductor-sseq:1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: sSeq
// Visualizations: volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and paired dataset
//  * 2. [Input & Preparation] Define the conditions and the pairing structure using a data frame
//  * 3. [Core Analysis] Run the exact test with pairedDesign=TRUE and pairedDesign.dispMethod="pooled"
//  * 4. [Core Analysis] Inspect the top differentially expressed genes

nextflow.enable.dsl = 2

process BIOC_SSEQ_PAIRED_EXPERIMENTAL_DESIGN {
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
    .bm_deps <- c("sSeq")
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
        
        # 1. Load the package and paired dataset
        library(sSeq)
        
        # Read countsTable from the working directory (supports RDS, CSV, or TSV)
        if (file.exists("countsTable.rds")) {
          countsTable <- readRDS("countsTable.rds")
        } else if (file.exists("countsTable.csv")) {
          countsTable <- read.csv("countsTable.csv", row.names = 1, check.names = FALSE)
          countsTable <- as.matrix(countsTable)
        } else if (file.exists("countsTable.tsv")) {
          countsTable <- read.delim("countsTable.tsv", row.names = 1, check.names = FALSE)
          countsTable <- as.matrix(countsTable)
        } else {
          stop("Error: countsTable file (RDS, CSV, or TSV) not found in the working directory.")
        }
        
        # 2. Define the conditions and the pairing structure using a data frame
        # Read conds2 from the working directory (supports RDS, CSV, or TXT)
        if (file.exists("conds2.rds")) {
          conds2 <- readRDS("conds2.rds")
        } else if (file.exists("conds2.csv")) {
          conds2_df <- read.csv("conds2.csv", header = FALSE)
          conds2 <- as.character(conds2_df[[1]])
        } else if (file.exists("conds2.txt")) {
          conds2 <- readLines("conds2.txt")
        } else {
          stop("Error: conds2 file (RDS, CSV, or TXT) not found in the working directory.")
        }
        
        # Read coLevels from the working directory (supports RDS, CSV, or TSV)
        if (file.exists("coLevels.rds")) {
          coLevels <- readRDS("coLevels.rds")
        } else if (file.exists("coLevels.csv")) {
          coLevels <- read.csv("coLevels.csv", check.names = FALSE)
        } else if (file.exists("coLevels.tsv")) {
          coLevels <- read.delim("coLevels.tsv", check.names = FALSE)
        } else {
          stop("Error: coLevels file (RDS, CSV, or TSV) not found in the working directory.")
        }
        
        # Extract unique conditions from the conds2 vector
        unique_conds <- unique(conds2)
        condA <- unique_conds[1]
        condB <- unique_conds[2]
        
        # 3. Run the exact test with pairedDesign=TRUE and pairedDesign.dispMethod="pooled"
        res2 = nbTestSH(countsTable, conds2, condA, condB, 
           coLevels= coLevels, pairedDesign=TRUE, pairedDesign.dispMethod="pooled");
        
        # 4. Inspect the top differentially expressed genes
        head(res2)
        top25 <- countsTable[order(res2\$pval),][1:25,]
        print(top25)
        
        # Write named output files for the meaningful results
        write.csv(res2, "res2_results.csv", row.names = TRUE)
        saveRDS(res2, "res2_results.rds")
        write.csv(top25, "top25_paired_genes.csv", row.names = TRUE)
        
        # Generate diagnostic plots if possible
        tryCatch({
          pdf("MA_volcano_plot_paired.pdf", width = 10, height = 5)
          drawMA_vol(countsTable, conds2, res2\$pval, cutoff = 0.05)
          dev.off()
        }, error = function(e) {
          warning("Could not generate MA/Volcano plot: ", e\$message)
        })

    writeLines(c(
        '"BIOC_SSEQ_PAIRED_EXPERIMENTAL_DESIGN":',
        paste0('    sSeq: ', as.character(packageVersion('sSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paired_experimental_design.csv versions.yml
    """
}

workflow BIOC_SSEQ_PAIRED_EXPERIMENTAL_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ countsTable, conds2, coLevels ] ]

    main:
    BIOC_SSEQ_PAIRED_EXPERIMENTAL_DESIGN(ch_input)

    emit:
    tables   = BIOC_SSEQ_PAIRED_EXPERIMENTAL_DESIGN.out.tables
    plots    = BIOC_SSEQ_PAIRED_EXPERIMENTAL_DESIGN.out.plots
    objects  = BIOC_SSEQ_PAIRED_EXPERIMENTAL_DESIGN.out.objects
    versions = BIOC_SSEQ_PAIRED_EXPERIMENTAL_DESIGN.out.versions
}
