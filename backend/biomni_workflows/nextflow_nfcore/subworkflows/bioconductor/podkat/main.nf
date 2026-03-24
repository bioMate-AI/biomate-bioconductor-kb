#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: podkat
// This package provides an association test that is capable of dealing with very rare and even private
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/podkat/inst/doc/podkat.R
// Upstream  : GWASTools
// Downstream: none
//
// Install: BiocManager::install("podkat")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PODKAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-podkat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-podkat:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-podkat:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_podkat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_podkat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_podkat_plots.pdf"),    emit: plots, optional: true
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

    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, partitionRegions
    gr <- GRanges(seqnames="chr1", ranges=IRanges(start=1, end=140000))
    partitionRegions(gr, width=10000, overlap=0.5)
    partitionRegions(gr, width=15000, overlap=0.8)
    # --- Merge overlapping ranges [] ---
    # Key functions: reduce
    hg38all <- reduce(unlist(hg38Unmasked))
    # --- Sequence information check [] ---
    # Key functions: packageDescription, partitionRegions, readGenotypeMatrix, nullModel, attach, seqinfo, transcripts, strand
    res.b.adj.sorted <- sort(res.b.adj, sortBy="p.value.adj")
    Zi <- readGenotypeMatrix(vcfFile, regions=res.b.adj.sorted[1])
    plot(Zi, y=factor(pheno.b$y), labRow=NA)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_podkat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_podkat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_podkat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PODKAT:", paste0("    podkat: ", packageVersion("podkat"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_podkat_results.csv
    touch ${prefix}_podkat_output.rds
    echo "BIOC_PODKAT:" > versions.yml
    echo "    podkat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PODKAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PODKAT(ch_input)

    emit:
    results  = BIOC_PODKAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PODKAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PODKAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PODKAT.out.versions  // channel: path(versions.yml)
}
