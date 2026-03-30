#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pvac
// The package contains the function for filtering genes by the proportion of variation accounted for b
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pvac/inst/doc/pvac.R
// Upstream  : ALLMLL, affy, genefilter
// Downstream: none
//
// Install: BiocManager::install("pvac")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PVAC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pvac"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pvac:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pvac:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pvac_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pvac_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pvac_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ReadAffy)
    library(jsonlite)

    # --- Steps [] ---
    # Key functions: ReadAffy
    ##   library(affy)
    ##   abatch <- ReadAffy(celfile.path="/my/directory/celfiles")
    # --- Steps [] ---
    # Key functions: rma
    ##   myeset <- rma(abatch)
    # --- Steps [] ---
    # Key functions: pvacFilter
    ##   library(pvac)
    ##   ft <- pvacFilter(abatch)
    ##   myeset <- eset[ft$aset,]
    # --- <Steps [] ---
    # Key functions: rowttests, exprs, factor
    ##   library(genefilter)
    ##   myres  = rowttests(exprs(myeset), as.factor(group))
    # --- Example [] ---
    # Key functions: rma, pvacFilter
    library(affy)
    library(pvac)
    library(ALLMLL)
    data(MLL.A)
    myeset <- rma(MLL.A)
    # --- Plot [] ---
    # Key functions: density
    ## plot(density(ft$pvac[ft$nullset]),xlab="PVAC score",main="",
    ##           col="gray",cex.lab=0.5,xlim=c(0,1))
    ## lines(density(ft$pvac),col=1)
    ## abline(v=ft$cutoff,lty=2,col="gray")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pvac_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pvac_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pvac_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PVAC:", paste0("    pvac: ", packageVersion("pvac"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pvac_results.csv
    touch ${prefix}_pvac_output.rds
    echo "BIOC_PVAC:" > versions.yml
    echo "    pvac: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PVAC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PVAC(ch_input)

    emit:
    results  = BIOC_PVAC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PVAC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PVAC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PVAC.out.versions  // channel: path(versions.yml)
}
