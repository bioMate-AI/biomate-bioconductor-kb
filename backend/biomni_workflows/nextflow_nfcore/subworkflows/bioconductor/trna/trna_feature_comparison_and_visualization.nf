#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tRNA — trna_feature_comparison_and_visualization
// Compare tRNA feature parameters across multiple datasets and correlate features with external scores.
// Input: grl
// Container: quay.io/biocontainers/bioconductor-trna:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, ggplot2, tRNA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Generate comparative feature plots for tRNA sets
//  * 2. [Core Analysis] Correlate tRNA features with external numeric scores
//  * 3. [Visualization & Output] Customize the resulting ggplot2 visualization layers

nextflow.enable.dsl = 2

process BIOC_TRNA_TRNA_FEATURE_COMPARISON_AND_VISUALIZATION {
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
    .bm_deps <- c("tRNA", "GenomicRanges", "ggplot2")
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
        library(tRNA)
        library(GenomicRanges)
        library(ggplot2)
        
        # ==========================================
        # 0. Load User Input
        # ==========================================
        # Read the GRangesList object 'grl' from the working directory
        if (file.exists("grl")) {
          grl <- readRDS("grl")
        } else if (file.exists("grl.rds")) {
          grl <- readRDS("grl.rds")
        } else {
          stop("Error: Input file 'grl' or 'grl.rds' not found in the working directory.")
        }
        
        # Ensure it is a GRangesList
        if (!inherits(grl, "GRangesList")) {
          stop("Error: The input file does not contain a GRangesList object.")
        }
        
        # ==========================================
        # 1. Generate comparative feature plots
        # ==========================================
        plots_comp <- gettRNAFeaturePlots(grl)
        
        # Save the comparative feature plots to a PDF
        pdf("tRNA_comparative_feature_plots.pdf", width = 8, height = 6)
        print(plots_comp\$length)
        print(plots_comp\$tRNAscan_score)
        print(plots_comp\$gc)
        print(plots_comp\$tRNAscan_intron)
        print(plots_comp\$variableLoop_length)
        dev.off()
        
        # ==========================================
        # 2. Correlate tRNA features with external scores
        # ==========================================
        # Generate scores dynamically for each element in the GRangesList
        plots <- gettRNAFeaturePlots(grl,
                                     scores = lapply(grl, function(x) runif(length(x), 0L, 100L)))
        
        # Save the correlation plots to a PDF
        pdf("tRNA_correlation_plots.pdf", width = 8, height = 6)
        print(plots\$length)
        print(plots\$variableLoop_length)
        dev.off()
        
        # ==========================================
        # 3. Customize the resulting ggplot2 visualization layers
        # ==========================================
        # Modify the layers of the length plot as documented
        plots\$length\$layers <- plots\$length\$layers[c(-1L,-2L)]
        custom_plot <- plots\$length + ggplot2::geom_boxplot()
        
        # Save the customized plot
        pdf("tRNA_custom_length_plot.pdf", width = 8, height = 6)
        print(custom_plot)
        dev.off()
        
        # Extract and save the underlying data
        length_data_head <- head(plots\$length\$data)
        write.csv(plots\$length\$data, "tRNA_length_correlation_data.csv", row.names = FALSE)
        write.csv(length_data_head, "tRNA_length_correlation_data_head.csv", row.names = FALSE)
        
        # Save the final plots list as an RDS object for downstream use
        saveRDS(plots, "tRNA_correlation_plots_object.rds")

    writeLines(c(
        '"BIOC_TRNA_TRNA_FEATURE_COMPARISON_AND_VISUALIZATION":',
        paste0('    tRNA: ', as.character(packageVersion('tRNA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trna_feature_comparison_and_visualization.csv versions.yml
    """
}

workflow BIOC_TRNA_TRNA_FEATURE_COMPARISON_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ grl ] ]

    main:
    BIOC_TRNA_TRNA_FEATURE_COMPARISON_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_TRNA_TRNA_FEATURE_COMPARISON_AND_VISUALIZATION.out.tables
    plots    = BIOC_TRNA_TRNA_FEATURE_COMPARISON_AND_VISUALIZATION.out.plots
    objects  = BIOC_TRNA_TRNA_FEATURE_COMPARISON_AND_VISUALIZATION.out.objects
    versions = BIOC_TRNA_TRNA_FEATURE_COMPARISON_AND_VISUALIZATION.out.versions
}
