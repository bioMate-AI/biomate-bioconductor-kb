#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ArrayExpress
// Access the ArrayExpress Collection at EMBL-EBI Biostudies and build Bioconductor data structures: Ex
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ArrayExpress/inst/doc/ArrayExpress.R
// Upstream  : affy, limma
// Downstream: DrugVsDisease, maEndToEnd
//
// Install: BiocManager::install("ArrayExpress")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ARRAYEXPRESS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-arrayexpress"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-arrayexpress:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-arrayexpress:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_arrayexpress_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_arrayexpress_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_arrayexpress_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ArrayExpress)
    library(jsonlite)

    # --- Queryae [] ---
    # Key functions: queryAE
    library("ArrayExpress")
    sets = queryAE(keywords = "pneumonia", species = "homo+sapiens")
    # --- Arrayexpress Raw [] ---
    # Key functions: ArrayExpress
    rawset = ArrayExpress("E-MEXP-21")
    # --- Arrayexpress Columnsneeded [] ---
    # Key functions: ArrayExpress
    eset = try(ArrayExpress("E-MEXP-1870"))
    # --- Arrayexpress Withcolumns [] ---
    # Key functions: ArrayExpress
    eset = ArrayExpress("E-MEXP-1870",
      dataCols=list(R="ScanArray Express:F650 Mean",
        G="ScanArray Express:F550 Mean",
        Rb="ScanArray Express:B650 Mean",
        Gb="ScanArray Express:B550 Mean"))
    # --- Getae Full [] ---
    # Key functions: getAE
    mexp1422 = getAE("E-MEXP-21", type = "full")
    # --- Ae2Bioc Full [] ---
    # Key functions: ae2bioc
    rawset= ae2bioc(mageFiles = mexp1422)
    # --- Getcolproc [] ---
    # Key functions: getcolproc, show
    cn = getcolproc(mexp1422)
    show(cn)
    # --- Procset [] ---
    # Key functions: procset
    proset = procset(mexp1422, cn[2])
    # --- Import [] ---
    # Key functions: ArrayExpress
    ## AEset = ArrayExpress("E-MEXP-1416")
    # --- Norm [] ---
    # Key functions: rma
    ## library("affy")
    ## AEsetnorm = rma(AEset)
    # --- Fac [] ---
    # Key functions: pData
    ## fac = grep("Factor.Value",colnames(pData(AEsetnorm)), value=T)
    # --- Qanorm [] ---
    # Key functions: arrayQualityMetrics
    ## if (suppressWarnings(require("arrayQualityMetrics", quietly=TRUE))) {
    ##   qanorm = arrayQualityMetrics(AEsetnorm,
    ##     outdir = "QAnorm",
    ##     intgroup = fac)
    ## }
    # --- Limma [] ---
    # Key functions: pData, factor, levels, lmFit
    ## library("limma")
    ## facs =  pData(AEsetnorm)[,fac]
    ## facs[facs[,2]=="female",2]="F"
    ## facs[facs[,2]=="male",2]="M"
    ## facs[facs[,1]=="Parkinson disease",1]="parkinson"

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_arrayexpress_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_arrayexpress_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_arrayexpress_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ARRAYEXPRESS:", paste0("    arrayexpress: ", packageVersion("ArrayExpress"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_arrayexpress_results.csv
    touch ${prefix}_arrayexpress_output.rds
    echo "BIOC_ARRAYEXPRESS:" > versions.yml
    echo "    arrayexpress: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ARRAYEXPRESS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ARRAYEXPRESS(ch_input)

    emit:
    results  = BIOC_ARRAYEXPRESS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ARRAYEXPRESS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ARRAYEXPRESS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ARRAYEXPRESS.out.versions  // channel: path(versions.yml)
}
