#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: weitrix — alternative_polyadenylation_shift_analysis
// Analyze alternative polyadenylation (APA) site-level counts by calculating shift scores, calibrating weights, and identifying components of variation.
// Input: peak_count.csv.gz, peaks.csv.gz, samples
// Container: quay.io/biocontainers/bioconductor-weitrix:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, dplyr, ggplot2, weitrix
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct shift weitrix using counts_shift
//  * 2. [Core Analysis] Find components of variation using weitrix_components_seq
//  * 3. [Core Analysis] Calibrate weights using weitrix_calibrate_all (or weitrix_calibrate_trend for large datasets) with per_read_var and well_knotted_s
//  * 4. [Visualization & Output] Diagnostic plotting with weitrix_calplot
//  * 5. [Core Analysis] Test for confident loadings using weitrix_confects
//  * 6. [Core Analysis] Find highly variable genes using weitrix_sd_confects

nextflow.enable.dsl = 2

process BIOC_WEITRIX_ALTERNATIVE_POLYADENYLATION_SHIFT_ANALYSIS {
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
    .bm_deps <- c("weitrix", "dplyr", "ggplot2", "BiocParallel", "SummarizedExperiment")
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
    
    # Load required librari    library(SummarizedExperiment)
es
    library(weitrix)
    library(dplyr)
    library(ggplot2)
    library(BiocParallel)
    
    # Configure BiocParallel to use serial processing for reliability
    register(SerialParam())
    
    # ----------------------------------------------------------------------
    # 1. Read User Input Files
    # ----------------------------------------------------------------------
    
    # Read peak counts matrix (site-level counts)
    counts <- read.csv("peak_count.csv.gz", check.names = FALSE, row.names = 1)
    counts <- as.matrix(counts)
    
    # Read peaks data frame (grouping sites into genes)
    peaks <- read.csv("peaks.csv.gz", check.names = FALSE)
    # Clean up any missing gene names
    peaks <- peaks[!is.na(peaks\$gene_name) & peaks\$gene_name != "", ]
    
    # Read experimental design metadata
    samples <- read.csv("samples", check.names = FALSE)
    # Ensure rownames of samples match colnames of counts
    if ("sample" %in% colnames(samples)) {
      rownames(samples) <- samples\$sample
    } else {
      rownames(samples) <- colnames(counts)
    }
    
    # Construct groups data frame for counts_shift
    groups <- peaks %>% dplyr::select(group = gene_name, name = name)
    
    # Construct genes data frame to map gene names to symbols
    unique_genes <- unique(peaks\$gene_name)
    genes <- data.frame(
      row.names = unique_genes,
      symbol = unique_genes,
      stringsAsFactors = FALSE
    )
    if ("symbol" %in% colnames(peaks)) {
      symbol_map <- unique(peaks[, c("gene_name", "symbol")])
      rownames(symbol_map) <- symbol_map\$gene_name
      genes[rownames(symbol_map), "symbol"] <- symbol_map\$symbol
    }
    
    # ----------------------------------------------------------------------
    # 2. Execute Documented Workflow
    # ----------------------------------------------------------------------
    
    # Construct shift weitrix
    wei <- counts_shift(counts, groups)
    
    # Add sample metadata
    colData(wei) <- cbind(colData(wei), samples)
    
    # Add gene symbol metadata
    rowData(wei)\$symbol <- genes\$symbol[match(rownames(wei), rownames(genes))]
    
    # Find components of variation
    comp_seq <- weitrix_components_seq(wei, p=6, design=~0)
    
    # Generate and save screeplot
    pdf("screeplot.pdf")
    print(components_seq_screeplot(comp_seq))
    dev.off()
    
    # Select the 4th component
    comp <- comp_seq[[4]]
    
    # Calibrate all weights
    cal <- weitrix_calibrate_all( wei, design = comp, trend_formula = ~log(per_read_var)+well_knotted_spline(log2(weight),3))
    
    # Generate and save calibration plot
    pdf("calplot.pdf")
    print(weitrix_calplot(wei, comp, covar=mu))
    dev.off()
    
    # Test for confident loadings on C1
    confects_c1 <- weitrix_confects(cal, comp\$col, "C1", fdr=0.05)
    
    # Find highly variable genes
    sd_confects <- weitrix_sd_confects(cal, step=0.01)
    
    # Alternative calibration method (trend-based)
    cal_trend <- weitrix_calibrate_trend( wei, design = comp, trend_formula = ~log(per_read_var)+well_knotted_spline(log(total_reads),3))
    
    # ----------------------------------------------------------------------
    # 3. Save Outputs
    # ----------------------------------------------------------------------
    
    # Save tables
    write.csv(confects_c1\$table, "confects_C1.csv", row.names = TRUE)
    write.csv(sd_confects\$table, "sd_confects.csv", row.names = TRUE)
    
    # Save RDS objects
    saveRDS(cal, "cal_all.rds")
    saveRDS(cal_trend, "cal_trend.rds")

    writeLines(c(
        '"BIOC_WEITRIX_ALTERNATIVE_POLYADENYLATION_SHIFT_ANALYSIS":',
        paste0('    weitrix: ', as.character(packageVersion('weitrix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alternative_polyadenylation_shift_analysis.csv versions.yml
    """
}

workflow BIOC_WEITRIX_ALTERNATIVE_POLYADENYLATION_SHIFT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peak_count.csv.gz, peaks.csv.gz, samples ] ]

    main:
    BIOC_WEITRIX_ALTERNATIVE_POLYADENYLATION_SHIFT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_WEITRIX_ALTERNATIVE_POLYADENYLATION_SHIFT_ANALYSIS.out.tables
    plots    = BIOC_WEITRIX_ALTERNATIVE_POLYADENYLATION_SHIFT_ANALYSIS.out.plots
    objects  = BIOC_WEITRIX_ALTERNATIVE_POLYADENYLATION_SHIFT_ANALYSIS.out.objects
    versions = BIOC_WEITRIX_ALTERNATIVE_POLYADENYLATION_SHIFT_ANALYSIS.out.versions
}
