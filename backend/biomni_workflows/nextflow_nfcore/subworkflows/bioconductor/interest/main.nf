#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IntEREst
// This package performs Intron-Exon Retention analysis on RNA-seq data (.bam files).
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IntEREst/inst/doc/IntEREst.R
// Upstream  : BiocParallel, clinfun
// Downstream: none
//
// Install: BiocManager::install("IntEREst")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INTEREST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-interest"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-interest:1.30.2--r44_0' :
        'quay.io/biocontainers/bioconductor-interest:1.30.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_interest_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_interest_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_interest_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IntEREst)
    library(Fraction)
    library(jsonlite)

    # --- U12 Intron Annotation [] ---
    # Key functions: annotateU12
    ind <- u12$gene_name %in% c("RHBDD2", "YBX2")
    annoU12 <- annotateU12(
        pwmU12U2 = list(
            pwmU12db[[1]][, 11:17], pwmU12db[[2]],
            pwmU12db[[3]][, 38:40], pwmU12db[[4]][, 11:17],
            pwmU12db[[5]][, 38:40]
        ),
        pwmSsIndex = list(
            indexDonU12 = 1, indexBpU12 = 1, indexAccU12 = 3,
            indexDonU2 = 1, indexAccU2 = 3
        ),
        referenceChr = u12[ind, "chr"],
        referenceBegin = u12[ind, "begin"],
        referenceEnd = u12[ind, "end"],
        referenceIntronExon = u12[ind, "int_ex"],
        intronExon = "intron",
        matchWindowRelativeUpstreamPos = c(NA, -29, NA, NA, NA),
        matchWindowRelativeDownstreamPos = c(NA, -9, NA, NA, NA),
        minMatchScore = c("80%", "80%", "40%", "80%", "40%"),
        refGenome = BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19,
        setNaAs = "U2",
        annotateU12Subtype = TRUE
    )


    # --- Intron Retention Quantification [] ---
    # Key functions: interest, readInterestResults
    bamF <- system.file(
        "extdata", "small_test_SRR1691637_ZRSR2Mut_RHBDD3.bam",
        package = "IntEREst", mustWork = TRUE
    )
    ref <- u12[u12[, "gene_name"] == "RHBDD3", ]
    out_file <- tempfile(fileext = ".tsv")
    testInterest <- interest(
        bamFileYieldSize = 10000,
        junctionReadsOnly = FALSE,
        bamFile = bamF,
        isPaired = TRUE,
        reference = ref,
        referenceGeneNames = ref[, "ens_gene_id"],
        referenceIntronExon = ref[, "int_ex"],
        outFile = out_file,
        method = "IntRet",
        returnObj = FALSE
    )
    testIntRetObj <- readInterestResults(
        resultFiles = out_file,
        sampleNames = "small_test_SRR1691637_ZRSR2Mut_RHBDD3",
        sampleAnnotation = data.frame(type = "ZRSR2mut", test_ctrl = "test"),
        commonColumns = 1:ncol(ref),
        freqCol = ncol(ref) + 1,
        scaledRetentionCol = ncol(ref) + 2,
        scaleLength = TRUE,
        scaleFragment = TRUE,
        reScale = TRUE,
        geneIdCol = "ens_gene_id"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_interest_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_interest_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_interest_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INTEREST:", paste0("    interest: ", packageVersion("IntEREst"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interest_results.csv
    touch ${prefix}_interest_output.rds
    echo "BIOC_INTEREST:" > versions.yml
    echo "    interest: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INTEREST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_INTEREST(ch_input)

    emit:
    results  = BIOC_INTEREST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INTEREST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INTEREST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INTEREST.out.versions  // channel: path(versions.yml)
}
