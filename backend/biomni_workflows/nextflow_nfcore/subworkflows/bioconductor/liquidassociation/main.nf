#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: LiquidAssociation
// The package contains functions for calculate direct and model-based estimators for liquid associatio
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/LiquidAssociation/inst/doc/LiquidAssociation.R
// Upstream  : yeastCC
// Downstream: fastLiquidAssociation
//
// Install: BiocManager::install("LiquidAssociation")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LIQUIDASSOCIATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-liquidassociation"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-liquidassociation:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-liquidassociation:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_liquidassociation_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_liquidassociation_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_liquidassociation_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GLA)
    library(LA)
    library(jsonlite)

    # --- Loaddata [] ---
    # Key functions: na, exprs
    library(LiquidAssociation)
    library(yeastCC)
    library(org.Sc.sgd.db)
    data(spYCCES)
    lae <- spYCCES[,-(1:4)]
    # --- Preprocessing [] ---
    # Key functions: exprs, na
    data<-t(exprs(lae[whgene,]))
    eSetdata<-lae[whgene,]
    data<-data[!is.na(data[,1]) & !is.na(data[,2]) & !is.na(data[,3]),]
    colnames(data)<-genes
    str(data)
    # --- Glaplot [] ---
    # Key functions: plotGLA
    plotGLA(data, cut=3, dim=3, pch=16, filen="GLAplot", save=TRUE)
    # --- Calculate Gla [] ---
    # Key functions: LA, GLA
    LAest<-LA(data)
    GLAest<-rep(0,3)
    for ( dim in 1:3){
    	GLAest[dim]<-GLA(data, cut=4, dim=dim)
    }
    # --- Expressionset [] ---
    # Key functions: GLA
    eSetGLA<-GLA(eSetdata, cut=4, dim=3, geneMap=geneMap)
    eSetGLA
    # --- Cnm Model [] ---
    # Key functions: full
    FitCNM.full<-CNM.full(data)
    FitCNM.full
    # --- Calculate Sgla [] ---
    # Key functions: getsGLA, getsLA
    sGLAest<-getsGLA(data, boots=20, perm=50, cut=4, dim=3)
    sGLAest
    sLAest<-getsLA(data,boots=20, perm=50)
    sLAest
    # --- Extend Example Filter Small Variance [] ---
    # Key functions: exprs
    lae<-t(exprs(lae))
    V<-apply(lae, 2, var, na.rm=TRUE)
    ibig<-V > 0.5
    sum(ibig)
    big<-which(ibig)
    # --- Annotation [] ---
    # Key functions: mappedkeys
    x <- org.Sc.sgdGENENAME
    mappedgenes <- mappedkeys(x)
    xx <- as.list(x[mappedgenes])
    mapid<-names(xx)
    orfid<-colnames(bigtriplet)
    # --- Calculate Gla For All Triplets [] ---
    # Key functions: choose, combn, GLA
    num<-choose(ncol(bigtriplet),3)
    pick<-t(combn(1:ncol(bigtriplet),3))
    GLAout<-matrix(0, nrow=100, 3)
    # --- Hypothesistesting [] ---
    # Key functions: na, full, getsGLA
    whtrip<-1
    data<-bigtriplet[,pickmax[whtrip,]]
    data<-data[,trip.order[whtrip,]]
    data<-data[!is.na(data[,1]) & !is.na(data[,2]) & !is.na(data[,3]),]
    data<-apply(data,2,qqnorm2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_liquidassociation_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_liquidassociation_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_liquidassociation_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LIQUIDASSOCIATION:", paste0("    liquidassociation: ", packageVersion("LiquidAssociation"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_liquidassociation_results.csv
    touch ${prefix}_liquidassociation_output.rds
    echo "BIOC_LIQUIDASSOCIATION:" > versions.yml
    echo "    liquidassociation: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LIQUIDASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LIQUIDASSOCIATION(ch_input)

    emit:
    results  = BIOC_LIQUIDASSOCIATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LIQUIDASSOCIATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LIQUIDASSOCIATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LIQUIDASSOCIATION.out.versions  // channel: path(versions.yml)
}
