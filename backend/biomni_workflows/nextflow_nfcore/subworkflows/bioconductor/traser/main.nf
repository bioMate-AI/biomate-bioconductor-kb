#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: traseR
// traseR performs GWAS trait-associated SNP enrichment analyses in genomic intervals using different h
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/traseR/inst/doc/traseR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("traseR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRASER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-traser"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-traser:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-traser:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_traser_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_traser_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_traser_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(traseR)
    library(jsonlite)

    # --- Traser [] ---
    # Key functions: traseR
    ## x=traseR(snpdb=taSNP,region=Tcell)
    ## print(x)
    # --- Data [] ---
    # Key functions: traseR
    library(traseR)
    data(taSNP)
    data(Tcell)
    x=traseR(taSNP,Tcell)
    print(x)
    # --- Plotcontext [] ---
    # Key functions: plotContext
    plotContext(snpdb=taSNP,region=Tcell,keyword="Autoimmune")
    # --- Plotpvalue [] ---
    # Key functions: plotPvalue
    plotPvalue(snpdb=taSNP,region=Tcell,keyword="autoimmune",plot.type="densityplot")
    # --- Plotinterval [] ---
    # Key functions: plotInterval, frame
    plotInterval(snpdb=taSNP,data.frame(chr="chrX",start=152633780,end=152737085))
    # --- Querykeyword [] ---
    # Key functions: queryKeyword
    x=queryKeyword(snpdb=taSNP,region=Tcell,keyword="autoimmune",returnby="SNP")
    head(x)
    # --- Querygene [] ---
    # Key functions: queryGene
    x=queryGene(snpdb=taSNP,genes=c("AGRN","UBE2J2","SSU72"))
    x
    # --- Querysnp [] ---
    # Key functions: querySNP
    x=querySNP(snpdb=taSNP,snpid=c("rs3766178","rs880051"))
    x

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_traser_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_traser_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_traser_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRASER:", paste0("    traser: ", packageVersion("traseR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_traser_results.csv
    touch ${prefix}_traser_output.rds
    echo "BIOC_TRASER:" > versions.yml
    echo "    traser: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRASER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRASER(ch_input)

    emit:
    results  = BIOC_TRASER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRASER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRASER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRASER.out.versions  // channel: path(versions.yml)
}
