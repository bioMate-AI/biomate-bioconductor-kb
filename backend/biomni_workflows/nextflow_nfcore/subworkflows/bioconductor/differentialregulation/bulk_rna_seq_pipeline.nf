#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: differentialregulation — bulk_rna_seq_pipeline
// Detect differentially regulated transcripts between two groups of samples using bulk RNA-seq data.
// Input: quant.sf, eq_classes.txt.gz
// Container: quay.io/biocontainers/bioconductor-differentialregulation:2.8.0--r45ha27e39d_0
// R packages: DifferentialRegulation
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_DIFFERENTIALREGULATION_BULK_RNA_SEQ_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-differentialregulation:2.8.0--r45ha27e39d_0"

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
    .bm_deps <- c("DifferentialRegulation")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(DifferentialRegulation)
    
    # --- Locate user input files in the working directory ---
    quant_files = list.files(path = ".", pattern = "quant\\\\.sf\$", recursive = TRUE, full.names = TRUE)
    equiv_classes_files = list.files(path = ".", pattern = "eq_classes\\\\.txt\\\\.gz\$", recursive = TRUE, full.names = TRUE)
    
    if (length(quant_files) == 0 || length(equiv_classes_files) == 0) {
      stop("Error: Could not find 'quant.sf' or 'eq_classes.txt.gz' files in the working directory.")
    }
    
    # Sort to ensure matching order across samples
    quant_files = sort(quant_files)
    equiv_classes_files = sort(equiv_classes_files)
    
    # Extract sample IDs from the directory structure
    sample_ids = basename(dirname(quant_files))
    if (any(sample_ids == ".")) {
      sample_ids = paste0("sample", seq_along(quant_files))
    }
    
    # --- Load bulk US counts using load_bulk_US ---
    SE = load_bulk_US(quant_files,
                      sample_ids)
    
    # --- Load bulk equivalence classes using load_bulk_EC ---
    EC_list = load_bulk_EC(path_to_eq_classes = equiv_classes_files,
                           n_cores = 2)
    
    # --- Define experimental design ---
    # Dynamically assign groups A and B based on the number of samples
    group_names = rep(c("A", "B"), each = ceiling(length(sample_ids) / 2))[1:length(sample_ids)]
    design = data.frame(sample = sample_ids,
                        group = group_names)
    
    # --- Run bulk differential testing using ---
    set.seed(1609612)
    results = DifferentialRegulation_bulk(SE = SE, 
                                          EC_list = EC_list,
                                          design = design,
                                          n_cores = 2,
                                          traceplot = TRUE)
    
    # --- Save results to files ---
    saveRDS(results, "differential_regulation_results.rds")
    write.csv(results\$Differential_results, "differential_results.csv", row.names = FALSE)
    write.csv(results\$Convergence_results, "convergence_results.csv", row.names = FALSE)
    
    # --- Visualize results using plot_bulk_pi and ---
    # Generate PDF plots for the top transcript
    top_transcript = results\$Differential_results\$Transcript_id[1]
    
    pdf("bulk_pi_plot.pdf")
    plot_bulk_pi(results,
                 transcript_id = top_transcript)
    dev.off()
    
    pdf("bulk_traceplot.pdf")
    plot_bulk_traceplot(results,
                        transcript_id = top_transcript)
    dev.off()

    writeLines(c(
        '"BIOC_DIFFERENTIALREGULATION_BULK_RNA_SEQ_PIPELINE":',
        paste0('        differentialregulation: ', as.character(packageVersion("differentialregulation")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bulk_rna_seq_pipeline.csv versions.yml
    """
}

workflow BIOC_DIFFERENTIALREGULATION_BULK_RNA_SEQ_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ quant.sf, eq_classes.txt.gz ] ]

    main:
    BIOC_DIFFERENTIALREGULATION_BULK_RNA_SEQ_PIPELINE(ch_input)

    emit:
    tables   = BIOC_DIFFERENTIALREGULATION_BULK_RNA_SEQ_PIPELINE.out.tables
    plots    = BIOC_DIFFERENTIALREGULATION_BULK_RNA_SEQ_PIPELINE.out.plots
    objects  = BIOC_DIFFERENTIALREGULATION_BULK_RNA_SEQ_PIPELINE.out.objects
    versions = BIOC_DIFFERENTIALREGULATION_BULK_RNA_SEQ_PIPELINE.out.versions
}
