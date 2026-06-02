#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HybridMTest
// Performs hybrid multiple testing that incorporates method selection and assumption evaluations into 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HybridMTest/inst/doc/HybridMTest.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HybridMTest")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HYBRIDMTEST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hybridmtest"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hybridmtest:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hybridmtest:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hybridmtest_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hybridmtest_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hybridmtest_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HybridMTest)
    library(jsonlite)

    # --- Correlation Hybrid Testing [Analysis] ---
    # Key functions: hybrid.test, row.pearson, row.spearman, row.slr.shapiro
    data(correlation.data, package = "hybridmtest")
    test.specs <- data.frame(
        label = c("pearson", "spearman", "shapiro"),
        func.name = c("row.pearson", "row.spearman", "row.slr.shapiro"),
        x = rep("x", 3),
        opts = rep("", 3)
    )
    ebp.def <- data.frame(
        wght = c("shapiro.ebp", "(1-shapiro.ebp)"),
        mthd = c("pearson.ebp", "spearman.ebp")
    )
    corr.res <- hybrid.test(
        correlation.data,
        test.specs,
        ebp.def
    )

    # --- Group Comparison Hybrid Testing [Analysis] ---
    # Key functions: hybrid.test, row.oneway.anova, row.kruskal.wallis, row.kgrp.shapiro
    data(GroupComp.data, package = "hybridmtest")
    test.specs <- data.frame(
        label = c("anova", "kw", "shapiro"),
        func.name = c("row.oneway.anova", "row.kruskal.wallis", "row.kgrp.shapiro"),
        x = rep("grp", 3),
        opts = rep("", 3)
    )
    ebp.def <- data.frame(
        wght = c("shapiro.ebp", "(1-shapiro.ebp)"),
        mthd = c("anova.ebp", "kw.ebp")
    )
    kgrp.res <- hybrid.test(
        GroupComp.data,
        test.specs,
        ebp.def
    )

    # --- Two-Group Hybrid Testing [Analysis] ---
    # Key functions: hybrid.test, row.ttest.equalvar, row.ttest.unequalvar, row.2grp.shapiro
    data(GroupComp.data, package = "hybridmtest")
    two_grp_data <- GroupComp.data[, GroupComp.data$grp %in% c(1, 2)]
    test.specs <- data.frame(
        label = c("equal", "unequal", "shapiro"),
        func.name = c("row.ttest.equalvar", "row.ttest.unequalvar", "row.2grp.shapiro"),
        x = rep("grp", 3),
        opts = rep("", 3)
    )
    ebp.def <- data.frame(
        wght = c("shapiro.ebp", "(1-shapiro.ebp)"),
        mthd = c("equal.ebp", "unequal.ebp")
    )
    twogrp.res <- hybrid.test(
        two_grp_data,
        test.specs,
        ebp.def
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hybridmtest_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hybridmtest_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hybridmtest_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HYBRIDMTEST:", paste0("    hybridmtest: ", packageVersion("HybridMTest"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hybridmtest_results.csv
    touch ${prefix}_hybridmtest_output.rds
    echo "BIOC_HYBRIDMTEST:" > versions.yml
    echo "    hybridmtest: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HYBRIDMTEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HYBRIDMTEST(ch_input)

    emit:
    results  = BIOC_HYBRIDMTEST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HYBRIDMTEST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HYBRIDMTEST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HYBRIDMTEST.out.versions  // channel: path(versions.yml)
}
