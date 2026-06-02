#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DMRcate
// De novo identification and extraction of differentially methylated regions (DMRs) from the human gen
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DMRcate/inst/doc/EPICv1_and_450K.R
// Upstream  : BiocManager, ExperimentHub
// Downstream: methylationArrayAnalysis
//
// Install: BiocManager::install("DMRcate")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DMRCATE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dmrcate"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dmrcate:3.2.1--r44_0' :
        'quay.io/biocontainers/bioconductor-dmrcate:3.2.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dmrcate_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dmrcate_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dmrcate_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DMRcate)
    library(ExperimentHub)
    library(jsonlite)

    # --- Probe Filtering and Normalisation [] ---
    # Key functions: rmSNPandCH, ilogit2
    tcellms.noSNPs <- rmSNPandCH(tcellms, dist=2, mafcut=0.05)
    tcell$Replicate[tcell$Replicate==""] <- tcell$Sample_Name[tcell$Replicate==""]
    tcellms.noSNPs <- limma::avearrays(tcellms.noSNPs, tcell$Replicate)
    tcell <- tcell[,!duplicated(tcell$Replicate)]
    tcell <- tcell[rownames(tcellms.noSNPs),]
    colnames(tcellms.noSNPs) <- colnames(tcell)
    assays(tcell)[["M"]] <- tcellms.noSNPs
    assays(tcell)[["Beta"]] <- ilogit2(tcellms.noSNPs)


    # --- CpG Annotation and DMR Detection [] ---
    # Key functions: cpg.annotate, dmrcate, extractRanges
    type <- factor(tcell$CellType)
    design <- model.matrix(~type) 
    myannotation <- cpg.annotate("array", tcell, arraytype = "EPICv1",
                                 analysis.type="differential", design=design, coef=2)
    dmrcoutput <- dmrcate(myannotation, lambda=1000, C=2)
    results.ranges <- extractRanges(dmrcoutput, genome = "hg19")


    # --- Visualisation of Genomic Regions [] ---
    # Key functions: DMR.plot
    groups <- c(CD8T="magenta", CD4T="forestgreen")
    cols <- groups[as.character(type)]
    DMR.plot(ranges=results.ranges, dmr=1, CpGs=myannotation, what="Beta", 
             arraytype = "EPICv1", phen.col=cols, genome="hg19")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dmrcate_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dmrcate_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dmrcate_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DMRCATE:", paste0("    dmrcate: ", packageVersion("DMRcate"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dmrcate_results.csv
    touch ${prefix}_dmrcate_output.rds
    echo "BIOC_DMRCATE:" > versions.yml
    echo "    dmrcate: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DMRCATE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DMRCATE(ch_input)

    emit:
    results  = BIOC_DMRCATE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DMRCATE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DMRCATE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DMRCATE.out.versions  // channel: path(versions.yml)
}
