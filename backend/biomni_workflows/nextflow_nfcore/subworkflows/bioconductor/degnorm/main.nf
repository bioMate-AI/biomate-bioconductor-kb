#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: degnorm — degradation_normalization_workflow
// Perform degradation normalization on bulk RNA-seq BAM files using a GTF annotation to obtain degradation-normalized read counts and visualize degradation indice
// Input: bam_files, gtf_file
// Container: quay.io/biocontainers/bioconductor-degnorm:1.20.0--r45ha27e39d_0
// R packages: DegNorm
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_DEGNORM_DEGRADATION_NORMALIZATION_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-degnorm:1.20.0--r45ha27e39d_0"

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
    .bm_deps <- c("DegNorm")
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
    library(DegNorm)
    
    # --- Identify and list BAM and GTF files from the working ---
    bam_file_list = list.files(path=".", pattern="\\\\.bam\$", full.names=TRUE)
    if (length(bam_file_list) == 0) {
      stop("Error: No BAM files found in the working directory.")
    }
    
    gtf_files = list.files(path=".", pattern="\\\\.gtf\$", full.names=TRUE)
    if (length(gtf_files) == 0) {
      stop("Error: No GTF files found in the working directory.")
    }
    gtf_file = gtf_files[1]
    
    message("Found ", length(bam_file_list), " BAM files.")
    message("Using GTF file: ", gtf_file)
    
    # --- Calculate read coverage scores and counts across samples ---
    message("Calculating read coverage...")
    coverage_res_chr21 = read_coverage_batch(bam_file_list, gtf_file, cores=2)
    
    # Summarize coverage results
    summary_CoverageClass(coverage_res_chr21)
    
    # Extract coverage scores and counts
    coverage_matrix = coverage_res_chr21\$coverage
    counts = coverage_res_chr21\$counts
    
    # Save raw coverage results
    saveRDS(coverage_res_chr21, file="coverage_results.rds")
    write.csv(counts, file="raw_counts.csv", row.names=TRUE)
    
    # --- Run the DegNorm core algorithm ---
    message("Running DegNorm core algorithm...")
    res_DegNorm_chr21 = degnorm(read_coverage = coverage_res_chr21[[1]],
                                counts = coverage_res_chr21[[2]],
                                iteration = 5,
                                down_sampling = 1,
                                grid_size = 10,
                                loop = 100,
                                cores = 2)
    
    # Summary of DegNorm output
    summary_DegNormClass(res_DegNorm_chr21)
    
    # Extract normalized read counts
    counts_normed = res_DegNorm_chr21\$counts_normed
    
    # Save normalized counts and full results
    write.csv(counts_normed, file="degnorm_normalized_counts.csv", row.names=TRUE)
    saveRDS(res_DegNorm_chr21, file="degnorm_results.rds")
    
    # --- Visualize coverage curves, degradation index boxplots, ---
    message("Generating diagnostic plots...")
    pdf("degnorm_diagnostic_plots.pdf", width=7, height=6)
    
    # Determine a valid gene name to plot (fallback to first available if SOD1 is not present)
    available_genes = names(coverage_res_chr21\$coverage)
    gene_name_val = if ("SOD1" %in% available_genes) "SOD1" else available_genes[1]
    
    # Determine group vector based on number of samples
    num_samples = ncol(coverage_res_chr21\$counts)
    group_val = c(0, rep(1, max(0, num_samples - 1)))
    
    # Plot coverage for all samples
    if (!is.null(gene_name_val)) {
      tryCatch({
        plot_coverage(gene_name=gene_name_val, coverage_output=coverage_res_chr21, 
                      degnorm_output=res_DegNorm_chr21, group=group_val)
      }, error = function(e) {
        message("Warning: plot_coverage failed: ", e\$message)
      })
      
      # Plot coverage for a subset of samples (up to 2)
      samples_val = colnames(coverage_res_chr21\$counts)[1:min(2, num_samples)]
      group_val_sub = c(0, rep(1, max(0, length(samples_val) - 1)))
      tryCatch({
        plot_coverage(gene_name=gene_name_val, coverage_output=coverage_res_chr21, 
                      degnorm_output=res_DegNorm_chr21, group=group_val_sub, 
                      samples=samples_val)
      }, error = function(e) {
        message("Warning: subset plot_coverage failed: ", e\$message)
      })
    }
    
    # Boxplot of degradation index (DI) scores
    tryCatch({
      plot_boxplot(DI=res_DegNorm_chr21\$DI)
    }, error = function(e) {
      message("Warning: plot_boxplot failed: ", e\$message)
    })
    
    # Heatmap plot of DI scores
    tryCatch({
      plot_heatmap(DI=res_DegNorm_chr21\$DI)
    }, error = function(e) {
      message("Warning: plot_heatmap failed: ", e\$message)
    })
    
    # Correlation matrix plot of DI scores
    tryCatch({
      plot_corr(DI=res_DegNorm_chr21\$DI)
    }, error = function(e) {
      message("Warning: plot_corr failed: ", e\$message)
    })
    
    dev.off()
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_DEGNORM_DEGRADATION_NORMALIZATION_WORKFLOW":',
        paste0('        degnorm: ', as.character(packageVersion("degnorm")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_degradation_normalization_workflow.csv versions.yml
    """
}

workflow BIOC_DEGNORM_DEGRADATION_NORMALIZATION_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam_files, gtf_file ] ]

    main:
    BIOC_DEGNORM_DEGRADATION_NORMALIZATION_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_DEGNORM_DEGRADATION_NORMALIZATION_WORKFLOW.out.tables
    plots    = BIOC_DEGNORM_DEGRADATION_NORMALIZATION_WORKFLOW.out.plots
    objects  = BIOC_DEGNORM_DEGRADATION_NORMALIZATION_WORKFLOW.out.objects
    versions = BIOC_DEGNORM_DEGRADATION_NORMALIZATION_WORKFLOW.out.versions
}
