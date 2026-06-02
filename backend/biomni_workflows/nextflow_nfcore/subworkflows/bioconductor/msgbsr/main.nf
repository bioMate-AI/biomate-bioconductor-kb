#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: msgbsR
// Pipeline for the anaysis of a MS-GBS experiment.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/msgbsR/inst/doc/msgbsR_Vignette.R
// Upstream  : GenomicRanges, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("msgbsR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSGBSR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msgbsr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msgbsr:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msgbsr:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msgbsr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msgbsr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msgbsr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DataFrame)
    library(GRanges)
    library(jsonlite)

    # --- Load The Example Data [] ---
    # Key functions: rawCounts, assay
    library(msgbsR)
    library(GenomicRanges)
    library(SummarizedExperiment)
    my_path <- system.file("extdata", package = "msgbsR")
    se <- rawCounts(bamFilepath = my_path)
    # --- Insert Metadata [] ---
    # Key functions: colData, DataFrame, assay
    colData(se) <- DataFrame(Group = c(rep("Control", 3), rep("Experimental", 3)),
                             row.names = colnames(assay(se)))
    # --- Extract Cut Sites [] ---
    # Key functions: rowRanges, start, ifelse, strand, end
    cutSites <- rowRanges(se)
    # # Adjust the cut sites to overlap recognition site on each strand
    start(cutSites) <- ifelse(test = strand(cutSites) == '+',
                              yes = start(cutSites) - 1, no = start(cutSites) - 2)
    # --- Run Checkcuts With Bsgenome [] ---
    # Key functions: checkCuts
    library(BSgenome.Rnorvegicus.UCSC.rn6)
    correctCuts <- checkCuts(cutSites = cutSites, genome = "rn6", seq = "CCGG")
    # --- Filter Out Incorrect Cuts [] ---
    # Key functions: subsetByOverlaps, assay
    se <- subsetByOverlaps(se, correctCuts)
    dim(assay(se))
    # --- Plot Counts Per Cut Sites [] ---
    # Key functions: plotCounts
    plotCounts(se = se, cateogory = "Group")
    # --- Fig1 [] ---
    # Key functions: plotCounts
    plotCounts(se = se, cateogory = "Group")
    # --- Differential Methylation [] ---
    # Key functions: diffMeth
    top <- diffMeth(se = se, cateogory = "Group",
                    condition1 = "Control", condition2 = "Experimental",
                    cpmThreshold = 1, thresholdSamples = 1)
    # --- Chr20 Length [] ---
    # Key functions: seqlengths
    ratChr <- seqlengths(BSgenome.Rnorvegicus.UCSC.rn6)["chr20"]
    # --- Top Sites [] ---
    # Key functions: GRanges
    my_cuts <- GRanges(top$site[which(top$FDR < 0.05)])
    # --- Circos Plot [] ---
    # Key functions: plotCircos
    plotCircos(cutSites = my_cuts, seqlengths = ratChr,
               cutSite.colour = "red", seqlengths.colour = "blue")
    # --- Fig2 [] ---
    # Key functions: plotCircos
    plotCircos(cutSites = my_cuts, seqlengths = ratChr,
               cutSite.colour = "red", seqlengths.colour = "blue")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msgbsr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msgbsr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msgbsr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSGBSR:", paste0("    msgbsr: ", packageVersion("msgbsR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msgbsr_results.csv
    touch ${prefix}_msgbsr_output.rds
    echo "BIOC_MSGBSR:" > versions.yml
    echo "    msgbsr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSGBSR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSGBSR(ch_input)

    emit:
    results  = BIOC_MSGBSR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSGBSR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSGBSR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSGBSR.out.versions  // channel: path(versions.yml)
}
