#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TCseq
// Quantitative and differential analysis of epigenomic and transcriptomic time course sequencing data,
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TCseq/inst/doc/TCseq.R
// Upstream  : SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("TCseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TCSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tcseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tcseq:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tcseq:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tcseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tcseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tcseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DBanalysis)
    library(DBresult)
    library(SummarizedExperiment)
    library(TCA)
    library(TCAFromSummarizedExperiment)
    library(jsonlite)

    # --- Peakreference [] ---
    # Key functions: peakreference
    ## dir <- dir.peaks
    ## gf <- peakreference(dir = dir, pattern = "narrowpeaks")
    # --- Data [] ---
    # Key functions: data
    data("genomicIntervals")
    head(genomicIntervals)
    # --- Data [] ---
    # Key functions: TCA
    # Experiment design
    data("experiment_BAMfile")
    head(experiment_BAMfile)
    # create a TCA object
    tca <- TCA(design = experiment_BAMfile, genomicFeature = genomicIntervals)
    # --- Countreads [] ---
    # Key functions: countReads
    ## tca <- countReads(tca, dir = dir.BAM)
    # --- Data [] ---
    # Key functions: TCA
    #Experiment design without BAM file information
    data("experiment")
    #Counts table
    data("countsTable")
    # --- Counts [] ---
    # Key functions: counts
    ## counts(tca) <- countsTable
    # --- Suppresswarnings [] ---
    # Key functions: SummarizedExperiment, TCAFromSummarizedExperiment
    suppressWarnings(library(SummarizedExperiment))
    se <- SummarizedExperiment(assays=list(counts = countsTable), colData = experiment)
    tca <- TCAFromSummarizedExperiment(se = se, genomicFeature = genomicIntervals)
    # --- Dbanalysis [] ---
    # Key functions: DBanalysis
    tca <- DBanalysis(tca)
    # --- Dbresult [] ---
    # Key functions: DBresult
    DBres <- DBresult(tca, group1 = "0h", group2 = c("24h","40h","72h"))
    str(DBres, strict.width =  "cut")
    head(DBres$`24hvs0h`)
    # --- Timecoursetable [] ---
    # Key functions: timecourseTable
    # values are logFC
    tca <- timecourseTable(tca, value = "FC", control.group = "0h", norm.method = "rpkm", filter = TRUE)
    # --- Tctable [] ---
    # Key functions: tcTable
    t <- tcTable(tca)
    head(t)
    # --- Timeclust [] ---
    # Key functions: timeclust
    tca <- timeclust(tca, algo = "cm", k = 6, standardize = TRUE)
    # --- Timeclustplot [] ---
    # Key functions: timeclustplot, score
    ## p <- timeclustplot(tca, value = "z-score(PRKM)", cols = 3)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tcseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tcseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tcseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TCSEQ:", paste0("    tcseq: ", packageVersion("TCseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tcseq_results.csv
    touch ${prefix}_tcseq_output.rds
    echo "BIOC_TCSEQ:" > versions.yml
    echo "    tcseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TCSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TCSEQ(ch_input)

    emit:
    results  = BIOC_TCSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TCSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TCSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TCSEQ.out.versions  // channel: path(versions.yml)
}
