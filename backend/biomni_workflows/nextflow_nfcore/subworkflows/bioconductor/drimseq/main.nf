#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DRIMSeq — differential_transcript_usage
// Perform differential transcript usage (DTU) analysis between experimental conditions, with or without batch effects, using Dirichlet-multinomial and beta-binomi
// Input: pasilla_counts.txt, metadata.txt
// Container: quay.io/biocontainers/bioconductor-drimseq:1.38.0--r45hdfd78af_0
// R packages: DRIMSeq, geuvadistranscriptexpr, ggplot2, knitr, pasillatranscriptexpr, stageR
// Bioconductor: 3.20 | R: 4.4
// Requires: DRIMSeq, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load counts and sample metadata into a dmDSdata object using dmDSdata()
//  * 2. [Core Analysis] Filter out lowly expressed genes and transcripts using dmFilter()
//  * 3. [Input & Preparation] Define the full model design matrix using model.matrix()
//  * 4. [Core Analysis] Estimate precision parameters using dmPrecision()
//  * 5. [Core Analysis] Fit the full model proportions and coefficients using dmFit()
//  * 6. [Core Analysis] Test for differential usage against a null model using dmTest()
//  * 7. [Visualization & Output] Extract results using results() and visualize proportions using plotProportions()

nextflow.enable.dsl = 2

process BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE {
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
    .bm_deps <- c("DRIMSeq", "geuvadistranscriptexpr", "ggplot2", "knitr", "pasillatranscriptexpr", "stageR")
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
        library(DRIMSeq)
        library(ggplot2)
        
        # 1. Load counts and sample metadata from the working directory
        if (!file.exists("metadata.txt") || !file.exists("pasilla_counts.txt")) {
          stop("Required input files 'metadata.txt' and/or 'pasilla_counts.txt' are missing from the working directory.")
        }
        
        pasilla_metadata <- read.table("metadata.txt", header = TRUE, as.is = TRUE)
        pasilla_counts <- read.table("pasilla_counts.txt", header = TRUE, as.is = TRUE)
        
        pasilla_samples <- data.frame(sample_id = pasilla_metadata\$SampleName, 
          group = as.factor(pasilla_metadata\$condition))
        levels(pasilla_samples\$group)
        
        d <- dmDSdata(counts = pasilla_counts, samples = pasilla_samples)
        d
        head(counts(d), 3)
        head(samples(d), 3)
        
        # Save initial data plot
        pdf("plot_data_summary.pdf")
        print(plotData(d))
        dev.off()
        
        # Optional subsetting if the subset file is provided in the working directory
        if (file.exists("gene_id_subset.txt")) {
          gene_id_subset <- readLines("gene_id_subset.txt")
          d <- d[names(d) %in% gene_id_subset, ]
        }
        d
        
        table(samples(d)\$group)
        
        # 2. Filter out lowly expressed genes and transcripts
        total_samps <- nrow(pasilla_samples)
        min_reps <- min(table(pasilla_samples\$group))
        
        d <- dmFilter(d, min_samps_gene_expr = total_samps, min_samps_feature_expr = min_reps,
          min_gene_expr = 10, min_feature_expr = 10)
        
        # 3. Define the full model design matrix
        design_full <- model.matrix(~ group, data = samples(d))
        design_full
        
        # 4. Estimate precision parameters
        set.seed(123)
        d <- dmPrecision(d, design = design_full)
        d
        head(mean_expression(d), 3)
        common_precision(d)
        head(genewise_precision(d))
        
        pdf("plot_precision.pdf")
        print(plotPrecision(d))
        dev.off()
        
        ggp <- plotPrecision(d)
        pdf("plot_precision_custom.pdf")
        print(ggp + geom_point(size = 4))
        dev.off()
        
        # 5. Fit the full model proportions and coefficients
        d <- dmFit(d, design = design_full, verbose = 1)
        d
        
        head(proportions(d))
        head(coefficients(d))
        head(coefficients(d), level = "feature")
        
        # 6. Test for differential usage against a null model
        coef_to_test <- paste0("group", levels(pasilla_samples\$group)[2])
        d <- dmTest(d, coef = coef_to_test, verbose = 1)
        print(design(d))
        print(head(results(d), 3))
        
        head(results(d, level = "feature"), 3)
        
        # Save diagnostic plots
        pdf("plot_pvalues_gene.pdf")
        print(plotPValues(d))
        dev.off()
        
        pdf("plot_pvalues_feature.pdf")
        print(plotPValues(d, level = "feature"))
        dev.off()
        
        # 7. Extract results and visualize proportions
        res <- results(d)
        res <- res[order(res\$pvalue, decreasing = FALSE), ]
        top_gene_id <- res\$gene_id[1]
        
        pdf("plot_proportions_bar.pdf")
        print(plotProportions(d, gene_id = top_gene_id, group_variable = "group"))
        dev.off()
        
        pdf("plot_proportions_line.pdf")
        print(plotProportions(d, gene_id = top_gene_id, group_variable = "group", 
          plot_type = "lineplot"))
        dev.off()
        
        pdf("plot_proportions_ribbon.pdf")
        print(plotProportions(d, gene_id = top_gene_id, group_variable = "group", 
          plot_type = "ribbonplot"))
        dev.off()
        
        # Save meaningful tabular results and objects to the working directory
        write.csv(results(d), "dtu_gene_results.csv", row.names = FALSE)
        write.csv(results(d, level = "feature"), "dtu_feature_results.csv", row.names = FALSE)
        write.csv(proportions(d), "fitted_proportions.csv", row.names = FALSE)
        write.csv(coefficients(d), "coefficients_gene.csv", row.names = FALSE)
        write.csv(coefficients(d, level = "feature"), "coefficients_feature.csv", row.names = FALSE)
        saveRDS(d, "drimseq_final_object.rds")
        
        message("DRIMSeq pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE":',
        paste0('    DRIMSeq: ', as.character(packageVersion('DRIMSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_transcript_usage.csv versions.yml
    """
}

workflow BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pasilla_counts.txt, metadata.txt ] ]

    main:
    BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE(ch_input)

    emit:
    tables   = BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE.out.tables
    plots    = BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE.out.plots
    objects  = BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE.out.objects
    versions = BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE.out.versions
}
