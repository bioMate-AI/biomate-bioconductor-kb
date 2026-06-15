#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MBQN — mbqn_normalization_workflow
// Detect rank-invariant features and apply mean/median-balanced quantile normalization to a distorted intensity matrix.
// Input: mtx
// Container: quay.io/biocontainers/bioconductor-mbqn:2.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MBQN
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Detect rank-invariant (RI) or nearly rank-invariant (NRI)
//  * 2. [Visualization & Output] Perform classical quantile normalization, full MBQN, or
//  * 3. [Visualization & Output] Visualize and compare the normalized intensities

nextflow.enable.dsl = 2

process BIOC_MBQN_MBQN_NORMALIZATION_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("MBQN")
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
        library("MBQN")
        
        # Read the user input matrix 'mtx' from the working directory
        if (file.exists("mtx")) {
          mtx <- tryCatch({
            as.matrix(read.csv("mtx", row.names = 1, check.names = FALSE))
          }, error = function(e) {
            as.matrix(read.table("mtx", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE))
          })
        } else if (file.exists("mtx.csv")) {
          mtx <- as.matrix(read.csv("mtx.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("mtx.tsv")) {
          mtx <- as.matrix(read.table("mtx.tsv", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE))
        } else {
          stop("Input file 'mtx' (or mtx.csv/mtx.tsv) not found in the working directory.")
        }
        
        # Ensure the matrix is numeric
        if (!is.numeric(mtx)) {
          mode(mtx) <- "numeric"
        }
        
        # --- Detect rank-invariant (RI) or nearly rank-invariant (NRI) ---
        res <- mbqnGetNRIfeatures(mtx, low_thr = 0.5)
        
        # --- Perform classical quantile normalization, full MBQN, or ---
        mbqn.mtx <- mbqnNRI(x = mtx, FUN = median, verbose = FALSE)
        qn.mtx <- mbqnNRI(x = mtx, FUN = NULL, verbose = FALSE)
        
        # --- Visualize and compare the normalized intensities ---
        # We save the boxplot to a PDF file
        pdf("mbqn_boxplot.pdf", width = 7, height = 6)
        plot.new()
        # If no NRI features are found, we handle it gracefully to avoid plotting errors
        if (!is.null(res\$ip) && length(res\$ip) > 0) {
          mbqnBoxplot(mbqn.mtx, irow = res\$ip[1], vals = data.frame(QN = qn.mtx[res\$ip[1],]), main = "Normalized")
        } else {
          warning("No NRI features detected with low_thr = 0.5. Boxplot not generated.")
        }
        dev.off()
        
        # Additional normalization runs as documented
        qn.mtx <- mbqn(mtx,FUN=NULL, verbose = FALSE)
        mbqn.mtx <- mbqn(mtx,FUN = "median", verbose = FALSE)
        qn.nri.mtx <- mbqnNRI(mtx,FUN = "median", low_thr = 0.5, verbose = FALSE)
        
        # Save meaningful results to output files
        write.csv(as.data.frame(qn.mtx), "qn_matrix.csv", row.names = TRUE)
        write.csv(as.data.frame(mbqn.mtx), "mbqn_matrix.csv", row.names = TRUE)
        write.csv(as.data.frame(qn.nri.mtx), "qn_nri_matrix.csv", row.names = TRUE)
        
        # Save detected NRI features information
        if (!is.null(res\$ip) && length(res\$ip) > 0) {
          nri_df <- data.frame(
            Feature_Index = res\$ip,
            Feature_Name = rownames(mtx)[res\$ip]
          )
          write.csv(nri_df, "nri_features.csv", row.names = FALSE)
        } else {
          write.csv(data.frame(Message = "No NRI features detected"), "nri_features.csv", row.names = FALSE)
        }
        
        message("MBQN normalization workflow completed successfully.")

    writeLines(c(
        '"BIOC_MBQN_MBQN_NORMALIZATION_WORKFLOW":',
        paste0('    MBQN: ', as.character(packageVersion('MBQN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mbqn_normalization_workflow.csv versions.yml
    """
}

workflow BIOC_MBQN_MBQN_NORMALIZATION_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mtx ] ]

    main:
    BIOC_MBQN_MBQN_NORMALIZATION_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MBQN_MBQN_NORMALIZATION_WORKFLOW.out.tables
    plots    = BIOC_MBQN_MBQN_NORMALIZATION_WORKFLOW.out.plots
    objects  = BIOC_MBQN_MBQN_NORMALIZATION_WORKFLOW.out.objects
    versions = BIOC_MBQN_MBQN_NORMALIZATION_WORKFLOW.out.versions
}
