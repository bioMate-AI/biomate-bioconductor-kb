#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: musicatk — count_table_workflow
// Create a musica object directly from a pre-computed mutation count table and perform signature discovery.
// Input: luad_tcga_count_table.csv
// Container: quay.io/biocontainers/bioconductor-musicatk:2.4.0--r45h1f0d9b5_0
// R packages: musicatk
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUSICATK_COUNT_TABLE_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-musicatk:2.4.0--r45h1f0d9b5_0"

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
    .bm_deps <- c("musicatk")
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
    
    # Load required library
    library(musicatk)
    
    # --- Read the count table and convert to matrix ---
    # We assume the first column contains the mutation motifs (row names)
    luad_count_table <- as.matrix(read.csv("luad_tcga_count_table.csv", row.names = 1, check.names = FALSE))
    
    # --- Create a musica object directly from the count table ---
    musica_from_counts <- create_musica_from_counts(luad_count_table, "SBS96")
    
    # Set seed for reproducibility of the NMF algorithm
    set.seed(1)
    
    # --- Discover signatures and exposures using ---
    discover_signatures(
      musica = musica_from_counts, modality = "SBS96", num_signatures = 3,
      algorithm = "nmf", model_id = "ex_result", nstart = 10
    )
    
    # --- Extract and save meaningful results ---
    # Extract exposure matrix
    expos <- exposures(musica_from_counts, "result", "SBS96", "ex_result")
    write.csv(expos, "discovered_exposures.csv", row.names = TRUE)
    
    # Extract signature matrix
    sigs <- signatures(musica_from_counts, "result", "SBS96", "ex_result")
    write.csv(sigs, "discovered_signatures.csv", row.names = TRUE)
    
    # Save the complete musica object
    saveRDS(musica_from_counts, "musica_from_counts_results.rds")
    
    # Generate and save plots
    pdf("signatures_barplot.pdf", width = 10, height = 6)
    plot_signatures(musica_from_counts, model_id = "ex_result", modality = "SBS96")
    dev.off()
    
    pdf("exposures_barplot.pdf", width = 10, height = 6)
    plot_exposures(musica_from_counts, "ex_result", plot_type = "bar")
    dev.off()

    writeLines(c(
        '"BIOC_MUSICATK_COUNT_TABLE_WORKFLOW":',
        paste0('        musicatk: ', as.character(packageVersion("musicatk")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_count_table_workflow.csv versions.yml
    """
}

workflow BIOC_MUSICATK_COUNT_TABLE_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ luad_tcga_count_table.csv ] ]

    main:
    BIOC_MUSICATK_COUNT_TABLE_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MUSICATK_COUNT_TABLE_WORKFLOW.out.tables
    plots    = BIOC_MUSICATK_COUNT_TABLE_WORKFLOW.out.plots
    objects  = BIOC_MUSICATK_COUNT_TABLE_WORKFLOW.out.objects
    versions = BIOC_MUSICATK_COUNT_TABLE_WORKFLOW.out.versions
}
