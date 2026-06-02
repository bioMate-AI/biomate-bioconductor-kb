#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ggcyto
// With the dedicated fortify method implemented for flowSet, ncdfFlowSet and GatingSet classes, both r
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ggcyto/inst/doc/Top_features_of_ggcyto.R
// Upstream  : knitr
// Downstream: flowGate
//
// Install: BiocManager::install("ggcyto")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGCYTO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ggcyto"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ggcyto:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ggcyto:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ggcyto_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ggcyto_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ggcyto_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ggcyto)
    library(jsonlite)

    # --- Load Gs [] ---
    # Key functions: load_gs, files, attr, ggplot, aes, geom_hex, scale_fill_gradientn, colors
    ---------------------------------------------------------------------
    gs <- load_gs(list.files(dataDir, pattern = "gs_manual",full = TRUE))
    attr(gs, "subset") <- "CD3+"
    ggplot(gs, aes(x = `<B710-A>`, y = `<R780-A>`)) + geom_hex(bins = 128) + scale_fill_gradientn(colours = gray.colors(9))
    # --- Gs Pop Get Data [] ---
    # Key functions: gs_pop_get_data, ggplot, aes, geom_density
    ---------------------------------------------------------------------
    fs <- gs_pop_get_data(gs, "CD3+")
    ggplot(fs, aes(x = `<B710-A>`)) + geom_density(fill = "blue", alpha= 0.5)
    # --- Filterlist [] ---
    # Key functions: filterList, gs_pop_get_gate, ggplot, aes, geom_hex, geom_polygon
    ---------------------------------------------------------------------
    gates <- filterList(gs_pop_get_gate(gs, "CD8"))
    ggplot(gs, aes(x = `<B710-A>`, y = `<R780-A>`)) + geom_hex(bins = 128) + geom_polygon(data = gates, fill = NA, col = "purple")
    # --- Ggcyto [] ---
    # Key functions: ggcyto, aes, geom_hex, geom_gate
    ---------------------------------------------------------------------
    ggcyto(gs, aes(x = CD4, y = CD8)) + geom_hex(bins = 128) + geom_gate("CD8")
    # --- Autoplot [] ---
    # Key functions: autoplot
    ---------------------------------------------------------------------
    #1d
    autoplot(fs, "CD4")
    #2d
    autoplot(fs, "CD4", "CD8", bins = 64)
    # --- Data [] ---
    # Key functions: autoplot, scale_x_logicle, scale_x_flowJo_fasinh, scale_x_flowJo_biexp
    ---------------------------------------------------------------------
    data(GvHD)
    fr <- GvHD[[1]]
    p <- autoplot(fr, "FL1-H")
    p #raw scale
    # --- Autoplot [] ---
    # Key functions: autoplot, ggcyto_par_set, gate_mindensity, geom_gate, rectangleGate, gh_pop_get_gate
    ---------------------------------------------------------------------
    fr <- fs[[1]]
    p <- autoplot(fr,"CD4", "CD8") + ggcyto_par_set(limits = "instrument")
    #1d gate vertical
    gate_1d_v <- openCyto::gate_mindensity(fr, "<B710-A>")
    # --- Ggcyto [] ---
    # Key functions: ggcyto, aes, geom_hex, geom_gate, geom_stats
    ---------------------------------------------------------------------
    p <- ggcyto(gs, aes(x = "CD4", y = "CD8"), subset = "CD3+") + geom_hex()
    p + geom_gate("CD4") + geom_stats()
    p + geom_gate("CD4") + geom_stats(type = "count") #display cell counts
    # --- Axis X Inverse Trans [] ---
    # Key functions: axis_x_inverse_trans
    ---------------------------------------------------------------------
    p # axis display the transformed values
    p + axis_x_inverse_trans() # restore the x axis to the raw values
    # --- Ggcyto Par Set [] ---
    # Key functions: ggcyto_par_set
    ---------------------------------------------------------------------
    p <- p + ggcyto_par_set(limits = "instrument")
    p
    # --- Labs Cyto [] ---
    # Key functions: labs_cyto
    ---------------------------------------------------------------------
    p + labs_cyto("markers")
    # --- Ggcyto Par Set [] ---
    # Key functions: ggcyto_par_set, facet_wrap, scale_fill_gradientn, pal, labs_cyto, later
    ---------------------------------------------------------------------
    #put all the customized settings in one layer
    mySettings <- ggcyto_par_set(limits = "instrument"
                                 , facet = facet_wrap("name")
                                 , hex_fill = scale_fill_gradientn(colours = rev(RColorBrewer::brewer.pal(11, "Spectral")))
    # --- Class [] ---
    # Key functions: ggplot
    ---------------------------------------------------------------------
    class(p) # may not fully compatile with all the `ggplot` functions
    p1 <- as.ggplot(p)
    class(p1) # a pure ggplot object, thus can work with all the `ggplot` features
    # --- Ggcyto Arrange [] ---
    # Key functions: ggcyto_arrange
    ---------------------------------------------------------------------
    gt <- ggcyto_arrange(p, nrow = 1)
    class(gt)
    plot(gt)
    # --- Autoplot [] ---
    # Key functions: autoplot, gh_pop_get_data, ggcyto_arrange, gtable_rbind
    ---------------------------------------------------------------------
    p2 <- autoplot(gh_pop_get_data(gh, "CD3+")[,5:8]) # some density plot
    p2@arrange.main <- ""#clear the default title
    gt2 <- ggcyto_arrange(p2, nrow = 1)
    gt3 <- gridExtra::gtable_rbind(gt, gt2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ggcyto_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ggcyto_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ggcyto_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GGCYTO:", paste0("    ggcyto: ", packageVersion("ggcyto"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggcyto_results.csv
    touch ${prefix}_ggcyto_output.rds
    echo "BIOC_GGCYTO:" > versions.yml
    echo "    ggcyto: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GGCYTO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GGCYTO(ch_input)

    emit:
    results  = BIOC_GGCYTO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GGCYTO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GGCYTO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GGCYTO.out.versions  // channel: path(versions.yml)
}
