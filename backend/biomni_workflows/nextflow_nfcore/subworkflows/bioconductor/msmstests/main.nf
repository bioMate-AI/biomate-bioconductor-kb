#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: msmsTests
// Statistical tests for label-free LC-MS/MS data by spectral counts, to discover differentially expres
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/msmsTests/inst/doc/msmsTests-Vignette.R
// Upstream  : xtable
// Downstream: none
//
// Install: BiocManager::install("msmsTests")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSMSTESTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msmstests"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msmstests:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msmstests:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_msmstests_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msmstests_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msmstests_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(msmsTests)
    library(jsonlite)

    # --- Extract differential expression results [] ---
    # Key functions: results, pData, tres, frame
    ###  Cut-off values for a relevant protein as biomarker
    alpha.cut <- 0.05
    SpC.cut <- 2
    lFC.cut <- 1
    ###  Relevant proteins according to the Poisson GLM
    # --- Volcano plot of DE results [] ---
    # Key functions: volcanoplot
    par(mar=c(5,4,0.5,2)+0.1)
    res.volcanoplot(ql.tbl,max.pval=0.05,min.LFC=1,maxx=3,maxy=NULL,
                                ylbls=3)
    # --- Phenotype data inspection [] ---
    # Key functions: pData, exprs, pois, qlll, adjust, edgeR, frame, fc
    msms.spc <- exprs(msms.spk)
    treat <- pData(msms.spk)
    idx <- grep("HUMAN",rownames(msms.spc))
    mSpC <- t( apply(msms.spc[idx,],1,function(x) tapply(x,treat,mean)) )
    apply(mSpC,2,summary)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msmstests_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msmstests_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msmstests_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSMSTESTS:", paste0("    msmstests: ", packageVersion("msmsTests"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msmstests_results.csv
    touch ${prefix}_msmstests_output.rds
    echo "BIOC_MSMSTESTS:" > versions.yml
    echo "    msmstests: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSMSTESTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_MSMSTESTS(ch_input)

    emit:
    results  = BIOC_MSMSTESTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSMSTESTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSMSTESTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSMSTESTS.out.versions  // channel: path(versions.yml)
}
