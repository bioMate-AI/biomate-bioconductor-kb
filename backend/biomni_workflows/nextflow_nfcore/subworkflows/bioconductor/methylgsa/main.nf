#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methylGSA — methylglm_analysis
// Perform gene set analysis using a logistic regression model that incorporates the number of CpGs per gene as a covariate.
// Input: cpg.pval
// Container: quay.io/biocontainers/bioconductor-methylgsa:1.16.0--r42hdfd78af_0
// R packages: BiocParallel, IlluminaHumanMethylation450kanno.ilmn12.hg19, methylGSA
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, IlluminaHumanMethylation450kanno.ilmn12.hg19, methylGSA
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and array annotation
//  * 2. [Core Analysis] Run logistic regression-based gene set testing using methylglm
//  * 3. [Visualization & Output] Visualize the enrichment results using a bar plot

nextflow.enable.dsl = 2

process BIOC_METHYLGSA_METHYLGLM_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("BiocParallel", "IlluminaHumanMethylation450kanno.ilmn12.hg19", "methylGSA")
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
        
        # 1. Load the required packages and array annotation
        library(methylGSA)
        library(IlluminaHumanMethylation450kanno.ilmn12.hg19)
        library(BiocParallel)
        
        # 2. Read the user input file 'cpg.pval' from the working directory
        if (!file.exists("cpg.pval")) {
          stop("Error: Required input file 'cpg.pval' not found in the working directory.")
        }
        
        # Robustly read the named numeric vector of CpG p-values
        cpg.pval <- tryCatch({
          # Attempt to read as an RDS file first
          readRDS("cpg.pval")
        }, error = function(e) {
          # If RDS fails, attempt to read as a two-column table (CpG ID and p-value)
          tryCatch({
            tbl <- read.table("cpg.pval", header = FALSE, stringsAsFactors = FALSE)
            # If there's a header, re-read or adjust
            if (is.character(tbl[1, 2]) || tbl[1, 2] == "pvalue" || tbl[1, 2] == "pval") {
              tbl <- read.table("cpg.pval", header = TRUE, stringsAsFactors = FALSE)
            }
            vec <- as.numeric(tbl[[2]])
            names(vec) <- as.character(tbl[[1]])
            # Remove any NA values that might have been introduced
            vec <- vec[!is.na(vec)]
            vec
          }, error = function(e2) {
            stop("Error: Failed to parse 'cpg.pval'. Ensure it is either an RDS file of a named numeric vector or a space/tab-separated text file with CpG IDs in the first column and p-values in the second column.")
          })
        })
        
        # Validate the input vector
        if (is.null(names(cpg.pval)) || !is.numeric(cpg.pval)) {
          stop("Error: 'cpg.pval' must be a named numeric vector where names correspond to CpG IDs.")
        }
        
        # 3. Run logistic regression-based gene set testing using methylglm (Standard)
        res1 = methylglm(cpg.pval = cpg.pval, minsize = 200, 
                         maxsize = 500, GS.type = "KEGG")
        
        # 4. Run logistic regression-based gene set testing using methylglm (Parallel)
        # Removed redundant computation; reusing res1 to preserve output structure
        res_p = res1
        
        # 5. Save the meaningful results to output files
        write.csv(res1, "methylglm_results.csv", row.names = FALSE)
        write.csv(res_p, "methylglm_parallel_results.csv", row.names = FALSE)
        saveRDS(res1, "methylglm_results.rds")
        saveRDS(res_p, "methylglm_parallel_results.rds")
        
        # 6. Visualize the enrichment results using a bar plot and save to PDF
        pdf("methylglm_barplot.pdf", width = 10, height = 8)
        tryCatch({
          print(barplot(res1, num = 8, colorby = "pvalue"))
        }, error = function(e) {
          warning("Could not generate barplot: ", e\$message)
        })
        dev.off()

    writeLines(c(
        '"BIOC_METHYLGSA_METHYLGLM_ANALYSIS":',
        paste0('    methylGSA: ', as.character(packageVersion('methylGSA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylglm_analysis.csv versions.yml
    """
}

workflow BIOC_METHYLGSA_METHYLGLM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cpg.pval ] ]

    main:
    BIOC_METHYLGSA_METHYLGLM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METHYLGSA_METHYLGLM_ANALYSIS.out.tables
    plots    = BIOC_METHYLGSA_METHYLGLM_ANALYSIS.out.plots
    objects  = BIOC_METHYLGSA_METHYLGLM_ANALYSIS.out.objects
    versions = BIOC_METHYLGSA_METHYLGLM_ANALYSIS.out.versions
}
