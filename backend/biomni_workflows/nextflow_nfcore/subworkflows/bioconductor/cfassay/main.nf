#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CFAssay — lq_survival_curve_analysis
// Fit linear-quadratic cell survival curves to colony formation assay data, evaluate goodness-of-fit, and compare curves between different experimental groups.
// Input: cellsurv_data.txt
// Container: quay.io/biocontainers/bioconductor-cfassay:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CFAssay
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and inspect the data
//  * 2. [Core Analysis] Fit the LQ model for a single cell line/group
//  * 3. [Core Analysis] Print fit coefficients and calculate mean survival fractions
//  * 4. [Visualization & Output] Generate diagnostic plots for individual experiments
//  * 5. [Core Analysis] Compare two survival curves statistically
//  * 6. [Visualization & Output] Plot the compared curves together

nextflow.enable.dsl = 2

process BIOC_CFASSAY_LQ_SURVIVAL_CURVE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("CFAssay")
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
    library(CFAssay)
    
    # 1. Load and inspect the data
    datatab <- read.table("cellsurv_data.txt", header=TRUE, sep="\t")
    names(datatab)
    head(datatab, 3)
    
    # Extract unique cell lines from the data
    clines <- unique(as.character(datatab\$cline))
    cline1 <- clines[1]
    cline2 <- clines[2]
    
    # 2. Fit the LQ model for a single cell line/group
    X <- subset(datatab, cline==cline1)
    dim(X)
    fit <- cellsurvLQfit(X)
    
    # 3. Print fit coefficients and calculate mean survival fractions
    # Save printed fit to a text file
    sink(paste0("fit_", cline1, "_summary.txt"))
    print(fit)
    sink()
    
    # Print to console
    print(fit)
    
    # Generate mean survival curve plot
    pdf(paste0(cline1, "_mean_fit_plot.pdf"))
    plot(fit)
    dev.off()
    
    S0 <- pes(X)\$S0
    names(S0) <- pes(X)\$Exp
    sf_mean <- sfpmean(X, S0)
    write.csv(sf_mean, paste0(cline1, "_sfpmean.csv"), row.names=TRUE)
    
    # 4. Generate diagnostic plots for individual experiments
    pdf(paste0(cline1, "_experimental_plots.pdf"))
    plotExp(fit)
    dev.off()
    
    # 5. Compare two survival curves statistically
    fitcomp <- cellsurvLQdiff(datatab, curvevar="cline")
    
    # Save printed comparison to a text file
    sink("fitcomp_summary.txt")
    print(fitcomp)
    sink()
    
    # Print to console
    print(fitcomp)
    
    # 6. Plot the compared curves together
    pdf("compared_curves_plot.pdf")
    plot(cellsurvLQfit(subset(datatab, cline==cline1)), col=1)
    plot(cellsurvLQfit(subset(datatab, cline==cline2)), col=2, add=TRUE)
    legend(0, 0.02, c(cline1, cline2), text.col=1:2)
    dev.off()
    
    # Save RDS objects for downstream analysis
    saveRDS(fit, paste0("fit_", cline1, ".rds"))
    saveRDS(fitcomp, "fitcomp.rds")

    writeLines(c(
        '"BIOC_CFASSAY_LQ_SURVIVAL_CURVE_ANALYSIS":',
        paste0('    CFAssay: ', as.character(packageVersion('CFAssay')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lq_survival_curve_analysis.csv versions.yml
    """
}

workflow BIOC_CFASSAY_LQ_SURVIVAL_CURVE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cellsurv_data.txt ] ]

    main:
    BIOC_CFASSAY_LQ_SURVIVAL_CURVE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CFASSAY_LQ_SURVIVAL_CURVE_ANALYSIS.out.tables
    plots    = BIOC_CFASSAY_LQ_SURVIVAL_CURVE_ANALYSIS.out.plots
    objects  = BIOC_CFASSAY_LQ_SURVIVAL_CURVE_ANALYSIS.out.objects
    versions = BIOC_CFASSAY_LQ_SURVIVAL_CURVE_ANALYSIS.out.versions
}
