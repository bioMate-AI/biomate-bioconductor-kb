#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Heatplus
// Display a rectangular heatmap (intensity plot) of a data matrix. By default, both samples (columns) 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Heatplus/inst/doc/annHeatmap.R
// Upstream  : Biobase, limma, mva
// Downstream: phenoTest, tRanslatome, heatmapFlex
//
// Install: BiocManager::install("Heatplus")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HEATPLUS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-heatplus"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-heatplus:3.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-heatplus:3.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_heatplus_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_heatplus_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_heatplus_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Heatplus)
    library(jsonlite)

    # --- Setup01 [] ---
    # Key functions: data
    require(Biobase)
    data(sample.ExpressionSet)
    exdat = sample.ExpressionSet
    # --- Setup02 [] ---
    # Key functions: pData, lmFit, exprs, eBayes, topTable
    require(limma)
    design1 = model.matrix( ~ type, data=pData(exdat))
    lm1 = lmFit(exprs(exdat), design1)
    lm1 = eBayes(lm1)
    # --- Regheatmap1 [] ---
    # Key functions: regHeatmap, exprs
    require(Heatplus)
    reg1 = regHeatmap(exprs(exdat))
    plot(reg1)
    # --- Regheatmap2 [] ---
    # Key functions: regHeatmap, exprs
    reg2 = regHeatmap(exprs(exdat2), legend=2, col=heat.colors, breaks=-3:3)
    plot(reg2)
    # --- Regheatmap3 [] ---
    # Key functions: dist, hclust, regHeatmap, exprs
    corrdist = function(x) as.dist(1-cor(t(x)))
    hclust.avl = function(x) hclust(x, method="average")
    reg3 = regHeatmap(exprs(exdat2), legend=2, dendrogram =
      list(clustfun=hclust.avl, distfun=corrdist))
    plot(reg3)
    # --- Regheatmap4 [] ---
    # Key functions: regHeatmap, exprs
    reg4 = regHeatmap(exprs(exdat2), legend=3,
      dendrogram=list(Col=list(status="hide")))
    plot(reg4)
    # --- Annheatmap1 [] ---
    # Key functions: annHeatmap, exprs, pData
    ann1 = annHeatmap(exprs(exdat), ann=pData(exdat))
    plot(ann1)
    # --- Annheatmap2 [] ---
    # Key functions: annHeatmap, exprs, pData
    ann2 = annHeatmap(exprs(exdat2), ann=pData(exdat2),
    	cluster=list(cuth=5000))
    plot(ann2)
    # --- Annheatmap3 [] ---
    # Key functions: annHeatmap, exprs, pData
    ann3 = annHeatmap(exprs(exdat2), ann=pData(exdat2),
      cluster=list(cuth=7500, label=c("Control-like", "Case-like")))
    plot(ann3)
    # --- Setupx1 [] ---
    # Key functions: assayData
    SE = apply(get("se.exprs", assayData(exdat2)), 1, median)
    # --- Setupx2 [] ---
    # Key functions: exprs, pData, pt
    CO = cor(t(exprs(exdat2)), pData(exdat2)$score)
    df = nrow(exdat2)-2
    TT = sqrt(df) * CO/sqrt(1-CO^2)
    PV = 2*pt(-abs(TT), df=df)
    # --- Setupx3 [] ---
    # Key functions: mget, featureNames
    require(hgu95av2.db)
    allGO = as.list(mget(featureNames(exdat2), hgu95av2GO))
    isTransElong = sapply(allGO, function(x) "GO:0006414" %in% names(x))
    # --- Setupx4 [] ---
    # Key functions: frame
    annFeatures = data.frame(standard.errors=SE, sigCorScore=PV<0.05,
    isTransElong)
    # --- Annheatmap4 [] ---
    # Key functions: annHeatmap2, exprs, pData
    ann4 = annHeatmap2(exprs(exdat2),
      ann=list(Col=list(data=pData(exdat2)), Row=list(data=annFeatures)))
    plot(ann4)
    # --- Annheatmap5 [] ---
    # Key functions: annHeatmap2, exprs, pData
    ann4a = annHeatmap2(exprs(exdat2),
      ann=list(Col=list(data=pData(exdat2)), Row=list(data=annFeatures)),
      labels=list(Row=list(nrow=7), Col=list(nrow=2)))
    plot(ann4a)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_heatplus_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_heatplus_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_heatplus_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HEATPLUS:", paste0("    heatplus: ", packageVersion("Heatplus"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_heatplus_results.csv
    touch ${prefix}_heatplus_output.rds
    echo "BIOC_HEATPLUS:" > versions.yml
    echo "    heatplus: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HEATPLUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HEATPLUS(ch_input)

    emit:
    results  = BIOC_HEATPLUS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HEATPLUS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HEATPLUS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HEATPLUS.out.versions  // channel: path(versions.yml)
}
