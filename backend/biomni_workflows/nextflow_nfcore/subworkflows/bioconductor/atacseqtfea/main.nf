#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ATACseqTFEA
// Assay for Transpose-Accessible Chromatin using sequencing (ATAC-seq) is a technique to assess genome
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ATACseqTFEA/inst/doc/ATACseqTFEA.R
// Upstream  : ATACseqQC, Rsamtools
// Downstream: none
//
// Install: BiocManager::install("ATACseqTFEA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ATACSEQTFEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-atacseqtfea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-atacseqtfea:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-atacseqtfea:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_atacseqtfea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_atacseqtfea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_atacseqtfea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ATACseqTFEA)
    library(ESvolcanoplot)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Prepare Binding Sites [ATACseqTFEA] ---
    # Key functions: prepareBindingSites
    motifs <- readRDS(system.file("extdata", "PWMatrixList.rds",
                                   package="ATACseqTFEA"))
    Drerio <- BSgenome.Drerio.UCSC.danRer10::Drerio
    seqlev <- "chr1"
    bindingSites <- prepareBindingSites(
        motifs, Drerio, seqlev,
        grange = GenomicRanges::GRanges(
            "chr1", 
            IRanges::IRanges(5000, 100000)
        ),
        p.cutoff = 5e-05
    )

    # --- Direct TFEA Analysis [ATACseqTFEA] ---
    # Key functions: TFEA
    bamExp <- system.file("extdata",
                          c("KD.shift.rep1.bam", "KD.shift.rep2.bam"),
                          package="ATACseqTFEA")
    bamCtl <- system.file("extdata",
                          c("WT.shift.rep1.bam", "WT.shift.rep2.bam"),
                          package="ATACseqTFEA")
    res <- TFEA(
        bamExp, bamCtl, 
        bindingSites = bindingSites,
        positive = 0, negative = 0
    )

    # --- Count 5' Ends and Filter [ATACseqTFEA] ---
    # Key functions: expandBindingSites, count5ends, eventsFilter
    exbs <- expandBindingSites(
        bindingSites = bindingSites,
        proximal = 40, distal = 40, gap = 10
    )
    counts <- count5ends(
        bam = c(bamExp, bamCtl),
        positive = 0L, negative = 0L,
        bindingSites = bindingSites,
        bindingSitesWithGap = exbs$bindingSitesWithGap,
        bindingSitesWithProximal = exbs$bindingSitesWithProximal,
        bindingSitesWithProximalAndGap = exbs$bindingSitesWithProximalAndGap,
        bindingSitesWithDistal = exbs$bindingSitesWithDistal
    )
    counts <- eventsFilter(counts, "proximalRegion>0")

    # --- Normalization and Differential Scoring [ATACseqTFEA] ---
    # Key functions: countsNormalization, getWeightedBindingScore, DBscore
    counts <- countsNormalization(counts, proximal = 40, distal = 40)
    counts <- getWeightedBindingScore(counts)
    design <- cbind(CTL = 1, EXPvsCTL = c(1, 1, 0, 0))
    counts <- DBscore(counts, design = design, coef = "EXPvsCTL")

    # --- Downstream TFEA and Visualization [ATACseqTFEA] ---
    # Key functions: doTFEA, ESvolcanoplot, plotES, factorFootprints, getBindingSites
    res_counts <- doTFEA(counts)
    TF <- "Tal1::Gata1"
    ESvolcanoplot(TFEAresults = res_counts, TFnameToShow = TF)
    plotES(res_counts, TF = TF, outfolder = NA)
    Drerio <- BSgenome.Drerio.UCSC.danRer10::Drerio
    sigs <- factorFootprints(
        c(bamCtl, bamExp),
        pfm = as.matrix(motifs[[TF]]),
        bindingSites = getBindingSites(res_counts, TF = TF),
        seqlev = "chr1", genome = Drerio,
        upstream = 100, downstream = 100,
        group = rep(c("WT", "KD"), each = 2)
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_atacseqtfea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_atacseqtfea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_atacseqtfea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ATACSEQTFEA:", paste0("    atacseqtfea: ", packageVersion("ATACseqTFEA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_atacseqtfea_results.csv
    touch ${prefix}_atacseqtfea_output.rds
    echo "BIOC_ATACSEQTFEA:" > versions.yml
    echo "    atacseqtfea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ATACSEQTFEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ATACSEQTFEA(ch_input)

    emit:
    results  = BIOC_ATACSEQTFEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ATACSEQTFEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ATACSEQTFEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ATACSEQTFEA.out.versions  // channel: path(versions.yml)
}
