#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RTopper
// the RTopper package is designed to perform and integrate gene set enrichment results across multiple
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RTopper/inst/doc/RTopper.R
// Upstream  : KEGGREST, limma
// Downstream: none
//
// Install: BiocManager::install("RTopper")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RTOPPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rtopper"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rtopper:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rtopper:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_rtopper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rtopper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rtopper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RTopper)
    library(jsonlite)


    # --- Start [] ---
    # Key functions: class, str
    options(width=50)
    rm(list=ls())
    set.seed(9)
    library(RTopper)
    data(exampleData)
    ls()
    class(dat)
    names(dat)
    sapply(dat,class)
    sapply(dat,dim)
    dim(pheno)
    str(pheno)

    # --- Str Data [] ---
    # Key functions: function, org.Hs.eg
    ###data structure
    lapply(dat,function(x) head(x)[,1:3])
    sum(rownames(dat[[1]])%in%rownames(dat[[2]]))
    sum(rownames(dat[[2]])%in%rownames(dat[[3]]))
    library(org.Hs.eg.db)
    org.Hs.eg()

    # --- List Fgs [] ---
    # Key functions: str, function, unlist, mget, sample
    kegg <- as.list(org.Hs.egPATH2EG)
    go <- as.list(org.Hs.egGO2ALLEGS)
    length(kegg)
    length(go)
    str(kegg[1:5])
    names(kegg)[1:5]
    str(go[1:5])
    names(go)[1:5]
    someKeggID <- c("00450", "04971", "00970", "04260", "05320")
    kegg <- lapply(kegg[someKeggID],function(x) unique(unlist(mget(x,org.Hs.egSYMBOL))))
    go <- lapply(go[sample(1:length(go),5)],function(x) unique(unlist(mget(x,org.Hs.egSYMBOL))))
    str(kegg)
    str(go)

    # --- Annotate Fgs [] ---
    # Key functions: keggGet, hsa, Term
    library(KEGGREST)
    # --- List Fgs [] ---
    # Key functions: convertToDr, class, str
    fgsList <- list(go=go, kegg=kegg)

    fgsList$go
    dataDr <- convertToDr(dat, pheno, 4)
    class(dataDr)
    length(dataDr)
    names(dataDr)[1:5]
    str(dataDr[1:2])

    # --- Integrated Score [] ---
    # Key functions: computeDrStat, str, bic
    bicStatInt <- computeDrStat(dataDr, columns = c(1:4), method="bic", integrate = TRUE)
    names(bicStatInt)
    str(bicStatInt)
    bicStatSep <- computeDrStat(dataDr, columns = c(1:4), method="bic", integrate = FALSE)
    names(bicStatSep)
    str(bicStatSep)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rtopper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rtopper_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rtopper_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RTOPPER:", paste0("    rtopper: ", packageVersion("RTopper"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rtopper_results.csv
    touch ${prefix}_rtopper_output.rds
    echo "BIOC_RTOPPER:" > versions.yml
    echo "    rtopper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RTOPPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_RTOPPER(ch_input)

    emit:
    results  = BIOC_RTOPPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RTOPPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RTOPPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RTOPPER.out.versions  // channel: path(versions.yml)
}
