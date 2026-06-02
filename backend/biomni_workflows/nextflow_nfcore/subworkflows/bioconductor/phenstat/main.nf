#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PhenStat
// Package contains methods for statistical analysis of phenotypic data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PhenStat/inst/doc/PhenStat.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("PhenStat")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHENSTAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-phenstat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-phenstat:2.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-phenstat:2.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_phenstat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_phenstat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_phenstat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PhenStat)
    library(PhenList)
    library(PhenStatReport)
    library(TFDataset)
    library(WhatIsNew)
    library(jsonlite)

    # --- Mixed Model Statistical Analysis [] ---
    # Key functions: PhenList, testDataset
    dataset_path <- system.file("extdata", "test1.csv", package = "PhenStat")
    raw_data <- read.csv(dataset_path, na.strings = "-")
    pheno_data <- PhenList(
        dataset = raw_data,
        testGenotype = "Sparc/Sparc",
        outputMessages = FALSE
    )
    result <- testDataset(
        pheno_data,
        depVariable = "Bone.Area",
        equation = "withoutWeight"
    )


    # --- Time Fixed Effect Analysis [] ---
    # Key functions: PhenList, TFDataset, testDataset
    file_path <- system.file("extdata", "test7_TFE.csv", package = "PhenStat")
    raw_data <- read.csv(file_path, na.strings = "-")
    test_list <- PhenList(
        dataset = raw_data,
        testGenotype = "het",
        refGenotype = "WT",
        dataset.colname.sex = "sex",
        dataset.colname.genotype = "Genotype",
        dataset.values.female = "f",
        dataset.values.male = "m",
        dataset.colname.weight = "body.weight",
        dataset.colname.batch = "Date_of_procedure_start"
    )
    test_tf <- TFDataset(test_list, depVariable = "Cholesterol")
    result_tf <- testDataset(test_tf, depVariable = "Cholesterol", method = "TF")


    # --- Reference Range Framework [] ---
    # Key functions: PhenList, testDataset
    dataset_path <- system.file("extdata", "test1.csv", package = "PhenStat")
    raw_data <- read.csv(dataset_path, na.strings = "-")
    pheno_data <- PhenList(
        dataset = raw_data,
        testGenotype = "Sparc/Sparc",
        outputMessages = FALSE
    )
    result_rr <- testDataset(
        pheno_data,
        depVariable = "Lean.Mass",
        method = "RR"
    )


    # --- Categorical Association Testing [] ---
    # Key functions: PhenList, testDataset
    cat_path <- system.file("extdata", "test_categorical.csv", package = "PhenStat")
    raw_cat <- read.csv(cat_path, na.strings = "-")
    test_cat <- PhenList(
        dataset = raw_cat,
        testGenotype = "Aff3/Aff3",
        outputMessages = FALSE
    )
    result_cat <- testDataset(
        test_cat,
        depVariable = "Thoracic.Processes",
        method = "FE",
        outputMessages = FALSE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_phenstat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_phenstat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_phenstat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHENSTAT:", paste0("    phenstat: ", packageVersion("PhenStat"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phenstat_results.csv
    touch ${prefix}_phenstat_output.rds
    echo "BIOC_PHENSTAT:" > versions.yml
    echo "    phenstat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHENSTAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHENSTAT(ch_input)

    emit:
    results  = BIOC_PHENSTAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHENSTAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHENSTAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHENSTAT.out.versions  // channel: path(versions.yml)
}
