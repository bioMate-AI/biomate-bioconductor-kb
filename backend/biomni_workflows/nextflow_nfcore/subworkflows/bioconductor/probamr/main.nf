#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: proBAMr
// Mapping PSMs back to genome. The package builds SAM file from shotgun proteomics data The package al
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/proBAMr/inst/doc/proBAMr.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("proBAMr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROBAMR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-probamr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-probamr:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-probamr:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_probamr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_probamr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_probamr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(proBAMr)
    library(PSMtab2SAM)
    library(PrepareAnnotationGENCODE)
    library(jsonlite)

    # --- GENCODE Annotation Preparation ---
    # Key functions: PrepareAnnotationGENCODE
    gtfFile <- system.file("extdata", "test.gtf", package="proBAMr")
    CDSfasta <- system.file("extdata", "coding_seq.fasta", package="proBAMr")
    pepfasta <- system.file("extdata", "pro_seq.fasta", package="proBAMr")
    annotation_path <- tempdir()
    PrepareAnnotationGENCODE(
        gtfFile, 
        CDSfasta, 
        pepfasta, 
        annotation_path, 
        dbsnp=NULL, 
        splice_matrix=FALSE, 
        COSMIC=FALSE
    )

    # --- RefSeq Annotation Preparation ---
    # Key functions: PrepareAnnotationRefseq
    CDSfasta <- system.file("extdata", "coding_seq.fasta", package="proBAMr")
    pepfasta <- system.file("extdata", "pro_seq.fasta", package="proBAMr")
    annotation_path <- tempdir()
    PrepareAnnotationRefseq(
        genome="hg19",
        CDSfasta=CDSfasta,
        pepfasta=pepfasta,
        annotation_path=annotation_path,
        dbsnp=NULL,
        splice_matrix=FALSE,
        COSMIC=FALSE
    )

    # --- PSM to SAM Conversion ---
    # Key functions: PSMtab2SAM
    load(system.file("extdata/GENCODE", "exon_anno.RData", package="proBAMr"))
    load(system.file("extdata/GENCODE", "proseq.RData", package="proBAMr"))
    load(system.file("extdata/GENCODE", "procodingseq.RData", package="proBAMr"))
    passedPSM <- read.table(
        system.file("extdata", "passedPSM.tab", package="proBAMr"),
        sep="\t",
        header=TRUE,
        stringsAsFactors=FALSE
    )
    SAM <- PSMtab2SAM(
        passedPSM,
        XScolumn="mvh",
        exon,
        proteinseq,
        procodingseq
    )
    write.table(
        SAM,
        file=file.path(tempdir(), "test.sam"),
        sep="\t",
        quote=FALSE,
        row.names=FALSE,
        col.names=FALSE
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_probamr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_probamr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_probamr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROBAMR:", paste0("    probamr: ", packageVersion("proBAMr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_probamr_results.csv
    touch ${prefix}_probamr_output.rds
    echo "BIOC_PROBAMR:" > versions.yml
    echo "    probamr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROBAMR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROBAMR(ch_input)

    emit:
    results  = BIOC_PROBAMR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROBAMR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROBAMR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROBAMR.out.versions  // channel: path(versions.yml)
}
