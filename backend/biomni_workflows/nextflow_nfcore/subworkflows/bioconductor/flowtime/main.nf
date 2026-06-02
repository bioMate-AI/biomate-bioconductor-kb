#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowTime
// This package facilitates analysis of both timecourse and steady state flow cytometry experiments. Th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowTime/inst/doc/gating-vignette.R
// Upstream  : BiocManager, dplyr, flowClust, flowCore, flowStats
// Downstream: none
//
// Install: BiocManager::install("flowTime")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWTIME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowtime"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowtime:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowtime:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowtime_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowtime_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowtime_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Subset)
    library(jsonlite)

    # --- Flowset [] ---
    # Key functions: flowSet, csv, annotateFlowSet
    ---------------------------------------------------------------------
    data <- read.flowSet(path=system.file("extdata", "ss_example",
                            package = "flowTime"), alter.names = TRUE)
    annotation <- read.csv(system.file("extdata", "ss_example.csv",
                            package = "flowTime"))
    # --- Autoplot [] ---
    # Key functions: autoplot
    ---------------------------------------------------------------------
    autoplot(data[21:24], x = "FSC-A", y = "SSC-A")
    # --- Gate Quantile [] ---
    # Key functions: gate_quantile, autoplot, geom_gate
    ---------------------------------------------------------------------
    Debris <- gate_quantile(fr = data[[3]], channel = "FSC.A", probs = 0.99, filterId = "Debris")
    autoplot(data[[3]], x = "FSC-A") + geom_gate(Debris)
    # --- Autoplot [] ---
    # Key functions: autoplot, geom_gate, toTable, filter
    ---------------------------------------------------------------------
    autoplot(data[21:24], x = "FSC-A", "SSC-A") + geom_gate(Debris)
    toTable(summary(filter(data[c(3,21:24)], !Debris)))
    # --- Exprs [] ---
    # Key functions: exprs, fsApply, autoplot
    ---------------------------------------------------------------------
    #Initialize the single frame
    data.1frame <- data[[1]]
    #fill the single frame with the exprs data from each frame
    # in the flow set
    # --- Autoplot [] ---
    # Key functions: autoplot, scale_x_logicle, scale_y_logicle
    ---------------------------------------------------------------------
    autoplot(data.1frame, x = "FSC-A", "SSC-A") + scale_x_logicle() + scale_y_logicle()
    # --- Gate Flowclust 2D [] ---
    # Key functions: gate_flowClust_2d, autoplot, geom_gate
    ---------------------------------------------------------------------
    yeast <- gate_flowClust_2d(data.1frame, xChannel = "FSC.A",
                               yChannel =  "SSC.A", K = 1,
                               quantile = .95, min = c(0,0))
    autoplot(data.1frame, x = "FSC-A", y = "SSC-A") + geom_gate(yeast)
    # --- Transform [] ---
    # Key functions: transform
    ---------------------------------------------------------------------
    yeast <- transform(yeast, inv.trans)
    data.1frame <- transform(data.1frame, inv.trans)
    # --- Autoplot [] ---
    # Key functions: autoplot, geom_gate, output, filter, toTable
    ---------------------------------------------------------------------
    autoplot(data[c(1, 8, 16, 24, 32)], "FSC.A","SSC.A") +
      geom_gate(yeast)
    #invisible(capture.output(
      # we have to use this to prevent summary from printing
    # --- Autoplot [] ---
    # Key functions: autoplot, Subset, gate_singlet, geom_gate
    ---------------------------------------------------------------------
    autoplot(Subset(data.1frame, yeast), "FSC-A", "FSC-H")
    library(flowStats)
    chnl <- c("FSC-A", "FSC-H")
    singlets <- gate_singlet(x = Subset(data.1frame, yeast), area = "FSC.A",
    # --- Autoplot [] ---
    # Key functions: autoplot, geom_gate, facet_wrap, Subset
    ---------------------------------------------------------------------
    autoplot(data[c(1:4, 29:32)], x = "FSC-A", y = "FSC-H") +
      geom_gate(singlets) + facet_wrap("name", ncol = 4)
    autoplot(Subset(data[c(1:4, 29:32)], yeast & singlets), x = "FL1-A") +
      facet_wrap("name", ncol = 4)
    # --- Output [] ---
    # Key functions: output, filter, toTable, left_join, pData
    ---------------------------------------------------------------------
    invisible(capture.output(
      d <- summary(filter(data, yeast & singlets))))
    (e <- toTable(d))
    e <- left_join(e, pData(data), by = c("sample" = "name"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowtime_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowtime_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowtime_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWTIME:", paste0("    flowtime: ", packageVersion("flowTime"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowtime_results.csv
    touch ${prefix}_flowtime_output.rds
    echo "BIOC_FLOWTIME:" > versions.yml
    echo "    flowtime: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWTIME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWTIME(ch_input)

    emit:
    results  = BIOC_FLOWTIME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWTIME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWTIME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWTIME.out.versions  // channel: path(versions.yml)
}
