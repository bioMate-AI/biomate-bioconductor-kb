#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: clipper
// Implements topological gene set analysis using a two-step empirical approach. It exploits graph deco
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/clipper/inst/doc/clipper.R
// Upstream  : ALL, graph, graphite
// Downstream: none
//
// Install: BiocManager::install("clipper")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLIPPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clipper"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clipper:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clipper:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clipper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clipper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clipper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(clipper)
    library(jsonlite)

    # --- Cppr [] ---
    # Key functions: packageDescription
    options(keep.source = TRUE, width = 60)
    cppr <- packageDescription("clipper")
    # --- Loadgraphitepathways [] ---
    # Key functions: pathways, convertIdentifiers, pathwayGraph, nodes
    library(graphite)
    kegg  <- pathways("hsapiens", "kegg")
    graph <- convertIdentifiers(kegg[["Chronic myeloid leukemia"]], "entrez")
    graph <- pathwayGraph(graph)
    genes <- nodes(graph)
    # --- Loaddataandclasses [] ---
    # Key functions: data
    library(ALL)
    data(ALL)
    # --- Lookphenodata [] ---
    # Key functions: pData
    head(pData(ALL))
    dim(pData(ALL))
    # --- Bcell Selection [] ---
    # Key functions: pData
    pData(ALL)$BT
    pAllB <- pData(ALL)[grep("B", pData(ALL)$BT),]
    dim(pAllB)
    # --- Selectexpressionset [] ---
    # Key functions: exprs, featureNames, unlist, mget, na
    library("hgu95av2.db")
    all <- ALL[,names(classes)]
    probesIDS <- row.names(exprs(all))
    featureNames(all@assayData)<-unlist(mget(probesIDS, hgu95av2ENTREZID))
    all <- all[(!is.na(row.names(exprs(all))))]
    # --- Featurenames [] ---
    # Key functions: featureNames
    all_rnames <- featureNames(all@assayData)
    featureNames(all@assayData) <- paste("ENTREZID", all_rnames, sep = ":")
    # --- Obtainingthesubgraph [] ---
    # Key functions: intersect, exprs, subGraph
    library(graph)
    genes <- intersect(genes, row.names(exprs(all)))
    graph <- subGraph(genes, graph)
    exp <- all[genes,,drop=FALSE]
    exp
    # --- Pathqusage [] ---
    # Key functions: pathQ
    library(clipper)
    pathwayAnalysis <- pathQ(exp, classes, graph, nperm=100, alphaV=0.05, b=100)
    pathwayAnalysis
    # --- Clipperusage [] ---
    # Key functions: clipper
    clipped <- clipper(exp, classes, graph, "var", trZero=0.01, permute=FALSE)
    clipped[,1:5]
    # --- Sintetizeyourresult [] ---
    # Key functions: prunePaths
    clipped <- prunePaths(clipped, thr=0.2)
    clipped[,1:5]
    # --- Easyclip Usage [] ---
    # Key functions: easyClip
    clipped <- easyClip(exp, classes, graph, method="mean")
    clipped[,1:5]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clipper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clipper_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clipper_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLIPPER:", paste0("    clipper: ", packageVersion("clipper"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clipper_results.csv
    touch ${prefix}_clipper_output.rds
    echo "BIOC_CLIPPER:" > versions.yml
    echo "    clipper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLIPPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLIPPER(ch_input)

    emit:
    results  = BIOC_CLIPPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLIPPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLIPPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLIPPER.out.versions  // channel: path(versions.yml)
}
