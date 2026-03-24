#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: KCsmart
// Multi sample aCGH analysis package using kernel convolution
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/KCsmart/inst/doc/KCS.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("KCsmart")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KCSMART {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-kcsmart"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-kcsmart:2.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-kcsmart:2.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_kcsmart_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_kcsmart_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_kcsmart_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(KCsmart)
    library(jsonlite)

    # --- Calcspm [] ---
    # Key functions: calcSpm
    spm1mb <- calcSpm(hsSampleData, hsMirrorLocs)
    spm4mb <- calcSpm(hsSampleData, hsMirrorLocs, sigma=4000000)
    # --- Findsigleveltrad [] ---
    # Key functions: findSigLevelTrad
    sigLevel4mb <- findSigLevelTrad(hsSampleData, spm4mb, n=10, p=0.05)
    # --- Getsigsegments [] ---
    # Key functions: getSigSegments
    sigRegions4mb <- getSigSegments(spm4mb,sigLevel4mb)
    # --- Findsigleveltrad [] ---
    # Key functions: findSigLevelTrad
    sigLevel1mb <- findSigLevelTrad(hsSampleData, spm1mb, n=10)
    # --- Plotscalespace [] ---
    # Key functions: plotScaleSpace
    plotScaleSpace(list(spm1mb, spm4mb), list(sigLevel1mb, sigLevel4mb), type='g')
    # --- Calcspmcollection [] ---
    # Key functions: calcSpmCollection
    spmc1mb <- calcSpmCollection(hsSampleData, hsMirrorLocs, cl=c(rep(0,10),rep(1,10)), sigma=1000000)
    # --- Comparespmcollection [] ---
    # Key functions: compareSpmCollection
    spmc1mb.sig <- compareSpmCollection(spmc1mb, nperms=3, method=c("siggenes"))
    spmc1mb.sig
    # --- Getsigregionscompkc [] ---
    # Key functions: getSigRegionsCompKC
    spmc1mb.sig.regions <- getSigRegionsCompKC(spmc1mb.sig)
    spmc1mb.sig.regions

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_kcsmart_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_kcsmart_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_kcsmart_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_KCSMART:", paste0("    kcsmart: ", packageVersion("KCsmart"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_kcsmart_results.csv
    touch ${prefix}_kcsmart_output.rds
    echo "BIOC_KCSMART:" > versions.yml
    echo "    kcsmart: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KCSMART_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KCSMART(ch_input)

    emit:
    results  = BIOC_KCSMART.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KCSMART.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KCSMART.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KCSMART.out.versions  // channel: path(versions.yml)
}
