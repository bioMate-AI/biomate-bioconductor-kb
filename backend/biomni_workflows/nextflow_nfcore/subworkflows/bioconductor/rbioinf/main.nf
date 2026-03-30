#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RBioinf
// Functions and datasets and examples to accompany the monograph R For Bioinformatics.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RBioinf/inst/doc/RBioinf.R
// Upstream  : Rgraphviz
// Downstream: none
//
// Install: BiocManager::install("RBioinf")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBIOINF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rbioinf"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rbioinf:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rbioinf:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rbioinf_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rbioinf_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rbioinf_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(LPO)
    library(jsonlite)

    # --- Ex1 [] ---
    # Key functions: setClass, LPO
    library(RBioinf)
    setClass("object")
    setClass("grid-layout", contains="object")
    setClass("horizontal-grid", contains="grid-layout")
    setClass("vertical-grid", contains="grid-layout")
    # --- Cpotest [] ---
    # Key functions: computeClassLinearization
    computeClassLinearization("object")
    computeClassLinearization("grid-layout")
    computeClassLinearization("vertical-grid")
    # --- set Class [] ---
    # Key functions: setClass, LPO
    setClass("vh-grid", contains=c("vertical-grid", "horizontal-grid"))
    setClass("confused", contains=c("hv-grid", "vh-grid"))
    LPO("vh-grid")
    tryCatch(LPO("confused"), error=function(x) "this one failed")
    # --- Plotconfg [] ---
    # Key functions: class2Graph, makeNodeAttrs
    library(Rgraphviz)
     confG = class2Graph("confused")
     cGa = makeNodeAttrs(confG, shape="ellipse", fill="grey", width=4)
     plot(confG, nodeAttrs=cGa)
    # --- Showextends [] ---
    # Key functions: setClass, extends
    setClass("a")
     setClass("b")
     setClass("c", contains = c("a", "b"))
     setClass("d", contains = c("b", "a"))
     extends("c")
    # --- Scdemo [] ---
    # Key functions: getAllSuperClasses, getClass, superClassDepth, superClasses
    getAllSuperClasses(getClass("e"))
    cD = superClassDepth(getClass("e"))
    cD$label
    cD$depth
    superClasses(getClass("e"))
    # --- class2 Graph [] ---
    # Key functions: class2Graph
    cH = class2Graph("e")
    # --- Editwin [] ---
    # Key functions: setClass
    setClass("pane", contains="object")
     setClass("editing-mixin", contains="object")
     setClass("scrolling-mixin", contains="object")
     setClass("scrollable-pane", contains=c("pane", "scrolling-mixin"))
     setClass("editable-pane", contains=c("pane", "editing-mixin"))
    # --- Lposew [] ---
    # Key functions: LPO
    LPO("editable-scrollable-pane")
    LPO("editable-scrollable-pane", C3=TRUE)
    # --- Ewgraph [] ---
    # Key functions: class2Graph, makeNodeAttrs
    eWG = class2Graph("editable-scrollable-pane")
     eWGattrs = makeNodeAttrs(eWG, shape="ellipse", fill="grey", width=4)
     plot(eWG, nodeAttrs=eWGattrs)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rbioinf_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rbioinf_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rbioinf_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RBIOINF:", paste0("    rbioinf: ", packageVersion("RBioinf"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rbioinf_results.csv
    touch ${prefix}_rbioinf_output.rds
    echo "BIOC_RBIOINF:" > versions.yml
    echo "    rbioinf: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RBIOINF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RBIOINF(ch_input)

    emit:
    results  = BIOC_RBIOINF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RBIOINF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RBIOINF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RBIOINF.out.versions  // channel: path(versions.yml)
}
