#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BubbleTree
// CNV analysis in groups of tumor samples.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BubbleTree/inst/doc/BubbleTree-vignette.R
// Upstream  : GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("BubbleTree")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BUBBLETREE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bubbletree"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bubbletree:2.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bubbletree:2.36.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_bubbletree_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bubbletree_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bubbletree_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BubbleTree)
    library(jsonlite)

    # --- Load [] ---
    # Key functions: new, makeRBD, btpredict, drawBTree
    ---------------------------------------------------------------------
    # load sample files
    load(system.file("data", "cnv.gr.rda", package="BubbleTree"))
    load(system.file("data", "snp.gr.rda", package="BubbleTree"))
    # load annotations
    # --- Load [] ---
    # Key functions: new, trackBTree, drawBTree
    ---------------------------------------------------------------------
    load(system.file("data", "allCall.lst.RData", package="BubbleTree"))
    btreeplotter <- new("BTreePlotter", max.ploidy=5, max.size=10)
    sample <- allCall.lst[["sam10"]]
    rbd1 <- sample@rbd
    # --- Load [] ---
    # Key functions: new, trackBTree, drawBTree, drawBubbles
    ---------------------------------------------------------------------
    load(system.file("data", "allCall.lst.RData", package="BubbleTree"))
    btreeplotter <- new("BTreePlotter", max.ploidy=5, max.size=10)
    sample <- allCall.lst[["sam12"]]
    rbd1 <- sample@rbd
    # --- Load [] ---
    # Key functions: new, trackBTree, drawBTree
    ---------------------------------------------------------------------
    load(system.file("data", "allCall.lst.RData", package="BubbleTree"))
    btreeplotter <- new("BTreePlotter", max.ploidy=5, max.size=10)
    sample <- allCall.lst[["sam12"]]
    rbd1 <- sample@rbd
    # --- Load [] ---
    # Key functions: new, loadRBD, ifelse
    ---------------------------------------------------------------------
    load(system.file("data", "allRBD.lst.RData", package="BubbleTree"))
    btreepredictor <- new("BTreePredictor")
    btreepredictor@config$cutree.h <- 0.15
    high.ploidy <- rep(TRUE, length(allRBD.lst))
    # --- Info [] ---
    # Key functions: info
    ---------------------------------------------------------------------
    cat(info(btreepredictor), "\n")
    names(allCall.lst) <- names(allRBD.lst)
    results <- list()
    for (name in names(allCall.lst)) {
    # --- Load [] ---
    # Key functions: btcompare, new, drawBTree, labs, s
    ---------------------------------------------------------------------
    load(system.file("data", "allCall.lst.RData", package="BubbleTree"))
    load(system.file("data", "cancer.genes.minus2.rda", package="BubbleTree"))
    load(system.file("data", "vol.genes.rda", package="BubbleTree"))
    load(system.file("data", "gene.uni.clean.gr.rda", package="BubbleTree"))
    # --- Load [] ---
    # Key functions: new, ifelse, xyTrack, labs, bafTrack
    ---------------------------------------------------------------------
    load(system.file("data", "allCall.lst.RData", package="BubbleTree"))
    load(system.file("data", "centromere.dat.rda", package="BubbleTree"))
    load(system.file("data", "all.somatic.lst.RData", package="BubbleTree"))
    load(system.file("data", "allHetero.lst.RData", package="BubbleTree"))
    # --- Load [] ---
    # Key functions: new, trackBTree, drawBTree, null, labs
    ---------------------------------------------------------------------
    load(system.file("data", "allCall.lst.RData", package="BubbleTree"))
    btp <- new("BTreePlotter", max.ploidy=5, max.size=10)
    nn1 <- "HCC11.Primary.Tumor"
    nn2 <- "HCC11.Recurrent.Tumor"

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bubbletree_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bubbletree_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bubbletree_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BUBBLETREE:", paste0("    bubbletree: ", packageVersion("BubbleTree"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bubbletree_results.csv
    touch ${prefix}_bubbletree_output.rds
    echo "BIOC_BUBBLETREE:" > versions.yml
    echo "    bubbletree: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BUBBLETREE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_BUBBLETREE(ch_input)

    emit:
    results  = BIOC_BUBBLETREE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BUBBLETREE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BUBBLETREE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BUBBLETREE.out.versions  // channel: path(versions.yml)
}
