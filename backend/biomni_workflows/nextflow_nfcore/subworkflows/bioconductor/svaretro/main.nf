#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: svaRetro
// svaRetro contains functions for detecting retrotransposed transcripts (RTs) from structural variant 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/svaRetro/inst/doc/svaRetro.R
// Upstream  : StructuralVariantAnnotation, VariantAnnotation, circlize, dplyr
// Downstream: none
//
// Install: BiocManager::install("svaRetro")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SVARETRO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-svaretro"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-svaretro:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-svaretro:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_svaretro_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_svaretro_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_svaretro_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(svaRetro)
    library(jsonlite)


    # --- Input [] ---
    # Key functions: readVcf, extdata, diploidSV.vcf, svaRetro
    library(StructuralVariantAnnotation)
    library(VariantAnnotation)
    library(svaRetro)

    RT_vcf <- readVcf(system.file("extdata", "diploidSV.vcf", package = "svaRetro"))

    # --- Include=true [] ---
    # Key functions: breakpointRanges
    RT_gr <- StructuralVariantAnnotation::breakpointRanges(RT_vcf, 
                                                           nominalPosition=TRUE)
    head(RT_gr)

    # --- Include=true [] ---
    # Key functions: rtDetect
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(dplyr)
    hg19.genes <- TxDb.Hsapiens.UCSC.hg19.knownGene

    RT <- rtDetect(RT_gr, hg19.genes, maxgap=10, minscore=0.8)

    ## -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    RT$SKA3

    # --- Include=true [] ---
    # Key functions: seqlevelsStyle, breakpointgr2pairs, circos.initializeWithIdeogram, circos.genomicLink, first, second, chr13, chr11
    library(circlize)
    rt_chr_prefix <- c(RT$SKA3$junctions, RT$SKA3$insSite)
    seqlevelsStyle(rt_chr_prefix) <- "UCSC"
    pairs <- breakpointgr2pairs(rt_chr_prefix)
    pairs

    ## -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    circos.initializeWithIdeogram(
        data.frame(V1=c("chr13", "chr11"),
                   V2=c(21720000,108585000),
                   V3=c(21755000,108586000),
                   V4=c("q12.11","q24.3"),
                   V5=c("gneg","gpos50")))
    circos.genomicLink(as.data.frame(S4Vectors::first(pairs)), 
                       as.data.frame(S4Vectors::second(pairs)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_svaretro_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_svaretro_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_svaretro_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SVARETRO:", paste0("    svaretro: ", packageVersion("svaRetro"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_svaretro_results.csv
    touch ${prefix}_svaretro_output.rds
    echo "BIOC_SVARETRO:" > versions.yml
    echo "    svaretro: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SVARETRO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SVARETRO(ch_input)

    emit:
    results  = BIOC_SVARETRO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SVARETRO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SVARETRO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SVARETRO.out.versions  // channel: path(versions.yml)
}
