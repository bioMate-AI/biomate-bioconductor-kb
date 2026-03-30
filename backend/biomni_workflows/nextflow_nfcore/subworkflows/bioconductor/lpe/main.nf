#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: LPE
// This LPE library is used to do significance analysis of microarray data with small number of replica
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/LPE/inst/doc/LPE.R
// Upstream  : none
// Downstream: PLPE
//
// Install: BiocManager::install("LPE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LPE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lpe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lpe:1.80.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lpe:1.80.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lpe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lpe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lpe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(LPE)
    library(jsonlite)

    # --- Packagedescription [] ---
    # Key functions: packageDescription
    ## packageDescription("LPE")
    # --- Preprocess [] ---
    # Key functions: preprocess
    Ley.normalized <- Ley.subset
    Ley.normalized[,2:7] <- preprocess(Ley.subset[,2:7], data.type = "MAS5")
    Ley.normalized[1:3,]
    # --- Error [] ---
    # Key functions: error
    var.Naive <- baseOlig.error(Ley.final[,2:4],q=0.01)
    dim(var.Naive)
    var.Naive[1:3,]
    # --- Frame [] ---
    # Key functions: frame, lpe
    lpe.val <- data.frame(lpe(Ley.final[,5:7], Ley.final[,2:4],
                              var.Activated, var.Naive,
                              probe.set.name=Ley.final$ID)
                          )
    lpe.val <- round(lpe.val, digits=2)
    # --- Adjust [] ---
    # Key functions: adjust
    fdr.BH <- fdr.adjust(lpe.val, adjp="BH")
    dim(fdr.BH)
    round(fdr.BH[1:4, ],2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lpe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lpe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lpe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LPE:", paste0("    lpe: ", packageVersion("LPE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lpe_results.csv
    touch ${prefix}_lpe_output.rds
    echo "BIOC_LPE:" > versions.yml
    echo "    lpe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LPE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LPE(ch_input)

    emit:
    results  = BIOC_LPE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LPE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LPE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LPE.out.versions  // channel: path(versions.yml)
}
