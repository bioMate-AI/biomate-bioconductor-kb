#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: openprimer — analyze_primers
// Evaluate the physicochemical properties, coverage, and constraint fulfillment of an existing primer set against template sequences.
// Input: templates.fasta, primers.fasta, settings.xml
// Container: quay.io/biocontainers/bioconductor-openprimer:1.32.0--r45hdfd78af_0
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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(openPrimeR)
    
    # Stage 1: Load templates and assign binding regions
    template.df <- read_templates("templates.fasta")
    template.df <- assign_binding_regions(template.df, fw = c(1, 30), rev = c(1, 30))
    
    # Stage 2: Load existing primers using read_primers()
    primer.df <- read_primers("primers.fasta", fw.id = "_fw")
    
    # Stage 3: Load settings and evaluate constraints using check_constraints()
    settings <- read_settings("settings.xml")
    conOptions(settings)\$allowed_other_binding_ratio <- c("max" = 1.0)
    constraint.df <- check_constraints(primer.df, template.df, settings, active.constraints = names(constraints(settings)))
    
    # Save raw constraint evaluation results
    saveRDS(constraint.df, "constraint_results.rds")
    
    # Stage 4: Update template coverage using update_template_cvg()
    template.df <- update_template_cvg(template.df, constraint.df)
    
    # Stage 5: Compute coverage statistics and ratios using get_cvg_ratio() and get_cvg_stats()
    cvg_ratio_val <- as.numeric(get_cvg_ratio(constraint.df, template.df))
    cvg.stats <- get_cvg_stats(constraint.df, template.df, for.viewing = TRUE)
    write.csv(cvg.stats, "coverage_stats.csv", row.names = FALSE)
    
    # Stage 6: Plot coverage and binding regions using plot_template_cvg(), plot_primer_binding_regions(), and plot_primer()
    pdf("plots.pdf", width = 8, height = 8)
    plot_template_cvg(constraint.df, template.df)
    plot_primer_binding_regions(constraint.df, template.df)
    
    # Safe subsetting for plot_primer to avoid out-of-bounds errors
    plot_primer_templates <- template.df[seq_len(min(10, nrow(template.df))), ]
    plot_primer(constraint.df[1,], plot_primer_templates)
    
    # Stage 7: Compute optimal primer subsets using subset_primer_set() and plot them using plot_primer_subsets()
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
    
    # Stage 8: Visualize constraint fulfillment using plot_constraint_fulfillment() and plot_constraint()
    plot_constraint_fulfillment(constraint.df, settings)
    plot_constraint(constraint.df, settings, "gc_clamp")
    dev.off()
    
    # Stage 9: Filter primers using filter_primers()
    filtered.df <- filter_primers(constraint.df, template.df, settings, active.constraints = c("gc_clamp", "gc_ratio"))
    write.csv(filtered.df, "filtered_primers.csv", row.names = FALSE)
    
    # Stage 10: Generate a PDF report using create_report()
    my.file <- "primer_analysis_report.pdf"
    tryCatch({
      create_report(constraint.df, template.df, my.file, settings, sample.name = "My analysis")
    }, error = function(e) {
      warning("Could not generate PDF report: ", e\$message)
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_OPENPRIMER_ANALYZE_PRIMERS":
        openprimer: \$(Rscript -e 'cat(as.character(packageVersion("openprimer")))')
    END_VERSIONS
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
