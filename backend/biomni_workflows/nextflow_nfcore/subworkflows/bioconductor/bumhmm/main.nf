#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BUMHMM
// This is a probabilistic modelling pipeline for computing per- nucleotide posterior probabilities of 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BUMHMM/inst/doc/BUMHMM.R
// Upstream  : Biostrings, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("BUMHMM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BUMHMM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bumhmm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bumhmm:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bumhmm:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bumhmm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bumhmm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bumhmm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(List)
    library(jsonlite)

    # --- Style Knitr [] ---
    # Key functions: latex
    ----------------
    BiocStyle::latex()
    # --- Head [] ---
    # Key functions: assay
    ------------------------------------------------------------------
    controls <- se[, se$replicate == "control"]
    head(assay(controls, 'coverage'))
    # --- Rowdata [] ---
    # Key functions: rowData
    ------------------------------------------------------------------
    rowData(controls)[1:4,]
    # --- Coldata [] ---
    # Key functions: colData
    ------------------------------------------------------------------
    colData(controls)
    # --- Assay [] ---
    # Key functions: assay
    ------------------------------------------------------------------
    pos <- 300
    assay(controls, 'coverage')[pos, 1]
    assay(controls, 'dropoff_count')[pos, 1]
    assay(controls, 'dropoff_rate')[pos, 1]
    # --- Selectnuclpos [] ---
    # Key functions: selectNuclPos, List
    ------------------------------------------------------------------
    Nc <- Nt <- 3
    t <- 1
    nuclSelection <- selectNuclPos(se, Nc, Nt, t)
    List(nuclSelection)
    # --- Apply [] ---
    # Key functions: assay, scaleDOR
    ------------------------------------------------------------------
    ## Medians of original drop-off rates in each replicate
    apply(assay(se, 'dropoff_rate'), 2, median)
    ## Scale drop-off rates
    assay(se, "dropoff_rate") <- scaleDOR(se, nuclSelection, Nc, Nt)
    # --- Computestretches [] ---
    # Key functions: computeStretches
    ------------------------------------------------------------------
    stretches <- computeStretches(se, t)
    # --- Head [] ---
    # Key functions: assay
    ------------------------------------------------------------------
    head(stretches)
    assay(se, 'dropoff_count')[1748,]
    # --- Stabilisevariance [] ---
    # Key functions: stabiliseVariance
    ------------------------------------------------------------------
    varStab <- stabiliseVariance(se, nuclSelection, Nc, Nt)
    LDR_C <- varStab$LDR_C
    LDR_CT <- varStab$LDR_CT
    hist(LDR_C, breaks = 30, main = 'Null distribution of LDRs')
    # --- Nuclperm [] ---
    # Key functions: nuclPerm
    ------------------------------------------------------------------
    nuclNum <- 3
    patterns <- nuclPerm(nuclNum)
    patterns
    # --- Subject [] ---
    # Key functions: subject, rowData, findPatternPos
    ------------------------------------------------------------------
    ## Extract the DNA sequence
    sequence <- subject(rowData(se)$nucl)
    sequence
    nuclPosition <- findPatternPos(patterns, sequence, '+')
    # --- Computeprobs [] ---
    # Key functions: computeProbs
    ------------------------------------------------------------------
    posteriors <- computeProbs(LDR_C, LDR_CT, Nc, Nt, '+', nuclPosition,
                                 nuclSelection$analysedC, nuclSelection$analysedCT,
                                 stretches)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bumhmm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bumhmm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bumhmm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BUMHMM:", paste0("    bumhmm: ", packageVersion("BUMHMM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bumhmm_results.csv
    touch ${prefix}_bumhmm_output.rds
    echo "BIOC_BUMHMM:" > versions.yml
    echo "    bumhmm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BUMHMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BUMHMM(ch_input)

    emit:
    results  = BIOC_BUMHMM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BUMHMM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BUMHMM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BUMHMM.out.versions  // channel: path(versions.yml)
}
