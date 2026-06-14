#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: openprimer — analyze_primers
// Evaluate the physicochemical properties, coverage, and constraint fulfillment of an existing primer set against template sequences.
// Input: templates.fasta, primers.fasta, settings.xml
// Container: quay.io/biocontainers/bioconductor-openprimer:1.32.0--r45hdfd78af_0
// R packages: openPrimeR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPENPRIMER_ANALYZE_PRIMERS {
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
    
    # Load required library
    library(openPrimeR)
    
    # --- Load templates and assign binding regions ---
    template.df <- read_templates("templates.fasta")
    template.df <- assign_binding_regions(template.df, fw = c(1, 30), rev = c(1, 30))
    
    # --- Load existing primers using read_primers() ---
    primer.df <- read_primers("primers.fasta", fw.id = "_fw")
    
    # --- Load settings and evaluate constraints using ---
    settings <- read_settings("settings.xml")
    conOptions(settings)\$allowed_other_binding_ratio <- c("max" = 1.0)
    constraint.df <- check_constraints(primer.df, template.df, settings, active.constraints = names(constraints(settings)))
    
    # Save raw constraint evaluation results
    saveRDS(constraint.df, "constraint_results.rds")
    
    # --- Update template coverage using update_template_cvg() ---
    template.df <- update_template_cvg(template.df, constraint.df)
    
    # --- Compute coverage statistics and ratios using ---
    cvg_ratio_val <- as.numeric(get_cvg_ratio(constraint.df, template.df))
    cvg.stats <- get_cvg_stats(constraint.df, template.df, for.viewing = TRUE)
    write.csv(cvg.stats, "coverage_stats.csv", row.names = FALSE)
    
    # --- Plot coverage and binding regions using ---
    pdf("plots.pdf", width = 8, height = 8)
    plot_template_cvg(constraint.df, template.df)
    plot_primer_binding_regions(constraint.df, template.df)
    
    # Safe subsetting for plot_primer to avoid out-of-bounds errors
    plot_primer_templates <- template.df[seq_len(min(10, nrow(template.df))), ]
    plot_primer(constraint.df[1,], plot_primer_templates)
    
    # --- Compute optimal primer subsets using subset_primer_set() ---
    primer.subsets <- subset_primer_set(constraint.df, template.df)
    plot_primer_subsets(primer.subsets, template.df)
    
    # Safe subsetting for my.primer.subset
    if (length(primer.subsets) >= 3) {
      my.primer.subset <- primer.subsets[[3]]
    } else {
      my.primer.subset <- primer.subsets[[length(primer.subsets)]]
    }
    
    original.cvg <- as.character(get_cvg_ratio(constraint.df, template.df, as.char = TRUE))
    subset.cvg <- as.character(get_cvg_ratio(my.primer.subset, template.df, as.char = TRUE))
    
    # --- Visualize constraint fulfillment using ---
    plot_constraint_fulfillment(constraint.df, settings)
    plot_constraint(constraint.df, settings, "gc_clamp")
    dev.off()
    
    # --- Filter primers using filter_primers() ---
    filtered.df <- filter_primers(constraint.df, template.df, settings, active.constraints = c("gc_clamp", "gc_ratio"))
    write.csv(filtered.df, "filtered_primers.csv", row.names = FALSE)
    
    # --- Generate a PDF report using create_report() ---
    my.file <- "primer_analysis_report.pdf"
    tryCatch({
      create_report(constraint.df, template.df, my.file, settings, sample.name = "My analysis")
    }, error = function(e) {
      warning("Could not generate PDF report: ", e\$message)
    })

    writeLines(c(
        '"BIOC_OPENPRIMER_ANALYZE_PRIMERS":',
        paste0('        openprimer: ', as.character(packageVersion("openprimer")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_analyze_primers.csv versions.yml
    """
}

workflow BIOC_OPENPRIMER_ANALYZE_PRIMERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ templates.fasta, primers.fasta, settings.xml ] ]

    main:
    BIOC_OPENPRIMER_ANALYZE_PRIMERS(ch_input)

    emit:
    tables   = BIOC_OPENPRIMER_ANALYZE_PRIMERS.out.tables
    plots    = BIOC_OPENPRIMER_ANALYZE_PRIMERS.out.plots
    objects  = BIOC_OPENPRIMER_ANALYZE_PRIMERS.out.objects
    versions = BIOC_OPENPRIMER_ANALYZE_PRIMERS.out.versions
}
