#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: isanalytics — clonal_sharing_analysis
// Analyze and plot shared integration sites between different experimental groups using heatmaps and Venn/Euler diagrams.
// Input: integration_matrices, association_file
// Container: quay.io/biocontainers/bioconductor-isanalytics:1.20.1--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-isanalytics:1.20.1--r45hdfd78af_0"

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
    .bm_deps <- c("biocstyle", "devtools", "dplyr", "dt", "ggplot2", "isanalytics", "refmanager", "sessioninfo")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    library(ISAnalytics)
    library(dplyr)
    library(ggplot2)
    
    # Helper function to load RDS files with or without extension
    load_r_object <- function(filename) {
      if (file.exists(filename)) {
        return(readRDS(filename))
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else {
        stop(paste("Required input file not found:", filename))
      }
    }
    
    # Read user input files from the working directory
    integration_matrices <- load_r_object("integration_matrices")
    association_file <- load_r_object("association_file")
    
    ## Aggregation by standard key
    agg <- aggregate_values_by_key(integration_matrices,
        association_file,
        value_cols = c("seqCount", "fragmentEstimate")
    )
    agg <- agg |> dplyr::filter(TimePoint %in% c("0030", "0060"))
    
    # Scenario 1: Pairwise sharing with genomic coordinates
    sharing_1 <- is_sharing(agg,
        group_key = c(
            "SubjectID", "CellMarker",
            "Tissue", "TimePoint"
        ),
        n_comp = 2,
        is_count = TRUE,
        relative_is_sharing = TRUE,
        minimal = TRUE,
        include_self_comp = FALSE,
        keep_genomic_coord = TRUE
    )
    
    # Scenario 2: Sharing for heatmap plotting
    sharing_1_b <- is_sharing(agg,
        group_key = c(
            "SubjectID", "CellMarker",
            "Tissue", "TimePoint"
        ),
        n_comp = 2,
        is_count = TRUE,
        relative_is_sharing = TRUE,
        minimal = FALSE,
        include_self_comp = TRUE
    )
    heatmaps <- sharing_heatmap(sharing_1_b)
    
    # Scenario 3: Sharing for Venn/Euler diagrams
    sharing_5 <- is_sharing(agg,
        group_keys = list(
            g1 = c(
                "SubjectID", "CellMarker",
                "Tissue", "TimePoint"
            ),
            g2 = c("SubjectID", "CellMarker"),
            g3 = c("CellMarker", "Tissue")
        ), table_for_venn = TRUE
    )
    
    sharing_plots1 <- sharing_venn(sharing_5, row_range = 1, euler = TRUE)
    sharing_plots2 <- sharing_venn(sharing_5, row_range = 1, euler = FALSE)
    
    # Write outputs to files
    saveRDS(sharing_1, "sharing_pairwise_coords.rds")
    write.csv(sharing_1, "sharing_pairwise_coords.csv", row.names = FALSE)
    
    saveRDS(sharing_1_b, "sharing_heatmap_data.rds")
    
    pdf("sharing_heatmaps.pdf", width = 10, height = 8)
    if (!is.null(heatmaps\$absolute)) print(heatmaps\$absolute)
    if (!is.null(heatmaps\$on_g1)) print(heatmaps\$on_g1)
    if (!is.null(heatmaps\$on_union)) print(heatmaps\$on_union)
    dev.off()
    
    saveRDS(sharing_5, "sharing_venn_data.rds")
    
    pdf("sharing_venn_euler_plots.pdf", width = 8, height = 8)
    if (length(sharing_plots1) >= 1) plot(sharing_plots1[[1]])
    if (length(sharing_plots2) >= 1) plot(sharing_plots2[[1]])
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS":
        isanalytics: \$(Rscript -e 'cat(as.character(packageVersion("isanalytics")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clonal_sharing_analysis.csv versions.yml
    """
}

workflow BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ integration_matrices, association_file ] ]

    main:
    BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS.out.tables
    plots    = BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS.out.plots
    objects  = BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS.out.objects
    versions = BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS.out.versions
}
