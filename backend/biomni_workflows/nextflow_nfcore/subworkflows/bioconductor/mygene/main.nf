#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mygene
// MyGene.Info_ provides simple-to-use REST web services to query/retrieve gene annotation data. It's d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mygene/inst/doc/mygene.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("mygene")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MYGENE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mygene"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mygene:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mygene:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mygene_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mygene_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mygene_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mygene)
    library(jsonlite)

    # --- Getgene [] ---
    # Key functions: getGene
    gene <- getGene("1017", fields="all")
    length(gene)
    gene["name"]
    gene["taxid"]
    gene["uniprot"]
    # --- Getgenes [] ---
    # Key functions: getGenes
    getGenes(c("1017","1018","ENSG00000148795"))
    # --- Query [] ---
    # Key functions: query
    query(q="cdk2", size=5)
    # --- Querymany [] ---
    # Key functions: queryMany
    queryMany(c('1053_at', '117_at', '121_at', '1255_g_at', '1294_at'),
              scopes="reporter", species="human")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mygene_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mygene_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mygene_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MYGENE:", paste0("    mygene: ", packageVersion("mygene"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mygene_results.csv
    touch ${prefix}_mygene_output.rds
    echo "BIOC_MYGENE:" > versions.yml
    echo "    mygene: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MYGENE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MYGENE(ch_input)

    emit:
    results  = BIOC_MYGENE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MYGENE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MYGENE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MYGENE.out.versions  // channel: path(versions.yml)
}
