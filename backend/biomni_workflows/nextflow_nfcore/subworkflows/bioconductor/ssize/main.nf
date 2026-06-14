#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ssize — sample_size_calculation
// Calculate and plot the sample size required to achieve a specified power and fold-change for a given proportion of genes.
// Input: control_expression_data.csv
// Container: quay.io/biocontainers/bioconductor-ssize:1.84.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: gdata, ssize, xtable
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and calculate gene-specific standard deviations from control samples
//  * 2. [Core Analysis] Compute the required sample sizes using ssize
//  * 3. [Visualization & Output] Plot the cumulative proportion of genes achieving the target power using ssize.plot

nextflow.enable.dsl = 2

process BIOC_SSIZE_SAMPLE_SIZE_CALCULATION {
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
    .bm_deps <- c("ssize", "xtable", "gdata")
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
        library(ssize)
        library(xtable)
        library(gdata) # for nobs()
        options(width=30)
        
        # 1. Load the package and calculate gene-specific standard deviations from control samples
        input_file <- "control_expression_data.csv"
        if (!file.exists(input_file)) {
          stop(paste("Required input file missing:", input_file))
        }
        
        # Read the control expression matrix (genes as rows, samples as columns)
        # Assumes the data is already normalized and log-transformed (e.g., RMA)
        expr_data <- read.csv(input_file, row.names = 1, check.names = FALSE)
        
        # Calculate gene-specific standard deviations
        exp.sd <- apply(expr_data, 1, sd, na.rm = TRUE)
        
        # Filter out NA or zero standard deviations to ensure stable calculations
        exp.sd <- exp.sd[!is.na(exp.sd) & exp.sd > 0]
        
        # Save the calculated standard deviations to a CSV file
        write.csv(data.frame(Gene = names(exp.sd), SD = exp.sd), 
                  file = "calculated_gene_sd.csv", row.names = FALSE)
        
        # Define parameters
        n <- 6
        fold.change <- 2.0
        power <- 0.8
        sig.level <- 0.05
        
        # 2. Compute the required sample sizes using ssize
        all.size  <- ssize(sd=exp.sd, delta=log2(fold.change),
                           sig.level=sig.level, power=power)
        
        # Save the raw ssize results object
        saveRDS(all.size, file = "ssize_results.rds")
        
        # Save the required sample sizes as a table
        size_df <- data.frame(Gene = names(exp.sd), Required_Sample_Size = as.vector(all.size))
        write.csv(size_df, file = "required_sample_sizes.csv", row.names = FALSE)
        
        # 3. Plot the cumulative proportion of genes achieving the target power using ssize.plot
        pdf("ssize_plot.pdf", width = 7, height = 7)
        par(cex=1)
        ssize.plot(all.size, lwd=2, col="magenta", xlim=c(1,20))
        
        # Add legend and title matching the documented vignette code
        xmax <- par("usr")[2]-1
        ymin <- par("usr")[3] + 0.05
        legend(x=xmax, y=ymin,
               legend= strsplit( paste("fold change=",fold.change,",",
                 "alpha=", sig.level, ",",
                 "power=",power,",",
                 "# genes=", nobs(exp.sd), sep=''), "," )[[1]],
               xjust=1, yjust=0, cex=0.90)
        title("Sample Size to Detect 2-Fold Change")
        dev.off()

    writeLines(c(
        '"BIOC_SSIZE_SAMPLE_SIZE_CALCULATION":',
        paste0('    ssize: ', as.character(packageVersion('ssize')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sample_size_calculation.csv versions.yml
    """
}

workflow BIOC_SSIZE_SAMPLE_SIZE_CALCULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ control_expression_data.csv ] ]

    main:
    BIOC_SSIZE_SAMPLE_SIZE_CALCULATION(ch_input)

    emit:
    tables   = BIOC_SSIZE_SAMPLE_SIZE_CALCULATION.out.tables
    plots    = BIOC_SSIZE_SAMPLE_SIZE_CALCULATION.out.plots
    objects  = BIOC_SSIZE_SAMPLE_SIZE_CALCULATION.out.objects
    versions = BIOC_SSIZE_SAMPLE_SIZE_CALCULATION.out.versions
}
