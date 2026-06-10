#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: river — river_evaluation
// Evaluate the predictive accuracy of the RIVER model compared to a genomic-only model (GAM) using held-out N2 pairs.
// Input: simulation_RIVER.gz
// Container: quay.io/biocontainers/bioconductor-river:1.34.0--r45hdfd78af_0
// R packages: devtools, RIVER
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIVER_RIVER_EVALUATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-river:1.34.0--r45hdfd78af_0"

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
    .bm_deps <- c("devtools", "RIVER")
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
    library("RIVER")
    
    # Define input file path (must be in the working directory)
    input_file <- "simulation_RIVER.gz"
    
    # Check if the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Required input file '", input_file, "' not found in the working directory.", sep=""))
    }
    
    # 1. Import experimental data using getData
    message("Importing experimental data...")
    dataInput <- getData(input_file)
    
    # 2. Run evaluation using evaRIVER with specified hyperparameters
    message("Running RIVER evaluation...")
    evaROC <- evaRIVER(dataInput, 
                       pseudoc=50, 
                       theta_init=matrix(c(.99, .01, .3, .7), nrow=2), 
                       costs=c(100, 10, 1, .1, .01, 1e-3, 1e-4), 
                       verbose=TRUE)
    
    # 3. Extract and compare AUC values for GAM and RIVER
    message("Evaluation complete. Results:")
    cat('AUC (GAM-genomic annotation model) = ', round(evaROC\$GAM_auc,3), '\n')
    cat('AUC (RIVER) = ', round(evaROC\$RIVER_auc,3), '\n')
    cat('P-value ', format.pval(evaROC\$pvalue, digits=2, eps=0.001), '***\n')
    
    # 4. Write named output files for the meaningful results
    
    # Save evaluation metrics as a CSV table
    metrics_df <- data.frame(
      Model = c("GAM", "RIVER"),
      AUC = c(evaROC\$GAM_auc, evaROC\$RIVER_auc),
      P_value = c(NA, evaROC\$pvalue)
    )
    write.csv(metrics_df, "river_evaluation_metrics.csv", row.names=FALSE)
    message("Saved evaluation metrics to 'river_evaluation_metrics.csv'")
    
    # Save the complete evaluation object as an RDS file
    saveRDS(evaROC, file="evaROC.rds")
    message("Saved evaluation object to 'evaROC.rds'")
    
    # Generate and save the ROC plot as a PDF
    pdf("roc_curve.pdf", width=6, height=6)
    par(mar=c(6.1, 6.1, 4.1, 4.1))
    plot(NULL, xlim=c(0,1), ylim=c(0,1), 
         xlab="False positive rate", ylab="True positive rate", 
         cex.axis=1.3, cex.lab=1.6)
    abline(0, 1, col="gray")
    lines(1-evaROC\$RIVER_spec, evaROC\$RIVER_sens, 
          type="s", col='dodgerblue', lwd=2)
    lines(1-evaROC\$GAM_spec, evaROC\$GAM_sens, 
          type="s", col='mediumpurple', lwd=2)
    legend(0.7,0.2,c("RIVER","GAM"), lty=c(1,1), lwd=c(2,2),
           col=c("dodgerblue","mediumpurple"), cex=1.2, 
           pt.cex=1.2, bty="n")
    title(main=paste("AUC: RIVER = ", round(evaROC\$RIVER_auc,3), 
                     ", GAM = ", round(evaROC\$GAM_auc,3), 
                     ", P = ", format.pval(evaROC\$pvalue, digits=2, 
                                           eps=0.001),sep=""))
    dev.off()
    message("Saved ROC curve plot to 'roc_curve.pdf'")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RIVER_RIVER_EVALUATION":
        river: \$(Rscript -e 'cat(as.character(packageVersion("river")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_river_evaluation.csv versions.yml
    """
}

workflow BIOC_RIVER_RIVER_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ simulation_RIVER.gz ] ]

    main:
    BIOC_RIVER_RIVER_EVALUATION(ch_input)

    emit:
    tables   = BIOC_RIVER_RIVER_EVALUATION.out.tables
    plots    = BIOC_RIVER_RIVER_EVALUATION.out.plots
    objects  = BIOC_RIVER_RIVER_EVALUATION.out.objects
    versions = BIOC_RIVER_RIVER_EVALUATION.out.versions
}
