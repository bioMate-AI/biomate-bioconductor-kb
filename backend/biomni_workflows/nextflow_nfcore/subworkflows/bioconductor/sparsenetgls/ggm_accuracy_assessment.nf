#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sparsenetgls — ggm_accuracy_assessment
// Assess the prediction accuracy of an estimated Gaussian Graphical Model (GGM) against a known true precision matrix.
// Input: databand_Y, databand_X, prec
// Container: quay.io/biocontainers/bioconductor-sparsenetgls:1.28.0--r45hdfd78af_0
// Requires: Matrix, sparsenetgls
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate precision matrices across a lambda path using sparsenetgls()
//  * 2. [Core Analysis] Format the estimated precision matrices into a 3D array
//  * 3. [Core Analysis] Calculate sensitivity, specificity, NPV, and PPV using path_result_for_roc()
//  * 4. [Visualization & Output] Plot the ROC curve using plot_roc()

nextflow.enable.dsl = 2

process BIOC_SPARSENETGLS_GGM_ACCURACY_ASSESSMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    
    # Load required libraries
    library(sparsenetgls)
    library(Matrix)
    library(MASS)
    
    # Helper function to find and read input files robustly
    find_and_read <- function(base_name) {
      possible_files <- c(
        base_name,
        paste0(base_name, ".rds"),
        paste0(base_name, ".csv"),
        paste0(base_name, ".tsv"),
        paste0(base_name, ".txt")
      )
      for (f in possible_files) {
        if (file.exists(f)) {
          if (grepl("\\\\.rds\$", f, ignore.case = TRUE)) {
            return(as.matrix(readRDS(f)))
          }
          df <- tryCatch({
            first_line <- readLines(f, n = 1)
            sep <- if (grepl("\t", first_line)) "\t" else ","
            tmp <- read.csv(f, sep = sep, check.names = FALSE)
            if (nrow(tmp) > 0 && !is.numeric(tmp[[1]])) {
              rownames(tmp) <- tmp[[1]]
              tmp <- tmp[-1]
            }
            as.matrix(tmp)
          }, error = function(e) NULL)
          if (!is.null(df)) return(df)
        }
      }
      stop(paste("Error: Could not find or read input file for", base_name))
    }
    
    # 1. Read the declared user input files
    databand_Y <- find_and_read("databand_Y")
    databand_X <- find_and_read("databand_X")
    prec <- find_and_read("prec")
    
    # 2. Estimate precision matrices across a lambda path using sparsenetgls()
    omega <- sparsenetgls(responsedata=databand_Y, predictdata=databand_X, 
    nlambda=10, ndist=1, method="glasso")\$PREC_seq
    
    # 3. Format the estimated precision matrices into a 3D array
    p <- ncol(databand_Y)
    omega_est <- array(dim=c(p,p,10))
    for (i in seq_len(10)) omega_est[,,i] <- as.matrix(omega[[i]])
    
    # 4. Calculate sensitivity, specificity, NPV, and PPV using path_result_for_roc()
    roc_path_result <- path_result_for_roc(PREC_for_graph=prec, OMEGA_path=omega_est
    , pathnumber=10)
    
    # Save the ROC path result as RDS
    saveRDS(roc_path_result, "roc_path_result.rds")
    
    # Save the ROC path result as a CSV table
    roc_df <- data.frame(
      sensitivity = roc_path_result\$sensitivity,
      specificity = roc_path_result\$specificity,
      NPV = roc_path_result\$NPV,
      PPV = roc_path_result\$PPV
    )
    write.csv(roc_df, "roc_path_result.csv", row.names = FALSE)
    
    # 5. Plot the ROC curve using plot_roc() and save to PDF
    pdf("roc_plot.pdf", width=7, height=7)
    plot_roc(result_assessment=roc_path_result, group=FALSE, ngroup=0,
    est_names="glasso estimation")
    dev.off()

    writeLines(c(
        '"BIOC_SPARSENETGLS_GGM_ACCURACY_ASSESSMENT":',
        paste0('    sparsenetgls: ', as.character(packageVersion('sparsenetgls')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggm_accuracy_assessment.csv versions.yml
    """
}

workflow BIOC_SPARSENETGLS_GGM_ACCURACY_ASSESSMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ databand_Y, databand_X, prec ] ]

    main:
    BIOC_SPARSENETGLS_GGM_ACCURACY_ASSESSMENT(ch_input)

    emit:
    tables   = BIOC_SPARSENETGLS_GGM_ACCURACY_ASSESSMENT.out.tables
    plots    = BIOC_SPARSENETGLS_GGM_ACCURACY_ASSESSMENT.out.plots
    objects  = BIOC_SPARSENETGLS_GGM_ACCURACY_ASSESSMENT.out.objects
    versions = BIOC_SPARSENETGLS_GGM_ACCURACY_ASSESSMENT.out.versions
}
