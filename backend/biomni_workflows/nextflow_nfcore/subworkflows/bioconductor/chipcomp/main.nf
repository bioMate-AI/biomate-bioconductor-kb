#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipcomp — differential_binding_analysis
// Detect differentially bound sharp binding sites between two conditions using ChIP-seq and matching control data.
// Input: conf.csv, *.bed
// Container: quay.io/biocontainers/bioconductor-chipcomp:1.40.0--r45h01b2380_0
// R packages: ChIPComp
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_CHIPCOMP_DIFFERENTIAL_BINDING_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chipcomp:1.40.0--r45h01b2380_0"

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
    .bm_deps <- c("ChIPComp")
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
    
    # Load the required library
    library(ChIPComp)
    
    # --- Load configuration and design matrix using makeConf ---
    confs=makeConf("conf.csv")
    conf=confs\$conf
    design=confs\$design
    
    # --- Merge binding sites and count reads using makeCountSet ---
    countSet=makeCountSet(conf,design,filetype="bed", species="hg19",binsize=1000)
    
    # --- Plot correlation between ChIP and control samples using ---
    pdf("chipcomp_correlation_plots.pdf", width=8, height=8)
    plot(countSet)
    dev.off()
    
    # --- Perform hypothesis testing for differential binding using ---
    countSet=ChIPComp(countSet)
    print(countSet)
    
    # Save meaningful results
    saveRDS(countSet, file="chipcomp_results.rds")
    
    # Export results to CSV
    exported <- FALSE
    tryCatch({
      results_df <- as.data.frame(countSet)
      write.csv(results_df, "chipcomp_differential_binding_results.csv", row.names=FALSE)
      exported <- TRUE
    }, error = function(e) {})
    
    if (!exported) {
      tryCatch({
        if (.hasSlot(countSet, "db")) {
          write.csv(as.data.frame(countSet@db), "chipcomp_differential_binding_results.csv", row.names=FALSE)
          exported <- TRUE
        }
      }, error = function(e) {})
    }
    
    if (!exported) {
      writeLines(capture.output(print(countSet)), "chipcomp_results_print.txt")
    }

    writeLines(c(
        '"BIOC_CHIPCOMP_DIFFERENTIAL_BINDING_ANALYSIS":',
        paste0('        chipcomp: ', as.character(packageVersion("chipcomp")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_binding_analysis.csv versions.yml
    """
}

workflow BIOC_CHIPCOMP_DIFFERENTIAL_BINDING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ conf.csv, *.bed ] ]

    main:
    BIOC_CHIPCOMP_DIFFERENTIAL_BINDING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CHIPCOMP_DIFFERENTIAL_BINDING_ANALYSIS.out.tables
    plots    = BIOC_CHIPCOMP_DIFFERENTIAL_BINDING_ANALYSIS.out.plots
    objects  = BIOC_CHIPCOMP_DIFFERENTIAL_BINDING_ANALYSIS.out.objects
    versions = BIOC_CHIPCOMP_DIFFERENTIAL_BINDING_ANALYSIS.out.versions
}
