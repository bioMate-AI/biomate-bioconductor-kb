#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RTN
// A transcriptional regulatory network (TRN) consists of a collection of transcription factors (TFs) a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RTN/inst/doc/RTN.R
// Upstream  : Fletcher2013b, SummarizedExperiment, TCGAbiolinks, pheatmap, snow
// Downstream: RTNduals, RTNsurvival, Fletcher2013b
//
// Install: BiocManager::install("RTN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RTN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rtn"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rtn:2.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rtn:2.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rtn_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rtn_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rtn_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RTN)
    library(jsonlite)

    # --- Label= 'Load A Sample Dataset' [] ---
    # Key functions: data
    ----------------------------
    library(RTN)
    data(tniData)
    # --- Label='Create A New Tni Object' [] ---
    # Key functions: constructor
    -----------
    # Input 1: 'expData', a named gene expression matrix (genes on rows, samples on cols);
    # Input 2: 'regulatoryElements', a vector listing genes regarded as TFs
    # Input 3: 'rowAnnotation', an optional data frame with gene annotation
    # Input 4: 'colAnnotation', an optional data frame with sample annotation
    # --- Label='Permutation' [] ---
    # Key functions: permutation
    -----------------------
    # Please set nPermutations >= 1000
    rtni <- tni.permutation(rtni, nPermutations = 100)
    # --- Label='Bootstrap' [] ---
    # Key functions: bootstrap
    -------------------------
    rtni <- tni.bootstrap(rtni)
    # --- Label='Run Dpi Filter' [] ---
    # Key functions: filter
    --------------------
    rtni <- tni.dpi.filter(rtni)
    # --- Label='Create A New Tna Object (Preprocess Tni To Tna)' [] ---
    # Key functions: preprocess
    # Input 1: 'object', a TNI object with regulons
    # Input 2: 'phenotype', a named numeric vector, usually log2 differential expression levels
    # Input 3: 'hits', a character vector, usually a set of differentially expressed genes
    # Input 4: 'phenoIDs', an optional data frame with gene anottation mapped to the phenotype
    data(tnaData)
    # --- Label='Run The Mra Method' [] ---
    # Key functions: mra
    ----------------
    # Run the MRA method
    rtna <- tna.mra(rtna)
    # --- Label='Run Gsea Method' [] ---
    # Key functions: gsea1
    -------------------
    # Run the GSEA method
    # Please set nPermutations >= 1000
    rtna <- tna.gsea1(rtna, nPermutations=100)
    # --- Label='Run The Gsea 2T Method' [] ---
    # Key functions: gsea2
    ------------
    # Run the GSEA-2T method
    # Please set nPermutations >= 1000
    rtna <- tna.gsea2(rtna, nPermutations = 100)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rtn_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rtn_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rtn_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RTN:", paste0("    rtn: ", packageVersion("RTN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rtn_results.csv
    touch ${prefix}_rtn_output.rds
    echo "BIOC_RTN:" > versions.yml
    echo "    rtn: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RTN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RTN(ch_input)

    emit:
    results  = BIOC_RTN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RTN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RTN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RTN.out.versions  // channel: path(versions.yml)
}
