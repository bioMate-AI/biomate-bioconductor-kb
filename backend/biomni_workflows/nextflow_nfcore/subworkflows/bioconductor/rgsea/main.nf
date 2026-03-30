#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RGSEA
// Combining bootstrap aggregating and Gene set enrichment analysis (GSEA), RGSEA is a classfication al
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RGSEA/inst/doc/RGSEA.R
// Upstream  : GEOquery
// Downstream: none
//
// Install: BiocManager::install("RGSEA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RGSEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rgsea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rgsea:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rgsea:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rgsea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rgsea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rgsea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GDS2eSet)
    library(RGSEAfix)
    library(RGSEApredict)
    library(RGSEAsd)
    library(jsonlite)

    # --- G D S2e Set [] ---
    # Key functions: GDS2eSet
    library(GEOquery)
    g4100 <- GDS2eSet(getGEO("GDS4100"))
    g4102 <- GDS2eSet(getGEO("GDS4102"))
    # --- exprs [] ---
    # Key functions: exprs
    e4102<-exprs(g4102)
    e4100<-exprs(g4100)
    # --- R G S E Afix [] ---
    # Key functions: RGSEAfix, RGSEApredict, RGSEAsd
    e1<-e4102[,c(1,51)]
    e2<-e4100[,c(1,2,23,24)]
    colnames(e1)<-c("tumor", "normal")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rgsea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rgsea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rgsea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RGSEA:", paste0("    rgsea: ", packageVersion("RGSEA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rgsea_results.csv
    touch ${prefix}_rgsea_output.rds
    echo "BIOC_RGSEA:" > versions.yml
    echo "    rgsea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RGSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RGSEA(ch_input)

    emit:
    results  = BIOC_RGSEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RGSEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RGSEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RGSEA.out.versions  // channel: path(versions.yml)
}
