#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TFBSTools
// TFBSTools is a package for the analysis and manipulation of transcription factor binding sites. It i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TFBSTools/inst/doc/TFBSTools.R
// Upstream  : Biostrings, CNEr, JASPAR2014, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("TFBSTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TFBSTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tfbstools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tfbstools:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tfbstools:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tfbstools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tfbstools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tfbstools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TFBSTools)
    library(Matrix)
    library(PFMatrix)
    library(PFMatrixList)
    library(jsonlite)

    # --- Transcription Factor Motif Similarity Analysis [] ---
    # Key functions: PFMSimilarity, PWMSimilarity, permuteMatrix
    pfm_seq <- permuteMatrix(pfm, type="intra")
    pfm_list <- PFMatrixList(pfm1=pfm, pfm2=pfm_seq, use.names=TRUE)
    sim_pfm <- PFMSimilarity(pfm_list, pfm)
    pwm1 <- toPWM(pfm, type="prob")
    pwm2 <- toPWM(pfm_seq, type="prob")
    sim_pwm <- PWMSimilarity(pwm1, pwm2, method="Pearson")


    # --- Transcription Factor Binding Site Search [] ---
    # Key functions: searchSeq, writeGFF3, relScore, pvalues
    subject_seq <- Biostrings::DNAString("GAATTCTCTCTTGTTGTAGTCTCTTGACAAAATG")
    siteset <- searchSeq(
        pwm, subject_seq, seqname="seq1", 
        min.score="60%", strand="*"
    )
    gff_output <- writeGFF3(siteset)
    scores <- relScore(siteset)
    p_vals <- pvalues(siteset, type="TFMPvalue")


    # --- Genomic Alignment Search [] ---
    # Key functions: searchAln, toGRangesList
    aln1 <- Biostrings::DNAString("ACTTCACCAGCTCCCTGGCGGTAAGTTGATC")
    aln2 <- Biostrings::DNAString("GTTTCACTACTTCCTTTCGGGTAAGTAAATA")
    site_pair <- searchAln(
        pwm, aln1, aln2, seqname1="seq1", seqname2="seq2",
        min.score="50%", cutoff=0.5, strand="*", type="any"
    )
    gff_aln <- writeGFF3(site_pair)


    # --- Transcription Factor Flexible Models [] ---
    # Key functions: readXMLTFFM, getPosProb
    xml_file <- system.file("extdata", "tffm_first_order.xml", package="TFBSTools")
    tffm_first <- readXMLTFFM(xml_file, type="First")
    pos_prob <- getPosProb(tffm_first)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tfbstools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tfbstools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tfbstools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TFBSTOOLS:", paste0("    tfbstools: ", packageVersion("TFBSTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tfbstools_results.csv
    touch ${prefix}_tfbstools_output.rds
    echo "BIOC_TFBSTOOLS:" > versions.yml
    echo "    tfbstools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TFBSTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TFBSTOOLS(ch_input)

    emit:
    results  = BIOC_TFBSTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TFBSTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TFBSTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TFBSTOOLS.out.versions  // channel: path(versions.yml)
}
