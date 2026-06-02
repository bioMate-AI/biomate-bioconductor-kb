#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VCFArray
// VCFArray extends the DelayedArray to represent VCF data entries as array-like objects with on-disk /
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VCFArray/inst/doc/VCFArray.R
// Upstream  : VariantAnnotation
// Downstream: none
//
// Install: BiocManager::install("VCFArray")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VCFARRAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-vcfarray"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-vcfarray:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-vcfarray:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_vcfarray_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_vcfarray_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_vcfarray_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(VCFArray)
    library(jsonlite)


    # --- Avail [] ---
    # Key functions: args, vcfFields, extdata, chr22.vcf.gz, VCFArray
    args(VCFArray)
    fl <- system.file("extdata", "chr22.vcf.gz", package = "VariantAnnotation")
    library(VariantAnnotation)
    vcfFields(fl)
    VCFArray(file = fl, name = "GT")

    # --- Constructor2 [] ---
    # Key functions: VcfFile, VCFArray, dir, basename, readRDS, VcfStack, seqinfo, RangedVcfStack
    vcf <- VariantAnnotation::VcfFile(fl)
    VCFArray(file = vcf, name = "DS")
    extdata <- system.file(package = "GenomicFiles", "extdata")
    files <- dir(extdata, pattern="^CEUtrio.*bgz$", full=TRUE)[1:2]
    names(files) <- sub(".*_([0-9XY]+).*", "\\1", basename(files))
    seqinfo <- as(readRDS(file.path(extdata, "seqinfo.rds")), "Seqinfo")
    stack <- GenomicFiles::VcfStack(files, seqinfo)
    gr <- as(GenomicFiles::seqinfo(stack)[rownames(stack)], "GRanges")
    ## RangedVcfStack
    rgstack <- GenomicFiles::RangedVcfStack(stack, rowRanges = gr)  
    rgstack

    # --- Constructor3 [] ---
    # Key functions: vcfFields, VCFArray, seed
    vcfFields(rgstack)$geno
    VCFArray(rgstack, name = "SB")
    va <- VCFArray(fl, name = "GT")
    seed(va)

    # --- Vcffile Accessor [] ---
    # Key functions: vcffile, VCFArray, class, dimnames, lengths
    vcffile(va)
    va <- VCFArray(fl, name = "GT")
    dim(va)
    class(dimnames(va))
    lengths(dimnames(va))

    # --- Subsetting [] ---
    # Key functions: VCFArray
    va[1:3, 1:3]
    va[c(TRUE, FALSE), ]
    ds <- VCFArray(fl, name = "DS")
    log(ds+5)

    # --- Vcfarray Seed [] ---
    # Key functions: VCFArraySeed, path, vcffile, VCFArray, DelayedArray, class, all.equal, sessionInfo
    seed <- VCFArray:::VCFArraySeed(fl, name = "GT", pfix = NULL)
    seed
    path(vcffile(seed))

    ## ----VCFArray-from-VCFArraySeed-----------------------------------------------
    (va <- VCFArray(seed))
    da <- DelayedArray(seed)
    class(da)
    all.equal(da, va)

    ## -----------------------------------------------------------------------------
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_vcfarray_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_vcfarray_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_vcfarray_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VCFARRAY:", paste0("    vcfarray: ", packageVersion("VCFArray"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vcfarray_results.csv
    touch ${prefix}_vcfarray_output.rds
    echo "BIOC_VCFARRAY:" > versions.yml
    echo "    vcfarray: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VCFARRAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VCFARRAY(ch_input)

    emit:
    results  = BIOC_VCFARRAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VCFARRAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VCFARRAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VCFARRAY.out.versions  // channel: path(versions.yml)
}
