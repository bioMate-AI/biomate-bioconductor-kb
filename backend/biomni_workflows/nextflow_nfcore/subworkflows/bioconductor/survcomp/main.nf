#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: survcomp
// Assessment and Comparison for Performance of Risk Prediction (Survival) Models.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/survcomp/inst/doc/survcomp.R
// Upstream  : Biobase, rmeta, xtable
// Downstream: none
//
// Install: BiocManager::install("survcomp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SURVCOMP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-survcomp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-survcomp:1.56.0--r44_0' :
        'quay.io/biocontainers/bioconductor-survcomp:1.56.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_survcomp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_survcomp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_survcomp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(survcomp)
    library(jsonlite)

    # --- Install Pkg [] ---
    # Key functions: requireNamespace, packages
    ## if (!requireNamespace("BiocManager", quietly=TRUE))
    ##     install.packages("BiocManager")
    ## BiocManager::install("survcomp")
    # --- Loadbreastcancerdata [] ---
    # Key functions: data
    data(breastCancerData)
    mainz7g
    # --- Createvars [] ---
    # Key functions: fData
    gsList <- tolower(fData(mainz7g)[,"Gene.symbol"])
    gidList <- fData(mainz7g)[,"Gene.ID"]
    probesNKI <- as.character(fData(nki7g)[,"probe"])
    probesAffy <- fData(mainz7g)[,"probe"]
    datasetList <- c("MAINZ","TRANSBIG","UPP","UNT","VDX","NKI","","Overall")
    # --- Showvars [] ---
    # Key functions: frame, xtable
    overview <- as.data.frame(cbind("Gene Symbol"=gsList,"Gene ID"=gidList,"Probes Agilent"=probesNKI,"Probes Affy"=probesAffy))
    print(xtable(overview), floating=FALSE)
    # --- Computecindexsample [] ---
    # Key functions: exprs, index, pData
    cindexall.mainz.small <- t(apply(X=exprs(mainz7g), MARGIN=1, function(x, y, z) { tt <- concordance.index(x=x, surv.time=y, surv.event=z, method="noether", na.rm=TRUE); return(c("cindex"=tt$c.index, "cindex.se"=tt$se, "lower"=tt$lower, "upper"=tt$upper)); }, y=pData(mainz7g)[ ,"t.dmfs"], z=pData(mainz7g)[ ,"e.dmfs"]))
    # --- Computecindex [] ---
    # Key functions: exprs, index, pData
    cindexall.transbig.small <- t(apply(X=exprs(transbig7g), MARGIN=1, function(x, y, z) {
        tt <- concordance.index(x=x, surv.time=y, surv.event=z, method="noether", na.rm=TRUE);
        return(c("cindex"=tt$c.index, "cindex.se"=tt$se, "lower"=tt$lower, "upper"=tt$upper)); },
        y=pData(transbig7g)[ ,"t.dmfs"], z=pData(transbig7g)[ ,"e.dmfs"]))
    # --- Dindexsample [] ---
    # Key functions: exprs, index, pData
    dindexall.mainz.small <- t(apply(X=exprs(mainz7g), MARGIN=1, function(x, y, z) {
        tt <- D.index(x=x, surv.time=y, surv.event=z, na.rm=TRUE);
        return(c("dindex"=tt$d.index, "dindex.se"=tt$se, "lower"=tt$lower, "upper"=tt$upper)); },
        y=pData(mainz7g)[ ,"t.dmfs"], z=pData(mainz7g)[ ,"e.dmfs"]))
    # --- Dindex [] ---
    # Key functions: exprs, index, pData
    dindexall.transbig.small <- t(apply(X=exprs(transbig7g), MARGIN=1, function(x, y, z) {
        tt <- D.index(x=x, surv.time=y, surv.event=z, na.rm=TRUE);
        return(c("dindex"=tt$d.index, "dindex.se"=tt$se, "lower"=tt$lower, "upper"=tt$upper)); },
        y=pData(transbig7g)[ ,"t.dmfs"], z=pData(transbig7g)[ ,"e.dmfs"]))
    # --- Showgeneexpressionrange [] ---
    # Key functions: exprs, frame
    tt <- list(mainz7g, transbig7g, upp7g, unt7g, vdx7g, nki7g)
    ttNames <- c("MAINZ","TRANSBIG","UPP","UNT","VDX","NKI")
    dataRange <- NULL
    # --- Datarangetable [] ---
    # Key functions: xtable
    print(xtable(dataRange), floating=FALSE)
    # --- Hratiosample [] ---
    # Key functions: rescale, exprs, ratio
    hratio.mainz.small <- t(apply(X=rescale(exprs(mainz7g) , q=0.05, na.rm=TRUE), MARGIN=1, function(x, y, z) {
        tt <- hazard.ratio(x=x, surv.time=y, surv.event=z, na.rm=TRUE);
        return(c("hratio"=tt$hazard.ratio, "hratio.se"=tt$se, "lower"=tt$lower, "upper"=tt$upper)); },
        y=pData(mainz7g)[ ,"t.dmfs"], z=pData(mainz7g)[ ,"e.dmfs"]))
    # --- Hratio [] ---
    # Key functions: rescale, exprs, ratio
    hratio.transbig.small <- t(apply(X=rescale(exprs(transbig7g), q=0.05, na.rm=TRUE), MARGIN=1, function(x, y, z) {
        tt <- hazard.ratio(x=x, surv.time=y, surv.event=z, na.rm=TRUE);
        return(c("hratio"=tt$hazard.ratio, "hratio.se"=tt$se, "lower"=tt$lower, "upper"=tt$upper)); },
        y=pData(transbig7g)[ ,"t.dmfs"], z=pData(transbig7g)[ ,"e.dmfs"]))
    # --- Combinecindices [] ---
    # Key functions: frame, est, qnorm
    tt <- as.data.frame(NULL)
    # --- Combinecindicesoutput [] ---
    # Key functions: xtable
    print(xtable(ccindex), floating=FALSE)
    # --- Combinedindices [] ---
    # Key functions: frame, est, qnorm
    tt <- as.data.frame(NULL)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_survcomp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_survcomp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_survcomp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SURVCOMP:", paste0("    survcomp: ", packageVersion("survcomp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_survcomp_results.csv
    touch ${prefix}_survcomp_output.rds
    echo "BIOC_SURVCOMP:" > versions.yml
    echo "    survcomp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SURVCOMP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SURVCOMP(ch_input)

    emit:
    results  = BIOC_SURVCOMP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SURVCOMP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SURVCOMP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SURVCOMP.out.versions  // channel: path(versions.yml)
}
