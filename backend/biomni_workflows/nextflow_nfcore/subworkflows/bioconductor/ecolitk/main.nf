#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ecolitk
// Meta-data and tools to work with E. coli. The tools are mostly plotting functions to work with circu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ecolitk/inst/doc/ecolitk.R
// Upstream  : Biobase, ecoliLeucine, multtest
// Downstream: none
//
// Install: BiocManager::install("ecolitk")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ECOLITK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ecolitk"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ecolitk:1.78.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ecolitk:1.78.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ecolitk_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ecolitk_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ecolitk_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Macromolecules)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(ecoligenomeSYMBOL2AFFY)
    data(ecoligenomeCHRLOC)
    # --- Grep [] ---
    # Key functions: unlist
    lac.i <- grep("^lac", ls(ecoligenomeSYMBOL2AFFY))
    lac.symbol <- ls(ecoligenomeSYMBOL2AFFY)[lac.i]
    lac.affy <- unlist(lapply(lac.symbol, get, envir=ecoligenomeSYMBOL2AFFY))
    beg.end <- lapply(lac.affy, get, envir=ecoligenomeCHRLOC)
    beg.end <- matrix(unlist(beg.end), nc=2, byrow=TRUE)
    # --- Cplotcircle [] ---
    # Key functions: cPlotCircle
    cPlotCircle(main.inside = "E. coli - K12")
    # --- Cplotcircle [] ---
    # Key functions: cPlotCircle, polygonChrom
    cPlotCircle(main.inside = "E. coli - K12", main = "lac genes")
    polygonChrom(beg.end[, 1], beg.end[, 2], ecoli.len, 1, 1.4)
    # --- Frame [] ---
    # Key functions: frame, cPlotCircle, polygonChrom, rainbow
    l <- data.frame(x=c(0.470, 0.48), y=c(0.87, 0.90))
    cPlotCircle(xlim=range(l$x), ylim=range(l$y), main = "lac genes")
    polygonChrom(beg.end[, 1], beg.end[, 2], ecoli.len, 1, 1.007, col=rainbow(4))
    legend(0.47, 0.9, legend=lac.symbol, fill=rainbow(4))
    # --- Data [] ---
    # Key functions: mget, unlist, Macromolecules
    library(Biobase)
    data(ecoligenomeBNUM2STRAND)
    data(ecoligenomeBNUM)
    data(ecoligenomeBNUM2MULTIFUN)
    data(ecoligenomeCHRLOC)
    # --- Data [] ---
    # Key functions: mget, unname, unlist, na
    library(Biobase)
    data(ecoligenome.operon)
    data(ecoligenomeSYMBOL2AFFY)
    tmp <- mget(ecoligenome.operon$gene.name,
             ecoligenomeSYMBOL2AFFY, ifnotfound=NA)
    # --- Data [] ---
    # Key functions: data
    library(ecoliLeucine)
    data(ecoliLeucine)
    # --- Normalize [] ---
    # Key functions: normalize
    abatch.nqt <- normalize(ecoliLeucine, method="quantiles")
    # --- Computeexprsetoperon [] ---
    # Key functions: computeExprSet, unlist
    operons.eset <- computeExprSet(abatch.nqt,
                                   pmcorrect.method="pmonly",
                                   summary.method="medianpolish",
                                   ids = unlist(affyoperons))
    # --- Function [] ---
    # Key functions: test, pData, esApply, rawp2adjp
    library(multtest)
    my.ttest <- function(x, i, j) {
      pval <- t.test(x[i], x[j])$p.value
      return(pval)
    }
    # --- Split [] ---
    # Key functions: split
    operons.i <- split(seq(along=operons.ttest), ecoligenome.operon$operon.name)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ecolitk_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ecolitk_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ecolitk_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ECOLITK:", paste0("    ecolitk: ", packageVersion("ecolitk"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ecolitk_results.csv
    touch ${prefix}_ecolitk_output.rds
    echo "BIOC_ECOLITK:" > versions.yml
    echo "    ecolitk: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ECOLITK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ECOLITK(ch_input)

    emit:
    results  = BIOC_ECOLITK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ECOLITK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ECOLITK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ECOLITK.out.versions  // channel: path(versions.yml)
}
