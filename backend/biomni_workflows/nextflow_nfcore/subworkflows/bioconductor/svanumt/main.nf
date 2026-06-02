#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: svaNUMT
// svaNUMT contains functions for detecting NUMT events from structural variant calls. It takes structu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/svaNUMT/inst/doc/svaNUMT.R
// Upstream  : StructuralVariantAnnotation, VariantAnnotation, circlize, readr
// Downstream: none
//
// Install: BiocManager::install("svaNUMT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SVANUMT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-svanumt"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-svanumt:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-svanumt:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_svanumt_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_svanumt_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_svanumt_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(svaNUMT)
    library(jsonlite)


    # --- Input [] ---
    # Key functions: readVcf, breakpointRanges, extdata, chr1_numt_pe_HS25.sv.vcf, svaNUMT
    library(StructuralVariantAnnotation)
    library(VariantAnnotation)
    library(svaNUMT)

    vcf <- readVcf(system.file("extdata", "chr1_numt_pe_HS25.sv.vcf", package = "svaNUMT"))
    gr <- breakpointRanges(vcf)

    # --- Include=true [] ---
    # Key functions: read_table, GRanges, numtDetect, GRangesList, extdata, numtS.txt, svaNUMT, bin
    library(readr)
    numtS <- read_table(system.file("extdata", "numtS.txt", package = "svaNUMT"), 
        col_names = FALSE)
    colnames(numtS) <- c("bin", "seqnames", "start", "end", "name", "score", "strand")
    numtS <- `seqlevelsStyle<-`(GRanges(numtS), "NCBI")

    library(BSgenome.Hsapiens.UCSC.hg19)
    genome <- BSgenome.Hsapiens.UCSC.hg19
    genomeMT <- genome$chrMT

    ## -----------------------------------------------------------------------------
    NUMT <- numtDetect(gr, numtS, genomeMT, max_ins_dist = 20)

    ## -----------------------------------------------------------------------------
    GRangesList(NU=NUMT$MT$NU$`1`[[1]], MT=NUMT$MT$MT$`1`[[1]])

    # --- Include=true [] ---
    # Key functions: seqlevelsStyle, breakpointgr2pairs, circos.initializeWithIdeogram, circos.genomicLink, first, chr1, chrM, p15.4
    library(circlize)
    numt_chr_prefix <- c(NUMT$MT$NU$`1`[[2]], NUMT$MT$MT$`1`[[2]])
    GenomeInfoDb::seqlevelsStyle(numt_chr_prefix) <- "UCSC"
    pairs <- breakpointgr2pairs(numt_chr_prefix)
    pairs

    ## -----------------------------------------------------------------------------
    circos.initializeWithIdeogram(
        data.frame(V1=c("chr1", "chrM"),
                   V2=c(1791073,1),
                   V3=c(1791093,16571),
                   V4=c("p15.4",NA),
                   V5=c("gpos50",NA)),  sector.width = c(0.2, 0.8))
    #circos.initializeWithIdeogram()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_svanumt_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_svanumt_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_svanumt_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SVANUMT:", paste0("    svanumt: ", packageVersion("svaNUMT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_svanumt_results.csv
    touch ${prefix}_svanumt_output.rds
    echo "BIOC_SVANUMT:" > versions.yml
    echo "    svanumt: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SVANUMT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SVANUMT(ch_input)

    emit:
    results  = BIOC_SVANUMT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SVANUMT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SVANUMT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SVANUMT.out.versions  // channel: path(versions.yml)
}
