#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowMerge
// Merging of mixture components for model-based automated gating of flow cytometry data using the flow
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowMerge/inst/doc/flowmerge.R
// Upstream  : Rgraphviz
// Downstream: none
//
// Install: BiocManager::install("flowMerge")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWMERGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowmerge"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowmerge:2.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowmerge:2.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowmerge_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowmerge_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowmerge_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowMerge)
    library(jsonlite)

    # --- fit Piecewise Linreg [] ---
    # Key functions: fitPiecewiseLinreg
    flowClust.flowobj<-flowObj(flowClust.maxBIC,rituximab);
    flowClust.merge<-merge(flowClust.flowobj,metric="entropy");
    i<-fitPiecewiseLinreg(flowClust.merge);
    # --- split [] ---
    # Key functions: split
    pop<-which(apply(apply(getEstimates(flowClust.mergeopt)$locations,2,function(x)order(x,decreasing=TRUE)==2),1,all));
    lymphocytes<-split(flowClust.mergeopt,population=list("lymphocytes"=pop))$lymphocytes;
    lymphocytes<-lymphocytes[,c(3,5)];
    # --- fit Piecewise Linreg [] ---
    # Key functions: fitPiecewiseLinreg
    par(mfrow=c(2,2));
    l.flowO<-flowObj(l.flowC[[which.max(flowMerge:::BIC(l.flowC))]],lymphocytes);
    plot(l.flowO,main="max BIC solution",new.window=F,pch=20,level=0.9);
    # --- ptree [] ---
    # Key functions: ptree
    require(Rgraphviz)
    f<-ptree("l.flowM",fitPiecewiseLinreg(l.flowM));
    par(mfrow=c(1,2))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowmerge_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowmerge_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowmerge_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWMERGE:", paste0("    flowmerge: ", packageVersion("flowMerge"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowmerge_results.csv
    touch ${prefix}_flowmerge_output.rds
    echo "BIOC_FLOWMERGE:" > versions.yml
    echo "    flowmerge: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWMERGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWMERGE(ch_input)

    emit:
    results  = BIOC_FLOWMERGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWMERGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWMERGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWMERGE.out.versions  // channel: path(versions.yml)
}
