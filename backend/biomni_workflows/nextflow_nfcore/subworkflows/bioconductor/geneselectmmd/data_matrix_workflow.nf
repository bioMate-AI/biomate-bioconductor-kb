#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneSelectMMD — data_matrix_workflow
// Select differentially expressed genes and estimate error rates from a raw expression matrix.
// Input: mat
// Container: quay.io/biocontainers/bioconductor-geneselectmmd:2.54.0--r45h63f16b7_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GeneSelectMMD
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare sample membership vector
//  * 2. [Core Analysis] Run gene selection using gsMMD.default
//  * 3. [Core Analysis] Estimate error rates using errRates

nextflow.enable.dsl = 2

process BIOC_GENESELECTMMD_DATA_MATRIX_WORKFLOW {
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
    .bm_deps <- c("GeneSelectMMD")
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
        library(GeneSelectMMD)
        
        # 1. Read user input file 'mat' from the working directory
        # Supports mat.csv, mat.tsv, mat.rds, or a file named 'mat'
        if (file.exists("mat.csv")) {
          mat <- as.matrix(read.csv("mat.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("mat.tsv")) {
          mat <- as.matrix(read.delim("mat.tsv", row.names = 1, check.names = FALSE))
        } else if (file.exists("mat.rds")) {
          mat <- readRDS("mat.rds")
        } else if (file.exists("mat")) {
          mat <- as.matrix(read.csv("mat", row.names = 1, check.names = FALSE))
        } else {
          stop("Error: Input file 'mat' (CSV, TSV, or RDS) not found in the working directory.")
        }
        
        # 2. Prepare sample membership vector (memSubjects)
        # B3/control coded as 0, T2/case coded as 1
        col_names <- colnames(mat)
        memSubjects <- rep(0, ncol(mat))
        
        if (any(grepl("T2", col_names))) {
          memSubjects[grepl("T2", col_names)] <- 1
        } else if (any(grepl("case", col_names, ignore.case = TRUE))) {
          memSubjects[grepl("case", col_names, ignore.case = TRUE)] <- 1
        } else if (any(grepl("group2", col_names, ignore.case = TRUE))) {
          memSubjects[grepl("group2", col_names, ignore.case = TRUE)] <- 1
        } else {
          # Fallback: assume first half is control (0), second half is case (1)
          n <- ncol(mat)
          memSubjects[seq(from = floor(n/2) + 1, to = n)] <- 1
        }
        
        # 3. Run gene selection using gsMMD.default
        obj.gsMMD <- gsMMD.default(mat, memSubjects, iniGeneMethod = "Ttest",
                transformFlag = TRUE, transformMethod = "boxcox", scaleFlag = TRUE,
                quiet=TRUE)
        
        # Extract parameters
        para <- obj.gsMMD\$para
        
        # 4. Estimate error rates using errRates
        errs <- errRates(obj.gsMMD)
        
        # 5. Write outputs
        # Save parameters
        para_df <- data.frame(Parameter = names(para), Value = as.numeric(para))
        write.csv(para_df, "estimated_parameters.csv", row.names = FALSE)
        
        # Save error rates
        errs_df <- data.frame(Error_Rate = names(errs), Value = as.numeric(errs))
        write.csv(errs_df, "estimated_error_rates.csv", row.names = FALSE)
        
        # Save gene selection results
        gene_mem_df <- data.frame(
          Gene = rownames(mat),
          memGenes = obj.gsMMD\$memGenes,
          memGenes2 = obj.gsMMD\$memGenes2
        )
        write.csv(gene_mem_df, "gene_selection_results.csv", row.names = FALSE)
        
        # Save RDS object
        saveRDS(obj.gsMMD, "gsMMD_object.rds")
        
        # 6. Visualizing the fit of the model
        tryCatch({
          pdf("density_plot.pdf")
          plotHistDensity(obj.gsMMD, plotFlag = "case", 
              mytitle = "Histogram of gene expression levels\nimposed with estimated density (case)", 
              plotComponent = TRUE, 
              numPoints = 500,
              cex.main = 1,
              cex = 1)
          dev.off()
        }, error = function(e) {
          warning("Could not generate density plot: ", e\$message)
          if (dev.cur() > 1) dev.off()
        })

    writeLines(c(
        '"BIOC_GENESELECTMMD_DATA_MATRIX_WORKFLOW":',
        paste0('    GeneSelectMMD: ', as.character(packageVersion('GeneSelectMMD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_data_matrix_workflow.csv versions.yml
    """
}

workflow BIOC_GENESELECTMMD_DATA_MATRIX_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mat ] ]

    main:
    BIOC_GENESELECTMMD_DATA_MATRIX_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_GENESELECTMMD_DATA_MATRIX_WORKFLOW.out.tables
    plots    = BIOC_GENESELECTMMD_DATA_MATRIX_WORKFLOW.out.plots
    objects  = BIOC_GENESELECTMMD_DATA_MATRIX_WORKFLOW.out.objects
    versions = BIOC_GENESELECTMMD_DATA_MATRIX_WORKFLOW.out.versions
}
