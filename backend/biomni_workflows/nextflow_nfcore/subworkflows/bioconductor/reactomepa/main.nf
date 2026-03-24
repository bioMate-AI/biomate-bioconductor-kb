#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ReactomePA
// This package provides functions for pathway analysis based on REACTOME pathway database. It implemen
//
// Source : https://yulab-smu.top/biomedical-knowledge-mining-book/024-reactome.html
// Upstream  : DOSE
// Downstream: maEndToEnd
//
// Install: BiocManager::install("ReactomePA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REACTOMEPA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-reactomepa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-reactomepa:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-reactomepa:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_reactomepa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_reactomepa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_reactomepa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ReactomePA)
    library(jsonlite)

    # --- Reactome pathway over-representation analysis [] ---
    # Key functions: data, enrichPathway
    library(ReactomePA)
    data(geneList, package="DOSE"
    )
    de <- names(geneList)[abs(geneList) > 1.5]
    head(de)
    
    x <- enrichPathway(gene=de, pvalueCutoff = 0.05, readable=TRUE)
    head(x)
    # --- Reactome pathway gene set enrichment analysis [] ---
    # Key functions: gsePathway
    y <- gsePathway(geneList,
                    pvalueCutoff = 0.2,
                    pAdjustMethod = "BH",
                    verbose = FALSE)
    head(y)
    # --- Pathway Visualization [] ---
    # Key functions: viewPathway
    viewPathway("E2F mediated regulation of DNA replication",
                readable = TRUE,
                foldChange = geneList)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_reactomepa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_reactomepa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_reactomepa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REACTOMEPA:", paste0("    reactomepa: ", packageVersion("ReactomePA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reactomepa_results.csv
    touch ${prefix}_reactomepa_output.rds
    echo "BIOC_REACTOMEPA:" > versions.yml
    echo "    reactomepa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REACTOMEPA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REACTOMEPA(ch_input)

    emit:
    results  = BIOC_REACTOMEPA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REACTOMEPA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REACTOMEPA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REACTOMEPA.out.versions  // channel: path(versions.yml)
}
