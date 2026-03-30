#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VegaMC
// This package enables the detection of driver chromosomal imbalances including loss of heterozygosity
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VegaMC/inst/doc/VegaMC.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("VegaMC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VEGAMC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-vegamc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-vegamc:3.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-vegamc:3.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_vegamc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_vegamc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_vegamc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(VegaMC)
    library(jsonlite)

    # --- Copy Dataset [] ---
    # Key functions: copy
    file.copy(system.file("example/breast_Affy500K.txt",
        package="VegaMC"),".")
    # --- Runvegamc Breast [] ---
    # Key functions: vegaMC
    results <-
    vegaMC("breast_Affy500K.txt",
    	output_file_name="breast.analysis",
    	beta=1,	min_region_bp_size=2000, bs=5000,
    	html=FALSE, getGenes=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_vegamc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_vegamc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_vegamc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VEGAMC:", paste0("    vegamc: ", packageVersion("VegaMC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vegamc_results.csv
    touch ${prefix}_vegamc_output.rds
    echo "BIOC_VEGAMC:" > versions.yml
    echo "    vegamc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VEGAMC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VEGAMC(ch_input)

    emit:
    results  = BIOC_VEGAMC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VEGAMC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VEGAMC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VEGAMC.out.versions  // channel: path(versions.yml)
}
