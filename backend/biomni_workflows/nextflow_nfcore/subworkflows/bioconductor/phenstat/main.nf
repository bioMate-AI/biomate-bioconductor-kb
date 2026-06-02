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
    library(PhenList)
    library(PhenStatReport)
    library(TFDataset)
    library(WhatIsNew)
    library(jsonlite)

    # --- R Hide 000 [] ---
    # Key functions: setenv, compactPDF
    #Sys.setenv(R_GSCMD = "C:\\Program Files\\gs\\gs9.21\\bin\\gswin64.exe")
    #tools::compactPDF(paths = 'C:\\Users\\hamedhm\\Google Drive\\At work\\ Publications. Shared with Terry and Jeremy\\PhenStat changes\\PhenStat_2.8.0\\PhenStat\\inst\\doc',gs_quality = "ebook")
    suppressPackageStartupMessages(library(PhenStat))
    # --- R Hide 001 [] ---
    # Key functions: WhatIsNew
    PhenStat:::WhatIsNew()
    # --- R Hide002 [] ---
    # Key functions: file
    library(PhenStat)
    dataset1 <- system.file("extdata", "test1.csv", package = "PhenStat")
    dataset2 <- system.file("extdata", "test1.txt", package = "PhenStat")
    # --- R Hide003 [] ---
    # Key functions: PhenList, csv
    # Default behaviour with messages
    library(PhenStat)
    dataset1 <- system.file("extdata", "test1.csv", package = "PhenStat")
    test <- PhenList(dataset = read.csv(dataset1, na.strings = '-'),
                     testGenotype = "Sparc/Sparc")
    # --- R Hide004 [] ---
    # Key functions: PhenList, csv
    library(PhenStat)
    dataset1 <- system.file("extdata", "test3.csv", package="PhenStat")
    # --- R Hide005 [] ---
    # Key functions: PhenList, csv, getDataset
    library(PhenStat)
    dataset1 <- system.file("extdata", "test3.csv", package="PhenStat")
    # --- R Hide006 [] ---
    # Key functions: PhenList, csv, testGenotype, refGenotype
    library(PhenStat)
    dataset2 <- system.file("extdata", "test2.csv", package="PhenStat")
    test2 <- PhenList(dataset=read.csv(dataset2,na.strings = '-'),
                      testGenotype="Arid4a/Arid4a",
                      dataset.colname.weight="Weight.Value")
    # --- R Hide007 [] ---
    # Key functions: PhenList, csv, PhenStatReport
    ## file <- system.file("extdata", "test1.csv", package = "PhenStat")
    ## test = PhenStat:::PhenList(dataset = read.csv(file, na.strings = '-'),
    ##                            testGenotype = "Sparc/Sparc")
    # --- R Hide008 [] ---
    # Key functions: PhenList, csv, testDataset, analysisResults, finalModel
    library(PhenStat)
    dataset1 <- system.file("extdata", "test1.csv", package="PhenStat")
    test <- PhenList(dataset=read.csv(dataset1,na.strings = '-'),
                     testGenotype="Sparc/Sparc",
                     outputMessages=FALSE)
    # --- R Hide009 [] ---
    # Key functions: testFinalModel, classificationTag
    PhenStat:::testFinalModel(result)
    PhenStat:::classificationTag(result)
    # --- R Hide010 [] ---
    # Key functions: PhenList, csv, TFDataset, testDataset
    file <- system.file("extdata", "test7_TFE.csv", package="PhenStat")
    # --- R Hide011 [] ---
    # Key functions: PhenList, csv, testDataset
    library(PhenStat)
    file <- system.file("extdata", "test1.csv", package="PhenStat")
    test <- PhenList(dataset=read.csv(file,na.strings = '-'),
                     testGenotype="Sparc/Sparc")
    # RR method is called
    # --- R Hide012 [] ---
    # Key functions: PhenList, csv, testDataset, getVariable, method
    library(PhenStat)
    dataset_cat <- system.file("extdata", "test_categorical.csv", package="PhenStat")
    test_cat <- PhenList(read.csv(dataset_cat,na.strings = '-'),testGenotype="Aff3/Aff3")
    # --- R Hide013 [] ---
    # Key functions: PhenList, csv, testDataset
    library(PhenStat)
    dataset1 <- system.file("extdata", "test1.csv", package="PhenStat")
    # MM framework
    test <- PhenList(dataset=read.csv(dataset1,na.strings = '-'),
                     testGenotype="Sparc/Sparc",outputMessages=FALSE)
    # --- R Hide014 [] ---
    # Key functions: PhenList, csv, testDataset
    library(PhenStat)
    dataset_cat <- system.file("extdata", "test_categorical.csv", package="PhenStat")
    test2 <- PhenList(dataset=read.csv(dataset_cat,na.strings = '-'),
                      testGenotype="Aff3/Aff3",outputMessages=FALSE)

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
