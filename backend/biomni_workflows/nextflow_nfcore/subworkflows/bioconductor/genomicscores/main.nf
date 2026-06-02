#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicScores
// Provide infrastructure to store and access genomewide position-specific scores within R and Biocondu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicScores/inst/doc/GenomicScores.R
// Upstream  : RColorBrewer, VariantAnnotation, gwascat
// Downstream: AlphaMissense.v2023.hg19, AlphaMissense.v2023.hg38, cadd.v1.6.hg19, cadd.v1.6.hg38, fitCons.UCSC.hg19
//
// Install: BiocManager::install("GenomicScores")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICSCORES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicscores"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomicscores:2.18.1--r44_0' :
        'quay.io/biocontainers/bioconductor-genomicscores:2.18.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicscores_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicscores_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicscores_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(jsonlite)

    # --- available G Scores [] ---
    # Key functions: availableGScores
    library(GenomicScores)
    avgs <- availableGScores()
    # --- score [] ---
    # Key functions: score, populations, defaultPopulation
    ppsco <- score(phylop, gwcgr)
    plot(pcsco, ppsco, xlab="phastCons", ylab="phyloP",
    populations(phast)
    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, gscores
    par(mar=c(4, 5, 3, 1))
    barplot(xtab, horiz=TRUE, col=c("red", "royalblue", "gray"),
    par(xpd=TRUE)
    # --- split [] ---
    # Key functions: split, elementNROWS
    x <- split(loc$PHASTCONS, loc$LOCATION)
    mask <- elementNROWS(x) > 0
    boxplot(x[mask], ylab="phastCons score", las=1, cex.axis=1.2, cex.lab=1.5, col="gray")
    # --- color Ramp Palette [] ---
    # Key functions: colorRampPalette
    library(RColorBrewer)
    par(mar=c(4, 5, 1, 1))
    hmcol <- colorRampPalette(brewer.pal(nlevels(loc$LOCATION), "Set1"))(nlevels(loc$LOCATION))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomicscores_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomicscores_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomicscores_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICSCORES:", paste0("    genomicscores: ", packageVersion("GenomicScores"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicscores_results.csv
    touch ${prefix}_genomicscores_output.rds
    echo "BIOC_GENOMICSCORES:" > versions.yml
    echo "    genomicscores: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICSCORES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICSCORES(ch_input)

    emit:
    results  = BIOC_GENOMICSCORES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICSCORES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICSCORES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICSCORES.out.versions  // channel: path(versions.yml)
}
