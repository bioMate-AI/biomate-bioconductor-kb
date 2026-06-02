#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: procoil
// The package allows for predicting whether a coiled coil sequence (amino acid sequence plus heptad re
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/procoil/inst/doc/procoil.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("procoil")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROCOIL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-procoil"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-procoil:2.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-procoil:2.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_procoil_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_procoil_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_procoil_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(procoil)
    library(jsonlite)


    # --- Load Package To Determine Version [] ---
    # Key functions: set, packageDescription, substr, procoil, predict, abcdefgabcdefgabcdefgabcdefga
    options(width=72)
    knitr::opts_knit$set(width=72)
    set.seed(0)
    library(procoil, quietly=TRUE)
    procoilVersion <- packageDescription("procoil")$Version
    procoilDateRaw <- packageDescription("procoil")$Date
    procoilDateYear <- as.numeric(substr(procoilDateRaw, 1, 4))
    procoilDateMonth <- as.numeric(substr(procoilDateRaw, 6, 7))
    procoilDateDay <- as.numeric(substr(procoilDateRaw, 9, 10))
    # --- Display Result For Gcn4wild Type [] ---
    # Key functions: procoil
    GCN4wt
    plot(GCN4wt)

    # --- Predict Marcoil Example [] ---
    # Key functions: predict
    res <- predict(PrOCoilModel,
    "MGECDQLLVFMITSRVLVLSTLIIMDSRQVYLENLRQFAENLRQNIENVHSFLENLRADLENLRQKFPGKWYSAMPGRHG",
    "-------------------------------abcdefgabcdefgabcdefgabcdefgabcdefg--------------")
    res

    # --- Plot Result For Marcoil Example [] ---
    # Key functions: rep, predict, GCN4_N16Y_L19T, GCN4_E22R_K27E, GCN4_V23K_K27E, abcdefgabcdefgabcdefgabcdefga
    plot(res[1])
    GCN4mSeq <- c("GCN4wt"        ="MKQLEDKVEELLSKNYHLENEVARLKKLV",
                  "GCN4_N16Y_L19T"="MKQLEDKVEELLSKYYHTENEVARLKKLV",
                  "GCN4_E22R_K27E"="MKQLEDKVEELLSKNYHLENRVARLEKLV",
                  "GCN4_V23K_K27E"="MKQLEDKVEELLSKNYHLENEKARLEKLV")
    GCN4mReg <- rep("abcdefgabcdefgabcdefgabcdefga", 4)

    GCN4mut <- predict(PrOCoilModel, GCN4mSeq, GCN4mReg)
    GCN4mut

    # --- Plot Gcn4mutation [] ---
    # Key functions: heatmap
    plot(GCN4mut[c(1, 2)])
    plot(GCN4mut[c(1, 3)])
    plot(GCN4mut[c(1, 4)])
    heatmap(GCN4mut)

    # --- Plot Result For Example With Heptad Irregularity [] ---
    # Key functions: predict, defgabcdefgabcdabcdefga, rgb
    plot(predict(PrOCoilModel,
                 "LQDTLVRQERPIRKSIEDLRNTV",
                 "defgabcdefgabcdabcdefga"))
    plot(GCN4mut[c(1, 2)], legend=c("wild type", "mutant N16Y,L19T"),
         col=c(rgb(0.7, 0, 0), rgb(0, 0, 0.8)), main="GCN4 Mutation Analysis",
         shades=c(rgb(0.77, 0.85, 0.95), rgb(0.99, 0.84, 0.71)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_procoil_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_procoil_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_procoil_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROCOIL:", paste0("    procoil: ", packageVersion("procoil"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_procoil_results.csv
    touch ${prefix}_procoil_output.rds
    echo "BIOC_PROCOIL:" > versions.yml
    echo "    procoil: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROCOIL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROCOIL(ch_input)

    emit:
    results  = BIOC_PROCOIL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROCOIL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROCOIL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROCOIL.out.versions  // channel: path(versions.yml)
}
