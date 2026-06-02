#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: doseR
// doseR package is a next generation sequencing package for sex chromosome dosage compensation which c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/doseR/inst/doc/doseR.R
// Upstream  : digest
// Downstream: none
//
// Install: BiocManager::install("doseR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DOSER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-doser"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-doser:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-doser:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_doser_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_doser_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_doser_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DataFrame)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(hmel.data.doser)
    # --- Frame [] ---
    # Key functions: frame, factor, ifelse
    ---------------------------------------------------------------------
    annotxn <- data.frame("Chromosome" = factor(hmel.dat$chromosome,
    levels = 1:21))
    annotxn$ZA <- factor(ifelse(hmel.dat$chromosome == 21, "Z", "A"),
    levels = c("A", "Z"))
    # --- Dataframe [] ---
    # Key functions: DataFrame, factor, SummarizedExperiment
    ---------------------------------------------------------------------
    counts <- hmel.dat$readcounts
    colData <- S4Vectors::DataFrame(Treatment=as.factor(reps),
    row.names=colnames(hmel.dat$readcounts))
    # --- Coldata [] ---
    # Key functions: colData, getLibsizes3
    ---------------------------------------------------------------------
    SummarizedExperiment::colData(se2)$Libsizes <- getLibsizes3(se2,
    estimationType = "total")
    # --- Assays [] ---
    # Key functions: assays, make_RPKM, digest
    ---------------------------------------------------------------------
    SummarizedExperiment::assays(se2)$rpkm <- make_RPKM(se2)
    # se2 now equals se...
    data(hmel.se)  # loads hmel.dat list
    # MD5 checksum equivalence:
    # --- Simplefilter [] ---
    # Key functions: simpleFilter
    ---------------------------------------------------------------------
    f_se <- simpleFilter(se, mean_cutoff = 0.01, counts = FALSE)
    # --- Coldata [] ---
    # Key functions: colData, generateStats, test
    ---------------------------------------------------------------------
    se.male <- f_se[, colData(f_se)$Treatment == "Male"]
    male_ZvA <- generateStats(se.male , groupings = "annotation.ZA", LOG2 = FALSE)
    male_ZvA$summary  # distributional summary statistics
    male_ZvA$kruskal  # htest class output from kruskal.test()
    # --- Test Diffs [] ---
    # Key functions: test_diffs, test
    ---------------------------------------------------------------------
    za.ratios.test <- test_diffs(f_se, groupings = "annotation.ZA",
    treatment1 = "Male", treatment2 = "Female", LOG2 = FALSE )
    za.ratios.test$summary  # summary statistics for each grouping
    za.ratios.test$kruskal  # htest class output from kruskal.test()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_doser_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_doser_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_doser_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DOSER:", paste0("    doser: ", packageVersion("doseR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_doser_results.csv
    touch ${prefix}_doser_output.rds
    echo "BIOC_DOSER:" > versions.yml
    echo "    doser: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DOSER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DOSER(ch_input)

    emit:
    results  = BIOC_DOSER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DOSER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DOSER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DOSER.out.versions  // channel: path(versions.yml)
}
