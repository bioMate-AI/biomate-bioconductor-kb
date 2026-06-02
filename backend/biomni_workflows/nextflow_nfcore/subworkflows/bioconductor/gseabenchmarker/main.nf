#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSEABenchmarkeR
// The GSEABenchmarkeR package implements an extendable framework for reproducible evaluation of set- a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSEABenchmarkeR/inst/doc/GSEABenchmarkeR.R
// Upstream  : EnrichmentBrowser
// Downstream: none
//
// Install: BiocManager::install("GSEABenchmarkeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSEABENCHMARKER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gseabenchmarker"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gseabenchmarker:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gseabenchmarker:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gseabenchmarker_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gseabenchmarker_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gseabenchmarker_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GSEABenchmarkeR)
    library(jsonlite)


    # --- Ma Comp [] ---
    # Key functions: loadEData, geo2kegg, maPreproc
    geo2kegg <- loadEData("geo2kegg")
    names(geo2kegg)
    geo2kegg[[1]]
    geo2kegg <- maPreproc(geo2kegg[1:5])
    geo2kegg[[1]]

    # --- Ma Groups [] ---
    # Key functions: loadEData, tcga, extdata, myEData
    se <- geo2kegg[[1]]
    table(se$GROUP)
    tcga <- loadEData("tcga", nr.datasets=2)
    names(tcga)
    brca <- tcga[[2]]
    brca
    table(brca$GROUP)
    data.dir <- system.file("extdata", package="GSEABenchmarkeR")
    edat.dir <- file.path(data.dir, "myEData")
    edat <- loadEData(edat.dir)
    names(edat)
    edat[[1]]

    # --- Differential Expression Ana [] ---
    # Key functions: runDE, rowData, limma, flexible, getGenesets, hsa, kegg, runEA
    geo2kegg <- runDE(geo2kegg, de.method="limma", padj.method="flexible")
    rowData(geo2kegg[[1]], use.names=TRUE)
    library(EnrichmentBrowser)
    kegg.gs <- getGenesets(org="hsa", db="kegg")
    kegg.ora.res <- runEA(geo2kegg[[1]], method="ora", gs=kegg.gs, perm=0)
    kegg.ora.res
    res.dir <- tempdir()
    res <- runEA(geo2kegg, methods=c("ora", "camera"), 
                    gs=kegg.gs, perm=0, save2file=TRUE, out.dir=res.dir)
    res$ora[1:2]

    ## -----------------------------------------------------------------------------
    method <- function(se, gs)
    # --- Read Rt [] ---
    # Key functions: readResults, ora, camera, runtime, bpPlot, lengths, ranking
    ea.rtimes <- readResults(res.dir, names(geo2kegg), 
                                methods=c("ora", "camera"), type="runtime")
    ea.rtimes
    bpPlot(ea.rtimes, what="runtime")
    mean(ea.rtimes$ora) / mean(ea.rtimes$camera)
    ea.ranks <- readResults(res.dir, names(geo2kegg), 
                                methods=c("ora", "camera"), type="ranking")
    lengths(ea.ranks)
    ea.ranks$ora[1:2]

    # --- Plot Adj Sig Sets [] ---
    # Key functions: evalNrSigSets, bpPlot, sig.sets, readRDS, malacards, readDataId2diseaseCodeMap, evalRelevance
    sig.sets <- evalNrSigSets(ea.ranks, alpha=0.05, padj="BH")
    sig.sets
    bpPlot(sig.sets, what="sig.sets")
    mala.kegg.file <- file.path(data.dir, "malacards", "KEGG.rds")
    mala.kegg <- readRDS(mala.kegg.file)
    sapply(mala.kegg, nrow)
    mala.kegg$ALZ
    mala.kegg$BRCA
    d2d.file <- file.path(data.dir, "malacards", "GseId2Disease.txt")
    d2d.map <- readDataId2diseaseCodeMap(d2d.file)
    head(d2d.map)
    ea.ranks$ora$GSE1297
    obs.score <- evalRelevance(ea.ranks$ora$GSE1297, mala.kegg$ALZ)
    obs.score

    # --- Comp Rand [] ---
    # Key functions: substring, compRand, summary, compOpt, evalRelevance, bpPlot, runif, rel.sets
    gs.names <- ea.ranks$ora$GSE1297$GENE.SET
    gs.ids <- substring(gs.names, 1, 8)
    rand.scores <- compRand(mala.kegg$ALZ, gs.ids, perm=50)
    summary(rand.scores)
    (sum(rand.scores >= obs.score) + 1) / 51
    opt.score <- compOpt(mala.kegg$ALZ, gs.ids)
    opt.score
    round(obs.score / opt.score * 100, digits=2)
    all.kegg.res <- evalRelevance(ea.ranks, mala.kegg, d2d.map[names(geo2kegg)])
    bpPlot(all.kegg.res, what="rel.sets")

    ## -----------------------------------------------------------------------------
    rel.ranks <- mala.kegg$ALZ[,1:2]
    rel.ranks$REL.SCORE <- runif(nrow(rel.ranks), min=1, max=100)
    rel.ranks$REL.SCORE <- round(rel.ranks$REL.SCORE, digits = 2)
    ind <- order(rel.ranks$REL.SCORE, decreasing = TRUE)
    rel.ranks <- rel.ranks[ind,]
    rel.ranks
    cacheResource(geo2kegg, rname="geo2kegg")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gseabenchmarker_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gseabenchmarker_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gseabenchmarker_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSEABENCHMARKER:", paste0("    gseabenchmarker: ", packageVersion("GSEABenchmarkeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gseabenchmarker_results.csv
    touch ${prefix}_gseabenchmarker_output.rds
    echo "BIOC_GSEABENCHMARKER:" > versions.yml
    echo "    gseabenchmarker: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSEABENCHMARKER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GSEABENCHMARKER(ch_input)

    emit:
    results  = BIOC_GSEABENCHMARKER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSEABENCHMARKER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSEABENCHMARKER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSEABENCHMARKER.out.versions  // channel: path(versions.yml)
}
