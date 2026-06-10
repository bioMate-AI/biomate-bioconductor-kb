#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RITAN — comparative_subset_enrichment
// Compare functional enrichment profiles across multiple gene lists (e.g., different treatment conditions) and visualize the results as an annotated heatmap.
// Input: study_set.rds, annotation_metadata.csv
// Container: quay.io/biocontainers/bioconductor-ritan:1.34.0--r45hdfd78af_0
// R packages: RITAN, RITANdata
// Bioconductor: 3.20 | R: 4.4
// Requires: RITAN, RITANdata
// Visualizations: heatmap, enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run comparative enrichment across all subsets simultaneously using term_enrichment_by_subset(). 2. Generate a heatmap of the enric

nextflow.enable.dsl = 2

process BIOC_RITAN_COMPARATIVE_SUBSET_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("RITAN", "RITANdata")
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
        library(RITANdata)
        library(RITAN)
        
        # 1. Read User Input Files
        if (!file.exists("study_set.rds")) {
          stop("Error: 'study_set.rds' not found in the working directory.")
        }
        study_set <- readRDS("study_set.rds")
        
        mat <- NULL
        if (file.exists("annotation_metadata.csv")) {
          mat <- as.matrix(read.csv("annotation_metadata.csv", row.names = 1, check.names = FALSE))
        }
        
        # Define resources to use (standard RITAN resources)
        resources <- c("ReactomePathways", "MSigDB_Hallmarks")
        
        # 2. Run comparative enrichment across all subsets simultaneously
        e <- term_enrichment_by_subset ( study_set, q_value_threshold = 1e-5 , resources = resources, all_symbols = cached_coding_genes )
        
        # Save enrichment results
        saveRDS(e, "enrichment_results.rds")
        write.csv(as.data.frame(e), "enrichment_results.csv", row.names = TRUE)
        
        # 3. Generate a heatmap of the enrichment results (without annotation)
        pdf("enrichment_heatmap_simple.pdf", width = 10, height = 8)
        p1 <- plot ( e, show_values = FALSE , label_size_y = 7 , label_size_x = 7 , cap= 10 )
        print(p1)
        dev.off()
        
        # 4. Generate a heatmap of the enrichment results (with annotation, if available)
        if (!is.null(mat)) {
          pdf("enrichment_heatmap_annotated.pdf", width = 10, height = 8)
          p2 <- plot ( e, show_values = TRUE , label_size_y = 7 , label_size_x = 7 , cap= 10 , annotation_matrix = mat, grid_line_color = 'black' )
          print(p2)
          dev.off()
        } else {
          message("Optional 'annotation_metadata.csv' not found. Skipping annotated plot.")
        }

    writeLines(c(
        '"BIOC_RITAN_COMPARATIVE_SUBSET_ENRICHMENT":',
        paste0('    RITAN: ', as.character(packageVersion('RITAN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_comparative_subset_enrichment.csv versions.yml
    """
}

workflow BIOC_RITAN_COMPARATIVE_SUBSET_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ study_set.rds, annotation_metadata.csv ] ]

    main:
    BIOC_RITAN_COMPARATIVE_SUBSET_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_RITAN_COMPARATIVE_SUBSET_ENRICHMENT.out.tables
    plots    = BIOC_RITAN_COMPARATIVE_SUBSET_ENRICHMENT.out.plots
    objects  = BIOC_RITAN_COMPARATIVE_SUBSET_ENRICHMENT.out.objects
    versions = BIOC_RITAN_COMPARATIVE_SUBSET_ENRICHMENT.out.versions
}
