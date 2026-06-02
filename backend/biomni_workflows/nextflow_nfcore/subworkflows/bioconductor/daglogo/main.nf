#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dagLogo
// Visualize significant conserved amino acid sequence pattern in groups based on probability theory.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dagLogo/inst/doc/dagLogo.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("dagLogo")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DAGLOGO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-daglogo"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-daglogo:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-daglogo:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_daglogo_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_daglogo_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_daglogo_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(dagLogo)
    library(jsonlite)

    # --- Background Model Construction [] ---
    # Key functions: buildBackgroundModel
    bg_fisher <- buildBackgroundModel(seq, background = "wholeProteome",
                                      proteome = proteome, testType = "fisher")
    bg_ztest <- buildBackgroundModel(seq, background = "wholeProteome",
                                     proteome = proteome, testType = "ztest")


    # --- Differential Amino Acid Usage Testing [] ---
    # Key functions: testDAU, addScheme
    t0 <- testDAU(seq, dagBackground = bg_ztest)
    t1 <- testDAU(dagPeptides = seq, dagBackground = bg_ztest,
                  groupingScheme = "chemistry_property_Mahler_group")
    color <- c(LVIMC = "#33FF00", AGSTP = "#CCFF00",
               FYW = '#00FF66', EDNQKRH = "#FF0066")
    symbol <- c(LVIMC = "L", AGSTP = "A", FYW = "F", EDNQKRH = "E")
    group <- list(LVIMC = c("L", "V", "I", "M", "C"),
                  AGSTP = c("A", "G", "S", "T", "P"),
                  FYW = c("F", "Y", "W"),
                  EDNQKRH = c("E", "D", "N", "Q", "K", "R", "H"))
    addScheme(color = color, symbol = symbol, group = group)
    t5 <- testDAU(dagPeptides = seq, dagBackground = bg_ztest,
                  groupingScheme = "custom_group")


    # --- Heatmap Visualisation [] ---
    # Key functions: dagHeatmap
    dagHeatmap(t0)
    dagHeatmap(t1)
    dagHeatmap(t5)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_daglogo_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_daglogo_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_daglogo_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DAGLOGO:", paste0("    daglogo: ", packageVersion("dagLogo"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_daglogo_results.csv
    touch ${prefix}_daglogo_output.rds
    echo "BIOC_DAGLOGO:" > versions.yml
    echo "    daglogo: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DAGLOGO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DAGLOGO(ch_input)

    emit:
    results  = BIOC_DAGLOGO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DAGLOGO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DAGLOGO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DAGLOGO.out.versions  // channel: path(versions.yml)
}
