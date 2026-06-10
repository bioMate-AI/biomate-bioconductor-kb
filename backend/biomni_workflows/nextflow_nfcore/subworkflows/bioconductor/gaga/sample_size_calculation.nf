#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gaga — sample_size_calculation
// Perform fixed and sequential sample size calculations to determine the optimal number of additional samples to collect.
// Input: pilot_expression.csv, pilot_groups.csv
// Container: quay.io/biocontainers/bioconductor-gaga:2.56.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: gaga
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the GaGa model to pilot data using fitGG and parest. 2. Calculate expected discoveries for fixed additional sample sizes using

nextflow.enable.dsl = 2

process BIOC_GAGA_SAMPLE_SIZE_CALCULATION {
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
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required library
        library(gaga)
        
        # Check if input files exist
        if (!file.exists("pilot_expression.csv") || !file.exists("pilot_groups.csv")) {
          stop("Required input files 'pilot_expression.csv' and/or 'pilot_groups.csv' are missing.")
        }
        
        # Read pilot expression data and group labels
        x_df <- read.csv("pilot_expression.csv", row.names = 1, check.names = FALSE)
        groups_df <- read.csv("pilot_groups.csv")
        
        # Extract group labels (assume they are in the first column)
        raw_groups <- groups_df[[1]]
        
        # Check that the pilot study contains at least two distinct groups
        unique_g <- unique(raw_groups)
        if (length(unique_g) < 2) {
          stop("The pilot study must contain at least two distinct groups.")
        }
        
        # Convert the full expression data to a numeric matrix
        x <- as.matrix(x_df)
        class(x) <- "numeric"
        
        # Define sampling cost as specified in the vignette
        samplingCost <- 0.01
        
        # 1. Fit the GaGa model to pilot data
        gg1 <- fitGG(x, groups = raw_groups, method = 'EM')
        gg1 <- parest(gg1, x = x, groups = raw_groups)
        
        # 2. Calculate expected discoveries for fixed additional sample sizes
        pow1 <- powfindgenes(gg1, x = x, groups = raw_groups, batchSize = 1, fdrmax = 0.05, B = 1000)
        
        # 3. Run forward simulations for sequential design
        fs1 <- forwsimDiffExpr(gg1, x = x, groups = raw_groups, maxBatch = 3, batchSize = 1, fdrmax = 0.05, B = 100, Bsummary = 100, randomSeed = 1)
        
        # 4. Determine optimal sequential stopping boundaries
        b0seq <- seq(0, 20, length = 200)
        b1seq <- seq(0, 40, length = 200)
        bopt <- seqBoundariesGrid(b0 = b0seq, b1 = b1seq, forwsim = fs1, samplingCost = samplingCost, powmin = 0)
        
        # Save outputs
        saveRDS(pow1, "power_calculation.rds")
        
        if (!is.null(pow1\$m)) {
          write.csv(data.frame(batchSize = 1, expected_discoveries = pow1\$m), "power_summary.csv", row.names = FALSE)
        }
        
        write.csv(fs1, "forward_simulations.csv", row.names = FALSE)
        write.csv(as.data.frame(t(bopt\$opt)), "optimal_boundary_summary.csv", row.names = TRUE)
        write.csv(bopt\$grid, "boundary_grid.csv", row.names = FALSE)
        
        # Generate diagnostic plot
        pdf("sequential_sample_size_plot.pdf")
        plot(fs1\$time, fs1\$summary, xlab = 'Additional batches', ylab = 'E(newly discovered DE genes)')
        abline(bopt\$opt['b0'], bopt\$opt['b1'])
        text(.2, bopt\$opt['b0'], 'Continue', pos = 3)
        text(.2, bopt\$opt['b0'], 'Stop', pos = 1)
        dev.off()

    writeLines(c(
        '"BIOC_GAGA_SAMPLE_SIZE_CALCULATION":',
        paste0('    gaga: ', as.character(packageVersion('gaga')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sample_size_calculation.csv versions.yml
    """
}

workflow BIOC_GAGA_SAMPLE_SIZE_CALCULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pilot_expression.csv, pilot_groups.csv ] ]

    main:
    BIOC_GAGA_SAMPLE_SIZE_CALCULATION(ch_input)

    emit:
    tables   = BIOC_GAGA_SAMPLE_SIZE_CALCULATION.out.tables
    plots    = BIOC_GAGA_SAMPLE_SIZE_CALCULATION.out.plots
    objects  = BIOC_GAGA_SAMPLE_SIZE_CALCULATION.out.objects
    versions = BIOC_GAGA_SAMPLE_SIZE_CALCULATION.out.versions
}
