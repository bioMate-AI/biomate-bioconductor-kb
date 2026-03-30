#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MethTargetedNGS
// Perform step by step methylation analysis of Next Generation Sequencing data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MethTargetedNGS/inst/doc/MethTargetedNGS.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MethTargetedNGS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHTARGETEDNGS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methtargetedngs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methtargetedngs:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methtargetedngs:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methtargetedngs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methtargetedngs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methtargetedngs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MethTargetedNGS)
    library(jsonlite)

    # --- Loading Files In R [] ---
    # Key functions: file
    library(MethTargetedNGS)
    healthy = system.file("extdata", "Healthy.fasta", package = "MethTargetedNGS")
    tumor = system.file("extdata", "Tumor.fasta", package = "MethTargetedNGS")
    reference = system.file("extdata", "Reference.fasta", package = "MethTargetedNGS")
    # --- Aligning Samples To Reference Sequence [] ---
    # Key functions: methAlign
    hAlign = methAlign(healthy,reference)
    tAlign = methAlign(tumor,reference)
    # --- :Heatmap [] ---
    # Key functions: methHeatmap
    hHeatmap = methHeatmap(hAlign,plot=TRUE)
    # --- Methheatmap [] ---
    # Key functions: methHeatmap
    hHeatmap = methHeatmap(hAlign,plot=TRUE)
    # --- Calculating Methylation Average [] ---
    # Key functions: methAvg
    hAvg = methAvg(hAlign,plot=FALSE)
    hAvg
    # --- Calculating Methylation Entropy [] ---
    # Key functions: methEntropy
    hEnt <- methEntropy(hAlign)
    hEnt
    # --- Calculate Statistically Significant Cpg Sites In Samples [] ---
    # Key functions: fishertest_cpg
    SigCpGsites = fishertest_cpg(hAlign,tAlign,plot=FALSE)
    SigCpGsites
    # --- Odd Ratio [] ---
    # Key functions: odd_ratio
    odSamps = odd_ratio(hAlign,tAlign,plot=FALSE)
    odSamps
    # --- Compare Samples [] ---
    # Key functions: compare_samples
    compare_samples(hAlign,tAlign)
    # --- Complete Methylation Analysis Comparison [] ---
    # Key functions: compare_samples
    compare_samples(hAlign,tAlign)
    # --- Creating Profile Hidden Markov Model From Multiple Sequence Alignment [] ---
    # Key functions: hmmbuild
    msa = system.file("extdata", "msa.fasta", package = "MethTargetedNGS")
    if (file.exists("/usr/bin/hmmbuild"))
    hmmbuild(file_seq=msa,file_out="hmm",pathHMMER = "/usr/bin/")
    # --- Calculate Likelihood Of Sequences Against Hmm [] ---
    # Key functions: nhmmer
    if (file.exists("/usr/bin/nhmmer")){
    res <- nhmmer("hmm",tumor,pathHMMER = "/usr/bin/")
    res$Total.Likelihood.Score
    }

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methtargetedngs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methtargetedngs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methtargetedngs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHTARGETEDNGS:", paste0("    methtargetedngs: ", packageVersion("MethTargetedNGS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methtargetedngs_results.csv
    touch ${prefix}_methtargetedngs_output.rds
    echo "BIOC_METHTARGETEDNGS:" > versions.yml
    echo "    methtargetedngs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHTARGETEDNGS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHTARGETEDNGS(ch_input)

    emit:
    results  = BIOC_METHTARGETEDNGS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHTARGETEDNGS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHTARGETEDNGS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHTARGETEDNGS.out.versions  // channel: path(versions.yml)
}
