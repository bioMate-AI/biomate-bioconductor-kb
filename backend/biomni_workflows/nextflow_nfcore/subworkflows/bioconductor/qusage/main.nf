#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: qusage
// This package is an implementation the Quantitative Set Analysis for Gene Expression (QuSAGE) method 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/qusage/inst/doc/qusage.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("qusage")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QUSAGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qusage"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qusage:2.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qusage:2.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qusage_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qusage_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qusage_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(qusage)
    library(jsonlite)

    # --- Labelssimple [] ---
    # Key functions: rep
    labels = c(rep("t0",17),rep("t1",17))
    labels
    # --- Qssimple [] ---
    # Key functions: qusage
    qs.results = qusage(eset, labels, contrast, ISG.geneSet)
    # --- Pvalsimple [] ---
    # Key functions: pVal
    pdf.pVal(qs.results)
    # --- Plotsimple [] ---
    # Key functions: getOption
    getOption("SweaveHooks")[["fig"]]()
    plot(qs.results, xlab="Gene Set Activation")
    # --- gmt [] ---
    # Key functions: gmt
    ##   MSIG.geneSets = read.gmt("c2.cp.kegg.v4.0.symbols.gmt")
    # --- qusage [] ---
    # Key functions: qusage, numPathways
    summary(MSIG.geneSets[1:5])
      MSIG.geneSets[2]
      qs.results.msig = qusage(eset, labels, contrast, MSIG.geneSets)
      numPathways(qs.results.msig)
    # --- Multihypcorr [] ---
    # Key functions: pVal, adjust
    p.vals = pdf.pVal(qs.results.msig)
      head(p.vals)
      q.vals = p.adjust(p.vals, method="fdr")
      head(q.vals)
    # --- Qstable [] ---
    # Key functions: qsTable
    qsTable(qs.results.msig, number=10)
    # --- Plotcis [] ---
    # Key functions: getOption
    getOption("SweaveHooks")[["fig"]]()
    par(mar=c(10,4,1,2))
    plot(qs.results.msig)
    # --- Twowayrun [] ---
    # Key functions: qusage
    sx.results  = qusage(eset, twoWay.labels, "sx.t1-sx.t0",
                           MSIG.geneSets, pairVector=pairs)
      asx.results = qusage(eset, twoWay.labels, "asx.t1-asx.t0",
                           MSIG.geneSets, pairVector=pairs)
    # --- Twocurvepval [] ---
    # Key functions: pVal
    p.vals = twoCurve.pVal(sx.results,asx.results)
      head(p.vals)
    # --- Twowaycomplex [] ---
    # Key functions: qusage, pVal
    asx.vs.sx = qusage(eset, twoWay.labels, "(sx.t1-sx.t0) - (asx.t1-asx.t0)",
                       MSIG.geneSets, pairVector=pairs)
      p.vals = pdf.pVal(asx.vs.sx)
      head(p.vals)
    # --- Twowaydensitycurvescode [] ---
    # Key functions: plotDensityCurves
    plotDensityCurves(asx.results,path.index=125,xlim=c(-0.2,0.5),
                        col=3,main="CYTOSOLIC DNA SENSING")
      plotDensityCurves(sx.results,path.index=125,col=2,add=T)
      plotDensityCurves(asx.vs.sx, path.index=125,col=1,add=T, lwd=3)
      legend("topleft", legend=c("asx","sx","asx-sx"),lty=1,col=c(2:3,1),
    # --- Twowaydensitycurves [] ---
    # Key functions: getOption, plotDensityCurves
    getOption("SweaveHooks")[["fig"]]()
      plotDensityCurves(asx.results,path.index=125,xlim=c(-0.2,0.5),
                        col=3,main="CYTOSOLIC DNA SENSING")
      plotDensityCurves(sx.results,path.index=125,col=2,add=T)
      plotDensityCurves(asx.vs.sx, path.index=125,col=1,add=T, lwd=3)
    # --- Plotgsd [] ---
    # Key functions: getOption, plotGeneSetDistributions
    getOption("SweaveHooks")[["fig"]]()
    plotGeneSetDistributions(sx.results,asx.results,path.index=125)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qusage_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qusage_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qusage_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QUSAGE:", paste0("    qusage: ", packageVersion("qusage"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qusage_results.csv
    touch ${prefix}_qusage_output.rds
    echo "BIOC_QUSAGE:" > versions.yml
    echo "    qusage: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QUSAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QUSAGE(ch_input)

    emit:
    results  = BIOC_QUSAGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QUSAGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QUSAGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QUSAGE.out.versions  // channel: path(versions.yml)
}
