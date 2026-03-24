#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: metapone
// The package conducts pathway testing from untargetted metabolomics data. It requires the user to sup
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/metapone/inst/doc/metapone.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("metapone")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METAPONE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metapone"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metapone:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metapone:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metapone_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metapone_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metapone_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(metapone)
    library(jsonlite)

    # --- metapone [] ---
    # Key functions: metapone
    dat <- list(pos, neg)
    type <- list("pos", "neg")
    r<-metapone(dat, type, pa, hmdbCompMZ=hmdbCompMZ, pos.adductlist=pos.adductlist, neg.adductlist=neg.adductlist, p.threshold=0.05,n.permu=200,fractional.count.power=0.5, max.match.count=10, use.fgsea = FALSE)
    # --- example continued [] ---
    # Key functions: ptable
    selection<-which(ptable(r)[,1]<0.025)
    ptable(r)[selection,]
    # --- example continued 2 [] ---
    # Key functions: ftable
    ftable(r)[which(ptable(r)[,1]<0.025 & ptable(r)[,2]>=2)]
    # --- example visulization [] ---
    # Key functions: bbplot1d, bbplot2d
    bbplot1d(r@test.result, 0.025)
    bbplot2d(r@test.result, 0.025)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metapone_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metapone_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metapone_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METAPONE:", paste0("    metapone: ", packageVersion("metapone"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metapone_results.csv
    touch ${prefix}_metapone_output.rds
    echo "BIOC_METAPONE:" > versions.yml
    echo "    metapone: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METAPONE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METAPONE(ch_input)

    emit:
    results  = BIOC_METAPONE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METAPONE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METAPONE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METAPONE.out.versions  // channel: path(versions.yml)
}
