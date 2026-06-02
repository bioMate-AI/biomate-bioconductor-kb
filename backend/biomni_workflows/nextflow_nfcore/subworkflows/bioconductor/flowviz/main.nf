#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowViz
// Provides visualization tools for flow cytometry data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowViz/inst/doc/filters.R
// Upstream  : flowStats
// Downstream: flowFP, flowVS
//
// Install: BiocManager::install("flowViz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowviz:1.70.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowviz:1.70.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowViz)
    library(jsonlite)


    # --- Load Data [] ---
    # Key functions: pData, transformList, rectangleGate, xyplot
    library(flowViz)
    data(GvHD)
    head(pData(GvHD))
    GvHD <- GvHD[pData(GvHD)$Patient==6]
    tf <- transformList(from=colnames(GvHD)[3:7], tfun=asinh)
    GvHD <- tf %on% GvHD
    rgate <- rectangleGate("FSC-H"=c(0, 400),"SSC-H"=c(-50, 300))
    print(xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=rgate))
    rgate2 <- rgate * rectangleGate("FL1-H"=c(2, 4))
    xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=rgate2)

    # --- Non Smooth Scatter [] ---
    # Key functions: xyplot, trellis.last.object, rectangleGate, filters
    xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=rgate, smooth=FALSE)
    xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=rgate, smooth=FALSE,xbin=128)
    print(plot(trellis.last.object()))
    xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=rgate,
    smooth=FALSE, stat=TRUE,pos=0.5,abs=TRUE)

    ## ----multi-filters------------------------------------------------------------
    recGate1<-rectangleGate("FL4-H"=c(3.3,5.3),"FL2-H"=c(2.5,5))
    recGate2<-rectangleGate("FL4-H"=c(4,6),"FL2-H"=c(6,8))
    filters1<-filters(list(recGate1,recGate2))
    # --- Non Smooth Scatter Outline2 [] ---
    # Key functions: xyplot, trellis.last.object, norm2Filter, filter, curv2Filter
    xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=rgate2,
           smooth=FALSE, outline=TRUE)
    print(plot(trellis.last.object()))
    n2Filter <- norm2Filter("SSC-H", "FSC-H", scale=2, filterId="Lymphocytes")
    n2Filter.results <- filter(GvHD, n2Filter)
    xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=n2Filter.results)
    print(plot(trellis.last.object()))
    library(flowStats)
    c2f <- curv2Filter("FSC-H", "FL4-H", bwFac=1.8)
    c2f.results <- filter(GvHD, c2f)
    xyplot(`FL4-H` ~ `FSC-H` | Visit, data=GvHD, filter=c2f.results)

    # --- Plotcurv2filter [] ---
    # Key functions: trellis.last.object, densityplot, curv1Filter
    print(plot(trellis.last.object()))
    densityplot(~ `FSC-H`, GvHD, filter=curv1Filter("FSC-H"))
    print(plot(trellis.last.object()))
    densityplot(~ ., GvHD, channels=c("FSC-H", "SSC-H", "FL1-H"), 
    filter=list(curv1Filter("FSC-H"), NULL, rgate2))
    print(plot(trellis.last.object()))

    # --- Pars1 [] ---
    # Key functions: xyplot, black, trellis.last.object, orange, rainbow, transparent
    xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=rgate,
           par.settings=list(gate=list(fill="black", alpha=0.2)))
    print(plot(trellis.last.object()))
    xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=rgate,
           smooth=FALSE, 
           par.settings=list(gate=list(col="orange", alpha=0.04,
                                       pch=20, cex=0.7),
                             flow.symbol=list(alpha=0.04, pch=20, cex=0.7)))
    print(plot(trellis.last.object()))
    xyplot(`FL4-H` ~ `FSC-H` | Visit, data=GvHD, filter=c2f.results,
    par.settings=list(gate=list(fill=rainbow(10), alpha=0.5, col="transparent")))

    # --- Plot Pars4 [] ---
    # Key functions: trellis.last.object, xyplot, black, transparent, darkred, parallel
    print(plot(trellis.last.object()))
    xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=n2Filter.results, 
           names=TRUE, 
           par.settings=list(gate=list(fill="black", alpha=0.2, 
                                       col="transparent"),
                             gate.text=list(col="darkred", alpha=0.7, cex=0.6)))
    print(plot(trellis.last.object()))
    parallel(~ . | Visit, GvHD, filter=n2Filter.results, alpha = 0.01)
    print(plot(trellis.last.object()))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWVIZ:", paste0("    flowviz: ", packageVersion("flowViz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowviz_results.csv
    touch ${prefix}_flowviz_output.rds
    echo "BIOC_FLOWVIZ:" > versions.yml
    echo "    flowviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWVIZ(ch_input)

    emit:
    results  = BIOC_FLOWVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWVIZ.out.versions  // channel: path(versions.yml)
}
