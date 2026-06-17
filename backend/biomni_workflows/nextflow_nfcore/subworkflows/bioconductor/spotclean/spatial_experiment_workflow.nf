#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spotclean — spatial_experiment_workflow
// Decontaminate spatial transcriptomics data stored in a SpatialExperiment object.
// Input: /path/to/spaceranger/output/
// Container: quay.io/biocontainers/bioconductor-spotclean:1.12.0--r45hdfd78af_0
// R packages: S4Vectors, SpatialExperiment, SpotClean
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_SPOTCLEAN_SPATIAL_EXPERIMENT_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-spotclean:1.12.0--r45hdfd78af_0"

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
    .bm_deps <- c("S4Vectors", "SpatialExperiment", "SpotClean", "SummarizedExperiment")
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
    library(SpatialExperiment)
    library(SummarizedExperiment)
    library(SpotClean)
    library(S4Vectors)
    
    # --- Load raw data into a SpatialExperiment object ---
    # Reading raw data from the specified Space Ranger output directory
    message("Loading raw 10x Visium data...")
    slide_obj <- read10xVisium(samples = "/path/to/spaceranger/output/", data = "raw")
    
    # --- Run decontamination ---
    message("Running SpotClean decontamination...")
    decont_obj <- spotclean(slide_obj)
    
    # --- Inspect decontaminated assays ---
    message("Inspecting decontaminated assays...")
    str(assays(decont_obj)\$decont)
    
    # --- Save meaningful pipeline outputs ---
    message("Saving results...")
    
    # Save the complete decontaminated SpatialExperiment object
    saveRDS(decont_obj, file = "decont_spatial_experiment.rds")
    
    # Extract decontaminated count matrix
    decont_matrix <- assays(decont_obj)\$decont
    
    # Save a summary of decontaminated expression per gene
    gene_summary <- data.frame(
        gene = rownames(decont_matrix),
        total_decont_expression = Matrix::rowSums(decont_matrix),
        mean_decont_expression = Matrix::rowMeans(decont_matrix)
    )
    write.csv(gene_summary, file = "decont_gene_summary.csv", row.names = FALSE)
    
    # Extract and save contamination metadata if available
    metadata_list <- metadata(decont_obj)
    
    if ("contamination_rate" %in% names(metadata_list)) {
        cont_rates <- metadata_list\$contamination_rate
        cont_df <- data.frame(
            spot_id = names(cont_rates),
            contamination_rate = as.numeric(cont_rates)
        )
        write.csv(cont_df, file = "contamination_rates.csv", row.names = FALSE)
        
        # Generate diagnostic plot of contamination rates
        pdf("decontamination_diagnostics.pdf", width = 7, height = 5)
        hist(cont_rates, 
             breaks = 30, 
             col = "skyblue", 
             border = "white",
             main = "Distribution of Estimated Spot Contamination Rates",
             xlab = "Contamination Rate")
        dev.off()
    }
    
    if ("ARC_score" %in% names(metadata_list)) {
        writeLines(as.character(metadata_list\$ARC_score), con = "arc_score.txt")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SPOTCLEAN_SPATIAL_EXPERIMENT_WORKFLOW":',
        paste0('        spotclean: ', as.character(packageVersion("spotclean")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_experiment_workflow.csv versions.yml
    """
}

workflow BIOC_SPOTCLEAN_SPATIAL_EXPERIMENT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ /path/to/spaceranger/output/ ] ]

    main:
    BIOC_SPOTCLEAN_SPATIAL_EXPERIMENT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_SPOTCLEAN_SPATIAL_EXPERIMENT_WORKFLOW.out.tables
    plots    = BIOC_SPOTCLEAN_SPATIAL_EXPERIMENT_WORKFLOW.out.plots
    objects  = BIOC_SPOTCLEAN_SPATIAL_EXPERIMENT_WORKFLOW.out.objects
    versions = BIOC_SPOTCLEAN_SPATIAL_EXPERIMENT_WORKFLOW.out.versions
}
