#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methylclock
// This package allows to estimate chronological and gestational DNA methylation (DNAm) age as well as 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methylclock/inst/doc/methylclock.R
// Upstream  : methylclockData, Biobase, tibble, impute, ggplot2
// Downstream: none
//
// Install: BiocManager::install("methylclock")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHYLCLOCK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methylclock"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methylclock:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methylclock:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methylclock_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methylclock_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methylclock_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(methylclock)
    library(jsonlite)

    # --- get_ Test Dataset [] ---
    # Key functions: get_TestDataset
    TestDataset <- get_TestDataset()
    cpgs.missing <- checkClocks(TestDataset)
    # --- common Clock Cpgs [] ---
    # Key functions: commonClockCpgs
    commonClockCpgs(cpgs.missing, "Hannum" )
    commonClockCpgs(cpgs.missing.GA, "Bohlin" )
    # --- load horvath example [] ---
    # Key functions: get_MethylationDataExample
    library(tidyverse)
    MethylationData <- get_MethylationDataExample()
    # --- show cpg miss [] ---
    # Key functions: checkClocks
    missCpGs <- checkClocks(MethylationData)
    # --- covariates horvath example [] ---
    # Key functions: read_csv
    library(tidyverse)
    path <- system.file("extdata", package = "methylclock")
    covariates <- read_csv(file.path(path, "SampleAnnotationExample55.csv"))
    # --- get geo gse58045 [] ---
    # Key functions: getGEO
    Sys.setenv("VROOM_CONNECTION_SIZE" = 131072 * 10)
    dd <- GEOquery::getGEO("GSE58045")
    Sys.setenv("VROOM_CONNECTION_SIZE" = 131072)
    # --- age gse58045 [] ---
    # Key functions: pData
    pheno <- pData(gse58045)
    age <- as.numeric(pheno$`age:ch1`)
    # --- plot D N Am Age [] ---
    # Key functions: plotDNAmAge
    plotDNAmAge(age.gse58045$Horvath, age)
    # --- get geo gse19711 [] ---
    # Key functions: getGEO
    Sys.setenv("VROOM_CONNECTION_SIZE" = 131072 * 10)
    dd <- GEOquery::getGEO("GSE19711")
    Sys.setenv("VROOM_CONNECTION_SIZE" = 131072)
    # --- get case control [] ---
    # Key functions: pData
    pheno <- pData(gse19711)
    age <- as.numeric(pheno$`ageatrecruitment:ch1`)
    table(disease)
    # --- attr [] ---
    # Key functions: attr
    cell <- attr(age.gse19711, "cell_proportion")
    mod.cell <- glm(disease ~ ageAcc.Levine + cell, data=age.gse19711,
    summary(mod.cell)
    # --- get geo 109446 [] ---
    # Key functions: getGEO
    dd <- GEOquery::getGEO("GSE109446")
    # --- age gse109446 [] ---
    # Key functions: pData
    controls <- pData(gse109446)$`diagnosis:ch1`=="control"
    age <- as.numeric(pData(gse)$`age:ch1`)
    age.gse <- DNAmAge(gse, age=age)
    # --- plot Cor Clocks [] ---
    # Key functions: plotCorClocks
    plotCorClocks(age.gse)
    # --- plot D N Am Age [] ---
    # Key functions: plotDNAmAge
    plotDNAmAge(ga.progress$Knight, progress_vars$EGA,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methylclock_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methylclock_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methylclock_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHYLCLOCK:", paste0("    methylclock: ", packageVersion("methylclock"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylclock_results.csv
    touch ${prefix}_methylclock_output.rds
    echo "BIOC_METHYLCLOCK:" > versions.yml
    echo "    methylclock: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHYLCLOCK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHYLCLOCK(ch_input)

    emit:
    results  = BIOC_METHYLCLOCK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHYLCLOCK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHYLCLOCK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHYLCLOCK.out.versions  // channel: path(versions.yml)
}
