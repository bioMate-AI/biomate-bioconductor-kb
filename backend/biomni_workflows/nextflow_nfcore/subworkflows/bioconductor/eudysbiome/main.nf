#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: eudysbiome
// eudysbiome a package that permits to annotate the differential genera as harmful/harmless based on t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/eudysbiome/inst/doc/eudysbiome.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("eudysbiome")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EUDYSBIOME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-eudysbiome"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-eudysbiome:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-eudysbiome:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_eudysbiome_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_eudysbiome_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_eudysbiome_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(eudysbiome)
    library(Cartesian)
    library(jsonlite)

    # --- Contingency Table Construction [] ---
    # Key functions: contingencyCount
    data(microDiff)
    microCount <- contingencyCount(
        data = microDiff$data,
        micro.anno = microDiff$micro.anno,
        comp.anno = microDiff$comp.anno
    )


    # --- Association Testing [] ---
    # Key functions: contingencyCount, contingencyTest
    data(microDiff)
    microCount <- contingencyCount(
        data = microDiff$data,
        micro.anno = microDiff$micro.anno,
        comp.anno = microDiff$comp.anno
    )
    microTest <- contingencyTest(
        microCount,
        alternative = "greater"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_eudysbiome_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_eudysbiome_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_eudysbiome_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EUDYSBIOME:", paste0("    eudysbiome: ", packageVersion("eudysbiome"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_eudysbiome_results.csv
    touch ${prefix}_eudysbiome_output.rds
    echo "BIOC_EUDYSBIOME:" > versions.yml
    echo "    eudysbiome: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EUDYSBIOME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EUDYSBIOME(ch_input)

    emit:
    results  = BIOC_EUDYSBIOME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EUDYSBIOME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EUDYSBIOME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EUDYSBIOME.out.versions  // channel: path(versions.yml)
}
