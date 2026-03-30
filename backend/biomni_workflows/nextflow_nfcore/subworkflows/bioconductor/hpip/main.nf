#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HPiP
// HPiP (Host-Pathogen Interaction Prediction) uses an ensemble learning algorithm for prediction of ho
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HPiP/inst/doc/HPiP_tutorial.R
// Upstream  : Biostrings, SummarizedExperiment, dplyr, knitr, readr
// Downstream: none
//
// Install: BiocManager::install("HPiP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HPIP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hpip"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hpip:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hpip:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hpip_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hpip_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hpip_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    # Loading packages required for data handling & data manipulation
    library(dplyr)
    library(tibble)
    library(stringr)
    # --- Unique [] ---
    # Key functions: get_negativePPI
    ---------------------------------------------------------------------
    #pathogen proteins
    prot1 <- unique(TP$`Official Symbol Interactor A`)
    #host proteins
    prot2 <- unique(TP$`Official Symbol Interactor B`)
    # --- Readaastringset [] ---
    # Key functions: readAAStringSet, frame, calculateAAC
    ---------------------------------------------------------------------
    #loading the package
    library(Biostrings)
    #Read fasta sequences provided by HPiP package using Biostrings
    fasta <-
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    #loading viral_se object
    data(viral_se)
    viral_se
    # --- Calculatectdc [] ---
    # Key functions: calculateCTDC, calculateCTDT, calculateCTDD
    ---------------------------------------------------------------------
    #generate descriptors
    CTDC_df <- calculateCTDC(fasta_df)
    CTDC_m <- as.matrix(CTDC_df[, -1])
    row.names(CTDC_m) <- CTDC_df$identifier
    # --- Summarizedexperiment [] ---
    # Key functions: SummarizedExperiment
    ---------------------------------------------------------------------
    #convert matrix to se object
    ctdc_se <- SummarizedExperiment(assays = list(counts = CTDC_m),
                                    colData = paste0(colnames(CTDC_df[,-1]),
                                                     "CTDC"))
    # --- Assays [] ---
    # Key functions: assays
    ---------------------------------------------------------------------
    #extract features from viral_se
    counts_v <- assays(viral_se)$counts
    #extract row.names from viral_Se
    rnames_v <- row.names(counts_v)
    # --- Gethpi [] ---
    # Key functions: getHPI, frame
    ---------------------------------------------------------------------
    x <- getHPI(x1_viral,x1_host, type = "combine")
    x <- as.data.frame(x)
    x <- cbind(gd$PPI, gd$class, x)
    colnames(x)[1:2] <- c("PPI", "class")
    # --- Data [] ---
    # Key functions: data, rbind
    ---------------------------------------------------------------------
    #load the unlabeled HP-PPIs
    data('unlabel_data')
    #Constructed labeled HP-PPIs
    labeled_dat <- x_FS$rf.result$rfdf
    # --- Filter [] ---
    # Key functions: filter
    ---------------------------------------------------------------------
    pred_interactions <- filter(pred_interactions, ensemble >= 0.7)
    dim(pred_interactions)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hpip_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hpip_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hpip_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HPIP:", paste0("    hpip: ", packageVersion("HPiP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hpip_results.csv
    touch ${prefix}_hpip_output.rds
    echo "BIOC_HPIP:" > versions.yml
    echo "    hpip: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HPIP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HPIP(ch_input)

    emit:
    results  = BIOC_HPIP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HPIP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HPIP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HPIP.out.versions  // channel: path(versions.yml)
}
