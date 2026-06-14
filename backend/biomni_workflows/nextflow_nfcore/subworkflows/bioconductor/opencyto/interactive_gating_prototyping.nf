#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: opencyto — interactive_gating_prototyping
// Interactively prototype and test individual gating methods on a GatingSet without writing a complete CSV template.
// Input: gs
// Container: quay.io/biocontainers/bioconductor-opencyto:2.22.0--r45ha27e39d_0
// R packages: flowWorkspace, openCyto
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-opencyto:2.22.0--r45ha27e39d_0"

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
    .bm_deps <- c("flowWorkspace", "openCyto")
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
    library(openCyto)
    library(flowWorkspace)
    
    # --- Load the pre-loaded, compensated, and transformed ---
    # In flowWorkspace, GatingSets are stored and loaded as directories.
    gs <- load_gs("gs")
    
    # --- Add a new population using gs_add_gating_method by ---
    gs_add_gating_method(gs, alias = "non-activated cd4",
                             pop = "--",
                             parent = "cd4",
                             dims = "CD38,HLA",
                             gating_method = "mindensity")
    
    # Save the GatingSet with the newly added gate
    save_gs(gs, path = "gs_with_prototype", overwrite = TRUE)
    
    # --- Visualize the updated gating tree to inspect the results ---
    pdf("plot_after_add.pdf")
    plot(gs[[1]])
    dev.off()
    
    # --- Remove the last added population using ---
    gs_remove_gating_method(gs)
    
    # --- Visualize the gating tree again to confirm removal ---
    pdf("plot_after_remove.pdf")
    plot(gs[[1]])
    dev.off()

    writeLines(c(
        '"BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING":',
        paste0('        opencyto: ', as.character(packageVersion("opencyto")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactive_gating_prototyping.csv versions.yml
    """
}

workflow BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gs ] ]

    main:
    BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING(ch_input)

    emit:
    tables   = BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING.out.tables
    plots    = BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING.out.plots
    objects  = BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING.out.objects
    versions = BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING.out.versions
}
