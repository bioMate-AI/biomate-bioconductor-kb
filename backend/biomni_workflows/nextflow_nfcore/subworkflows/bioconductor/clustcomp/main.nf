#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: clustComp
// clustComp is a package that implements several techniques for the comparison and visualisation of re
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/clustComp/inst/doc/clustComp.R
// Upstream  : Biobase, colonCA
// Downstream: none
//
// Install: BiocManager::install("clustComp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUSTCOMP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clustcomp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clustcomp:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clustcomp:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clustcomp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clustcomp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clustcomp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SCmapping)
    library(jsonlite)

    # --- Loaddata [] ---
    # Key functions: data
    library(Biobase)
    library(colonCA)
    data(colonCA)
    # --- Comparisonflatvsflat1 [] ---
    # Key functions: flatVSflat
    flatVSflat( flat1, flat2, line.wd = 5, h.min = 0.3, greedy = FALSE)
    # --- Fig01 [] ---
    # Key functions: bitmap, flatVSflat, off
    bitmap("fig01.png", height = 4, width = 4, pointsize = 10, res = 300)
    flatVSflat(flat1, flat2, line.wd = 5, h.min = 0.3, greedy = FALSE)
    dev.off()
    # --- flat V Sflat [] ---
    # Key functions: flatVSflat
    flatVSflat(flat1, flat2, coord1=c(6,3,4,7,5,1,2),
        coord2=c(5,1,4,6,3,2), greedy = FALSE)
    # --- bitmap [] ---
    # Key functions: bitmap, flatVSflat, off
    bitmap("fig01a.png",height=4,width=4,pointsize=10,res=300)
    flatVSflat(flat1, flat2, coord1=c(6,3,4,7,5,1,2), coord2=c(5,1,4,6,3,2),
        greedy = FALSE)
    dev.off()
    # --- Comparisonflatvsflat2 [] ---
    # Key functions: flatVSflat
    flatVSflat(flat1, flat2, evenly=TRUE, horiz=TRUE, greedy = FALSE)
    # --- Fig02 [] ---
    # Key functions: bitmap, flatVSflat, off
    bitmap("fig02.png",height=4,width=4,pointsize=10,res=300)
    flatVSflat(flat1, flat2, evenly=TRUE, horiz=TRUE, greedy = FALSE)
    dev.off()
    # --- Greedyalgorithm [] ---
    # Key functions: SCmapping
    myMapping<-SCmapping(flat1, flat2)
    # --- Fig03 [] ---
    # Key functions: bitmap, SCmapping, off
    bitmap("fig03.png",height=4,width=7,pointsize=10,res=300)
    SCmapping(flat1,flat2)
    dev.off()
    # --- Comparisonflatvsflatgreedy [] ---
    # Key functions: flatVSflat
    flatVSflat( flat1, flat2, line.wd = 5, h.min = 0.3, greedy = TRUE)
    # --- Fig04 [] ---
    # Key functions: bitmap, flatVSflat, off
    bitmap("fig04.png", height = 4, width = 4, pointsize = 10, res = 300)
    flatVSflat(flat1, flat2, line.wd = 5, h.min = 0.3, greedy = TRUE)
    dev.off()
    # --- Aestheticsnolookahead [] ---
    # Key functions: flatVShier
    comparison.flatVShier.1<-flatVShier(hierar, flat1, verbose=FALSE,
        pausing=FALSE, score.function="crossing", greedy.colours=1:4,
        look.ahead=0)
    # --- Fig05 [] ---
    # Key functions: bitmap, flatVShier, off
    bitmap("fig05.png",height=6,width=8,pointsize=9,res=300)
    flatVShier(hierar,flat1,pausing=FALSE,verbose=FALSE,
        score.function="crossing",greedy.colours=1:4,look.ahead=0)
    dev.off()
    # --- Aestheticsnolookaheadexpanded [] ---
    # Key functions: flatVShier
    comparison.flatVShier.1<-flatVShier(hierar, flat1, verbose=FALSE,
        pausing=FALSE, score.function="crossing", greedy.colours=1:4,
        look.ahead=0, expanded=TRUE)
    # --- Fig06 [] ---
    # Key functions: bitmap, flatVShier, off
    bitmap("fig06.png",height=14,width=8,pointsize=9,res=300)
    flatVShier(hierar,flat1,pausing=FALSE,verbose=FALSE,
        score.function="crossing",greedy.colours=1:4,look.ahead=0,
        expanded=TRUE)
    dev.off()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clustcomp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clustcomp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clustcomp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLUSTCOMP:", paste0("    clustcomp: ", packageVersion("clustComp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clustcomp_results.csv
    touch ${prefix}_clustcomp_output.rds
    echo "BIOC_CLUSTCOMP:" > versions.yml
    echo "    clustcomp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLUSTCOMP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLUSTCOMP(ch_input)

    emit:
    results  = BIOC_CLUSTCOMP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLUSTCOMP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLUSTCOMP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLUSTCOMP.out.versions  // channel: path(versions.yml)
}
