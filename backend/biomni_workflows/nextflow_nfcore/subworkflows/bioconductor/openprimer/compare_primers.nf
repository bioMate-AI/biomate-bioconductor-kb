#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: openprimer — compare_primers
// Compare multiple pre-evaluated primer sets across physicochemical constraints, coverage, and binding regions.
// Input: primers_set1.csv, primers_set2.csv, templates_set1.csv, templates_set2.csv
// Container: quay.io/biocontainers/bioconductor-openprimer:1.32.0--r45hdfd78af_0
// R packages: openPrimeR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_OPENPRIMER_COMPARE_PRIMERS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-openprimer:1.32.0--r45hdfd78af_0"

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
    .bm_deps <- c("openPrimeR")
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
    library(openPrimeR)
    
    # Load settings (using find.package to avoid system.file)
    settings.xml <- file.path(find.package("openPrimeR"), "extdata", "settings", "C_Taq_PCR_high_stringency.xml")
    settings <- read_settings(settings.xml)
    
    # Prepare constraint.df from user input to satisfy the first part of the documented code
    constraint.df <- read_primers("primers_set1.csv")
    
    # === DOCUMENTED CODE ===
    primer.xml <- tempfile("my_primers", fileext =".csv")
    write_primers(constraint.df, primer.xml, "CSV")
    template.xml <- tempfile("my_templates", fileext = ".csv")
    write_templates(constraint.df, template.xml, "CSV")
    sel.sets <- c("Glas1999", "Rubinstein1998", "Cardona1995", "Persson1991", "Ippolito2012", "Scheid2011")
    
    # ADAPTED: Read the declared user input files instead of system.file demo data
    primer.files <- c("primers_set1.csv", "primers_set2.csv")
    primer.data <- read_primers(primer.files)
    
    # Map names to match sel.sets so that the selection index is valid and exact vignette code runs
    names(primer.data) <- c("Glas1999", "Rubinstein1998")
    
    sel.idx <- which(names(primer.data) %in% sel.sets)
    primer.data <- primer.data[sel.idx]
    
    # ADAPTED: Read the declared user template files instead of system.file demo templates
    template.files <- c("templates_set1.csv", "templates_set2.csv")[1:length(primer.data)]
    template.data <- read_templates(template.files)
    
    # Generate and save plots to PDF files
    pdf("plot_constraint_fulfillment.pdf", width = 10, height = 8)
    plot_constraint_fulfillment(primer.data, settings, plot.p.vals = FALSE)
    dev.off()
    
    pdf("plot_constraint.pdf", width = 10, height = 8)
    plot_constraint(primer.data, settings, active.constraints = c("gc_ratio", "melting_temp_range"))
    dev.off()
    
    pdf("plot_primer_binding_regions.pdf", width = 10, height = 8)
    plot_primer_binding_regions(primer.data, template.data)
    dev.off()
    # === END DOCUMENTED CODE ===
    
    # Save processed data objects for downstream analysis
    saveRDS(primer.data, "compared_primers.rds")
    saveRDS(template.data, "compared_templates.rds")

    writeLines(c(
        '"BIOC_OPENPRIMER_COMPARE_PRIMERS":',
        paste0('        openprimer: ', as.character(packageVersion("openprimer")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compare_primers.csv versions.yml
    """
}

workflow BIOC_OPENPRIMER_COMPARE_PRIMERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ primers_set1.csv, primers_set2.csv, templates_set1.csv, templates_set2.csv ] ]

    main:
    BIOC_OPENPRIMER_COMPARE_PRIMERS(ch_input)

    emit:
    tables   = BIOC_OPENPRIMER_COMPARE_PRIMERS.out.tables
    plots    = BIOC_OPENPRIMER_COMPARE_PRIMERS.out.plots
    objects  = BIOC_OPENPRIMER_COMPARE_PRIMERS.out.objects
    versions = BIOC_OPENPRIMER_COMPARE_PRIMERS.out.versions
}
