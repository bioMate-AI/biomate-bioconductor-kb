#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: kissDE
// Retrieves condition-specific variants in RNA-seq data (SNVs, alternative-splicings, indels). It has 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/kissDE/inst/doc/kissDE.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("kissDE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KISSDE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-kissde"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-kissde:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-kissde:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_kissde_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_kissde_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_kissde_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(kissDE)
    library(jsonlite)

    # --- Installbc [] ---
    # Key functions: packages
    ## install.packages("BiocManager")
    # --- Quick Start [] ---
    # Key functions: kissplice2counts, qualityControl, diffExpressedVariants, writeOutputKissDE
    ## counts <- kissplice2counts("output_kissplice.fa")
    ## conditions <- c(rep("condition_1", 2), rep("condition_2", 2))
    ## qualityControl(counts, conditions)
    ## results <- diffExpressedVariants(counts, conditions)
    ## writeOutputKissDE(results, output = "kissDE_output.tab")
    # --- Conditionvector Howto [] ---
    # Key functions: rep
    myConditions <- c(rep("condition_1", 2), rep("condition_2", 2))
    # --- Conditionvectorremove Howto [] ---
    # Key functions: rep
    ## myConditionsRm <- c(rep("condition_1", 2), rep("*", 2), rep("condition_3", 2))
    # --- Tablecounts Howto [] ---
    # Key functions: file
    fpath1 <- system.file("extdata", "table_counts_alt_splicing.txt",
        package="kissDE")
    tableCounts <- read.table(fpath1, head = TRUE)
    # --- Kissplice Format [] ---
    # Key functions: file
    headfasta <- system.file("extdata",
        "head_output_kissplice_alt_splicing_fasta.txt", package = "kissDE")
    writeLines(readLines(headfasta))
    # --- Kissplice2Counts Howto [] ---
    # Key functions: kissplice2counts
    fpath2 <- system.file("extdata", "output_kissplice_alt_splicing.fa",
        package="kissDE")
    myCounts <- kissplice2counts(fpath2, pairedEnd = TRUE)
    # --- Kissplice2Counts K2Rg Howto [] ---
    # Key functions: kissplice2counts
    fpath3 <- system.file("extdata", "output_k2rg_alt_splicing.txt",
        package="kissDE")
    myCounts_k2rg <- kissplice2counts(fpath3,
        pairedEnd = TRUE, k2rg = TRUE)
    names(myCounts_k2rg)
    # --- Kissplice2Counts K2Rg Esonly Howto [] ---
    # Key functions: kissplice2counts
    myCounts_k2rg_ES <- kissplice2counts(fpath3, pairedEnd = TRUE,
        k2rg = TRUE, keep = c("ES"),
        remove = c("MULTI", "altA", "altD", "altAD", "MULTI_altA",
        "MULTI_altD", "MULTI_altAD"))
    # --- Qualitycontrol Howto [] ---
    # Key functions: qualityControl
    qualityControl(myCounts, myConditions)
    # --- Returnpcadata Howto [] ---
    # Key functions: qualityControl
    ## PCAdata <- qualityControl(myCounts, myConditions, returnPCAdata = TRUE)
    # --- Diffexpressedvariants Howto [] ---
    # Key functions: diffExpressedVariants
    myResults <- diffExpressedVariants(countsData = myCounts,
        conditions = myConditions)
    # --- Finaltable Description [] ---
    # Key functions: headhead
    # print(headhead(myResults$finalTable, n = 3), row.names = FALSE)
    print(str(myResults))
    # --- Finaltable Write [] ---
    # Key functions: writeOutputKissDE
    ## writeOutputKissDE(myResults, output = "kissDE_results_table.tab")
    # --- Finaltable Thresholds Write [] ---
    # Key functions: writeOutputKissDE
    ## writeOutputKissDE(myResults, output = "kissDE_results_table_filtered.tab",
    ##     adjPvalMax = 0.05, dPSImin = 0.10)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_kissde_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_kissde_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_kissde_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_KISSDE:", paste0("    kissde: ", packageVersion("kissDE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_kissde_results.csv
    touch ${prefix}_kissde_output.rds
    echo "BIOC_KISSDE:" > versions.yml
    echo "    kissde: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KISSDE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KISSDE(ch_input)

    emit:
    results  = BIOC_KISSDE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KISSDE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KISSDE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KISSDE.out.versions  // channel: path(versions.yml)
}
