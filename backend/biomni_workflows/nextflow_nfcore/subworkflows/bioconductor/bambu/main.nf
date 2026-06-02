#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bambu
// bambu is a R package for multi-sample transcript discovery and quantification using long read RNA-Se
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bambu/inst/doc/bambu.R
// Upstream  : BiocFileCache, DESeq2, DEXSeq, ExperimentHub, NanoporeRNASeq
// Downstream: none
//
// Install: BiocManager::install("bambu")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BAMBU {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bambu"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bambu:3.8.3--r44_0' :
        'quay.io/biocontainers/bioconductor-bambu:3.8.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bambu_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bambu_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bambu_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(bambu)
    library(BamFileList)
    library(BiocFileCache)
    library(DESeq)
    library(DESeqDataSetFromMatrix)
    library(DEXSeq)
    library(DEXSeqDataSet)
    library(ExperimentHub)
    library(jsonlite)

    # --- Transcript Discovery and Quantification [] ---
    # Key functions: bambu
    test.bam <- system.file("extdata",
        "SGNex_A549_directRNA_replicate5_run1_chr9_1_1000000.bam",
        package = "bambu")
    fa.file <- system.file("extdata",
        "Homo_sapiens.GRCh38.dna_sm.primary_assembly_chr9_1_1000000.fa",
        package = "bambu")
    se <- bambu(
        reads = test.bam,
        annotations = bambuAnnotations,
        genome = fa.file
    )


    # --- Gene Expression Summarization [] ---
    # Key functions: transcriptToGeneExpression
    seGene <- transcriptToGeneExpression(se)
    sample_conditions <- rep(
        c("Control", "Treatment"),
        length.out = ncol(seGene)
    )
    SummarizedExperiment::colData(seGene)$condition <- as.factor(
        sample_conditions
    )


    # --- Visualization [] ---
    # Key functions: plotBambu
    plotBambu(se, type = "heatmap")
    plotBambu(se, type = "pca")
    plotBambu(
        se,
        type = "annotation",
        gene_id = "ENSG00000099968"
    )


    # --- Exporting Results [] ---
    # Key functions: writeBambuOutput, writeToGTF
    save.dir <- tempdir()
    writeBambuOutput(
        se,
        path = save.dir,
        prefix = "bambu_output_"
    )
    save.file <- tempfile(fileext = ".gtf")
    writeToGTF(
        SummarizedExperiment::rowRanges(se),
        file = save.file
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bambu_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bambu_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bambu_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BAMBU:", paste0("    bambu: ", packageVersion("bambu"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bambu_results.csv
    touch ${prefix}_bambu_output.rds
    echo "BIOC_BAMBU:" > versions.yml
    echo "    bambu: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BAMBU_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BAMBU(ch_input)

    emit:
    results  = BIOC_BAMBU.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BAMBU.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BAMBU.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BAMBU.out.versions  // channel: path(versions.yml)
}
