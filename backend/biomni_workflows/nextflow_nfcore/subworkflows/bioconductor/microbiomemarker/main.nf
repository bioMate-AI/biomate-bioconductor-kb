#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: microbiomeMarker — microbiome_marker_discovery
// Identify and visualize taxonomic biomarkers from microbiome profiling data using LEfSe or other differential abundance methods.
// Input: otu_table.csv, sample_metadata.csv, taxonomy_table.csv
// Container: quay.io/biocontainers/bioconductor-microbiomemarker:1.8.0--r43hdfd78af_0
// R packages: ggplot2, microbiomeMarker, phyloseq
// Bioconductor: 3.20 | R: 4.4
// Requires: microbiomeMarker, phyloseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import data into a phyloseq object
//  * 2. [Core Analysis] Run marker discovery using run_lefse or other run_* functions
//  * 3. [Visualization & Output] Visualize identified markers using plot_ef_bar or plot_cladogram

nextflow.enable.dsl = 2

process BIOC_MICROBIOMEMARKER_MICROBIOME_MARKER_DISCOVERY {
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
    .bm_deps <- c("ggplot2", "microbiomeMarker", "phyloseq")
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
            library(phyloseq)
            library(microbiomeMarker)
            
            # 1. Import data into a phyloseq object
            # Read the user-provided CSV files from the working directory
            otu_df <- read.csv("otu_table.csv", row.names = 1, check.names = FALSE)
            tax_df <- read.csv("taxonomy_table.csv", row.names = 1, check.names = FALSE)
            sam_df <- read.csv("sample_metadata.csv", row.names = 1, check.names = FALSE)
            
            # Convert OTU table to matrix and determine orientation (taxa as rows or columns)
            otu_mat <- as.matrix(otu_df)
            taxa_are_rows_val <- TRUE
            if (!any(rownames(otu_mat) %in% rownames(tax_df)) && any(colnames(otu_mat) %in% rownames(tax_df))) {
                taxa_are_rows_val <- FALSE
            }
            
            # Construct phyloseq components
            otu <- otu_table(otu_mat, taxa_are_rows = taxa_are_rows_val)
            tax <- tax_table(as.matrix(tax_df))
            sam <- sample_data(sam_df)
            
            # Combine into a single phyloseq object
            ps <- phyloseq(otu, tax, sam)
            
            # 2. Run marker discovery using run_lefse
            # This call reproduces the documented code and arguments exactly
            mm_lefse <- run_lefse(
                ps,
                group = colnames(sam_df)[1],
                taxa_rank = "all",
                kw_cutoff = 0.05,
                wilcoxon_cutoff = 0.05,
                lda_cutoff = 2.0
            )
            
            # 3. Visualize identified markers and save outputs
            # Save the microbiomeMarker object for downstream analysis
            saveRDS(mm_lefse, "mm_lefse_results.rds")
            
            # Export the marker table to CSV
            tb <- marker_table(mm_lefse)
            if (!is.null(tb)) {
                write.csv(as.data.frame(tb), "marker_table.csv", row.names = FALSE)
            }
            
            # Generate and save the effect size bar plot
            pdf("plot_ef_bar.pdf", width = 8, height = 6)
            print(plot_ef_bar(mm_lefse))
            dev.off()
            
            # Generate and save the cladogram plot
            # Wrapped in a tryCatch block to handle cases where taxonomic tree structure 
            # or specific rank hierarchies prevent cladogram generation.
            tryCatch({
                pdf("plot_cladogram.pdf", width = 10, height = 10)
                print(plot_cladogram(mm_lefse, color = c("darkgreen", "red")))
                dev.off()
            }, error = function(e) {
                message("Cladogram plotting skipped or failed: ", e\$message)
            })

    writeLines(c(
        '"BIOC_MICROBIOMEMARKER_MICROBIOME_MARKER_DISCOVERY":',
        paste0('    microbiomeMarker: ', as.character(packageVersion('microbiomeMarker')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microbiome_marker_discovery.csv versions.yml
    """
}

workflow BIOC_MICROBIOMEMARKER_MICROBIOME_MARKER_DISCOVERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ otu_table.csv, sample_metadata.csv, taxonomy_table.csv ] ]

    main:
    BIOC_MICROBIOMEMARKER_MICROBIOME_MARKER_DISCOVERY(ch_input)

    emit:
    tables   = BIOC_MICROBIOMEMARKER_MICROBIOME_MARKER_DISCOVERY.out.tables
    plots    = BIOC_MICROBIOMEMARKER_MICROBIOME_MARKER_DISCOVERY.out.plots
    objects  = BIOC_MICROBIOMEMARKER_MICROBIOME_MARKER_DISCOVERY.out.objects
    versions = BIOC_MICROBIOMEMARKER_MICROBIOME_MARKER_DISCOVERY.out.versions
}
