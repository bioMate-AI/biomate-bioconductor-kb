#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: diffbind — standard_differential_binding
// Perform a standard differential binding analysis comparing two groups using a single-factor design.
// Input: tamoxifen.csv, reads/Chr18_BT474_ER_1.bam, peaks/BT474_ER_1.bed.gz
// Container: quay.io/biocontainers/bioconductor-diffbind:3.20.0--r45ha27e39d_0
// R packages: DiffBind, magrittr, xtable
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: MA plot, PCA plot, volcano plot
// QC: diagnostic MA/PCA QC

nextflow.enable.dsl = 2

process BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-diffbind:3.20.0--r45ha27e39d_0"

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
    .bm_deps <- c("DiffBind", "magrittr", "xtable")
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
    library(DiffBind)
    library(magrittr)
    
    # Execute the standard differential binding workflow exactly as documented
    tamoxifen <- dba(sampleSheet="tamoxifen.csv") %>%
      dba.blacklist() %>%
      dba.count()     %>%
      dba.normalize() %>%
      dba.contrast()  %>%
      dba.analyze()
    
    # Retrieve the report of differentially bound sites
    tamoxifen.DB <- dba.report(tamoxifen)
    
    # Save the results to output files
    # --- Save the complete DBA object ---
    saveRDS(tamoxifen, file="tamoxifen_dba_object.rds")
    
    # --- Save the differential binding report as a CSV ---
    if (!is.null(tamoxifen.DB) && length(tamoxifen.DB) > 0) {
      write.csv(as.data.frame(tamoxifen.DB), file="tamoxifen_differential_binding_report.csv", row.names=FALSE)
    } else {
      write.csv(data.frame(Message="No significantly differentially bound sites found."), file="tamoxifen_differential_binding_report.csv", row.names=FALSE)
    }
    
    # --- Generate diagnostic and results plots ---
    pdf("tamoxifen_differential_binding_plots.pdf", width=8, height=8)
    
    tryCatch({
      plot(tamoxifen)
    }, error=function(e) {
      message("Could not generate correlation heatmap: ", e\$message)
    })
    
    tryCatch({
      dba.plotPCA(tamoxifen, label=DBA_CONDITION)
    }, error=function(e) {
      message("Could not generate PCA plot: ", e\$message)
    })
    
    tryCatch({
      dba.plotMA(tamoxifen)
    }, error=function(e) {
      message("Could not generate MA plot: ", e\$message)
    })
    
    tryCatch({
      dba.plotVolcano(tamoxifen)
    }, error=function(e) {
      message("Could not generate Volcano plot: ", e\$message)
    })
    
    dev.off()

    writeLines(c(
        '"BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING":',
        paste0('        diffbind: ', as.character(packageVersion("diffbind")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_differential_binding.csv versions.yml
    """
}

workflow BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tamoxifen.csv, reads/Chr18_BT474_ER_1.bam, peaks/BT474_ER_1.bed.gz ] ]

    main:
    BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING(ch_input)

    emit:
    tables   = BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING.out.tables
    plots    = BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING.out.plots
    objects  = BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING.out.objects
    versions = BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING.out.versions
}
