#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowStats
// Methods and functionality to analyse flow data that is beyond the basic infrastructure provided by t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowStats/inst/doc/GettingStartedWithFlowStats.R
// Upstream  : flowCore, flowWorkspace, ggcyto, ggridges, gridExtra
// Downstream: flowVS, highthroughputassays
//
// Install: BiocManager::install("flowStats")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWSTATS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowstats"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowstats:4.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowstats:4.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowstats_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowstats_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowstats_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GatingSet)
    library(Subset)
    library(jsonlite)

    # --- Loadgvhd [] ---
    # Key functions: data
    library(flowCore)
    library(flowStats)
    library(flowWorkspace)
    library(ggcyto)
    data(ITN)
    # --- Transform [] ---
    # Key functions: GatingSet, trans_new, transformerList, transform
    require(scales)
    gs <- GatingSet(ITN)
    trans.func <- asinh
    inv.func <- sinh
    trans.obj <- trans_new("myAsinh", trans.func, inv.func)
    # --- Lymphgate [] ---
    # Key functions: lymphGate, gs_cyto_data, gs_pop_add, recompute
    lg <- lymphGate(gs_cyto_data(gs), channels=c("CD3", "SSC"),
                    preselection="CD4", filterId="TCells",
                    scale=2.5)
    gs_pop_add(gs, lg)
    recompute(gs)
    # --- Lymphgateplot [] ---
    # Key functions: ggcyto, aes, geom_hex, geom_gate
    ggcyto(gs, aes(x = CD3, y = SSC)) + geom_hex(bins = 32) + geom_gate("TCells")
    # --- Variation [] ---
    # Key functions: gs_pop_get_data, ggplot, ggcyto
    require(ggridges)
    require(gridExtra)
    pars <- colnames(gs)[c(3,4,5,7)]
    data <- gs_pop_get_data(gs, "TCells")
    # --- Quad Gate [] ---
    # Key functions: quadrantGate, gs_pop_get_data, gs_pop_add, recompute
    qgate <- quadrantGate(gs_pop_get_data(gs, "TCells"), stains=c("CD4", "CD8"),
                          filterId="CD4CD8", sd=3)
    gs_pop_add(gs, qgate, parent = "TCells")
    recompute(gs)
    # --- Quad Gate Norm [] ---
    # Key functions: normalize
    gs <- normalize(gs, populations=c("CD4+CD8+", "CD4+CD8-", "CD4-CD8+", "CD4-CD8-"),
                         dims=c("CD4", "CD8"), minCountThreshold = 50)
    # --- Variation Norm [] ---
    # Key functions: gs_pop_get_data, ggplot, ggcyto, aes, geom_density_ridges, theme
    data <- gs_pop_get_data(gs, "TCells")
    # --- Quad Gate Norm Plot [] ---
    # Key functions: ggcyto, gs_pop_get_data, aes, geom_hex, geom_gate, gs_pop_get_gate
    ggcyto(gs_pop_get_data(gs, "TCells"), aes(x=CD4, y=CD8)) +
      geom_hex(bins=32) +
      geom_gate(gs_pop_get_gate(gs, "CD4-CD8-")) +
      geom_gate(gs_pop_get_gate(gs, "CD4-CD8+")) +
      geom_gate(gs_pop_get_gate(gs, "CD4+CD8-")) +
    # --- Rangegate [] ---
    # Key functions: rangeGate, gs_cyto_data, gs_pop_add, recompute
    CD69rg <- rangeGate(gs_cyto_data(gs), stain="CD69",
                        alpha=0.75, filterId="CD4+CD8-CD69", sd=2.5)
    gs_pop_add(gs, CD69rg, parent="CD4+CD8-")
    # gs_pop_add(gs, CD69rg, parent="CD4+CD8-", name = "CD4+CD8-CD69-", negated=TRUE)
    recompute(gs)
    # --- Rangegateplot [] ---
    # Key functions: ggcyto, gs_pop_get_data, aes, geom_density_ridges, theme, element_blank, geom_vline, facet_null
    ggcyto(gs_pop_get_data(gs, "CD4+CD8-"), aes(x=CD69, fill = GroupID)) +
        geom_density_ridges(mapping = aes(y = name), alpha = 0.4) +
        theme(axis.title.y = element_blank(),
              axis.text.y = element_blank(),
              axis.ticks.y = element_blank()) +
    # --- Rangegate Norm [] ---
    # Key functions: normalize
    gs <- normalize(gs, populations=c("CD4+CD8-CD69"),
                         dims=c("CD69"), minCountThreshold = 50)
    # --- Rangegate Norm Plot [] ---
    # Key functions: ggcyto, gs_pop_get_data, aes, geom_density_ridges, theme, element_blank, geom_vline, facet_null
    ggcyto(gs_pop_get_data(gs, "CD4+CD8-"), aes(x=CD69, fill = GroupID)) +
        geom_density_ridges(mapping = aes(y = name), alpha = 0.4) +
        theme(axis.title.y = element_blank(),
              axis.text.y = element_blank(),
              axis.ticks.y = element_blank()) +
    # --- Createdata [] ---
    # Key functions: gs_cyto_data
    dat <- gs_cyto_data(gs)
    # --- Rawdata [] ---
    # Key functions: autoplot, ggtitle
    autoplot(dat, "CD4", "CD8") +
      ggtitle("Experimental Dataset")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowstats_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowstats_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowstats_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWSTATS:", paste0("    flowstats: ", packageVersion("flowStats"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowstats_results.csv
    touch ${prefix}_flowstats_output.rds
    echo "BIOC_FLOWSTATS:" > versions.yml
    echo "    flowstats: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWSTATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWSTATS(ch_input)

    emit:
    results  = BIOC_FLOWSTATS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWSTATS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWSTATS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWSTATS.out.versions  // channel: path(versions.yml)
}
