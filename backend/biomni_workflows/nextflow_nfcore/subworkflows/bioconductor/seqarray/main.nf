#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SeqArray
// Data management of large-scale whole-genome sequencing variant calls with thousands of individuals: 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SeqArray/inst/doc/SeqArray.R
// Upstream  : Biobase, Rcpp, SNPRelate, VariantAnnotation, parallel
// Downstream: GBScleanR, SAIGEgds, SeqVarTools
//
// Install: BiocManager::install("SeqArray")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQARRAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seqarray"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seqarray:1.46.3--r44_0' :
        'quay.io/biocontainers/bioconductor-seqarray:1.46.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seqarray_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seqarray_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seqarray_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CalcAlleleFreq)
    library(jsonlite)

    # --- Package [] ---
    # Key functions: package, seqOpen, seqExampleFileName, seqSummary
    ---------------------------------------------------------------------------------------------------
    library(SeqArray)
    # open a SeqArray file in the package (1000 Genomes Phase1, chromosome 22)
    file <- seqOpen(seqExampleFileName("KG_Phase1"))
    seqSummary(file)
    # --- Seqapply [] ---
    # Key functions: seqApply
    ---------------------------------------------------------------------------------------------------
    af <- seqApply(file, "genotype", as.is="double", margin="by.variant",
        FUN=function(x) { mean(x==0L, na.rm=TRUE) })
    head(af)
    # --- Cppfunction [] ---
    # Key functions: cppFunction, CalcAlleleFreq, size, double
    ---------------------------------------------------------------------------------------------------
    library(Rcpp)
    # --- Seqapply [] ---
    # Key functions: seqApply
    ---------------------------------------------------------------------------------------------------
    af <- seqApply(file, "genotype", as.is="double", margin="by.variant", FUN=CalcAlleleFreq)
    head(af)
    # --- Seqblockapply [] ---
    # Key functions: seqBlockApply, colMeans, frequencies, na, crossprod
    ---------------------------------------------------------------------------------------------------
    # covariance variable with an initial value
    s <- 0
    # --- Seqparallelsetup [] ---
    # Key functions: seqParallelSetup, seqNumAllele, seqAlleleFreq
    ---------------------------------------------------------------------------------------------------
    # use 2 cores for demonstration
    seqParallelSetup(2)
    # numbers of distinct alleles per site
    table(seqNumAllele(file))
    # --- Seqsetfilterchrom [] ---
    # Key functions: seqSetFilterChrom, seqAsVCF
    ---------------------------------------------------------------------------------------------------
    # select a region [10Mb, 30Mb] on chromosome 22
    seqSetFilterChrom(file, 22, from.bp=10000000, to.bp=30000000)
    vcf <- seqAsVCF(file, chr.prefix="chr")
    vcf
    # --- Data [] ---
    # Key functions: pData
    ---------------------------------------------------------------------------------------------------
    data(KG_P1_SampData)
    KG_P1_SampData
    head(pData(KG_P1_SampData))  # show KG_P1_SampData
    # --- Snpgdspca [] ---
    # Key functions: snpgdsPCA, proportion
    ---------------------------------------------------------------------------------------------------
    # Run PCA
    pca <- snpgdsPCA(file, snp.id=snpset.id, num.thread=2)
    # variance proportion (%)
    pc.percent <- pca$varprop*100
    # --- Factor [] ---
    # Key functions: factor, seqGetData, levels
    ---------------------------------------------------------------------------------------------------
    pop.code <- factor(seqGetData(file, "sample.annotation/Population"))
    head(pop.code)
    # --- Seqgetdata [] ---
    # Key functions: seqGetData
    ---------------------------------------------------------------------------------------------------
    # YRI samples
    sample.id <- seqGetData(file, "sample.id")
    CEU.id <- sample.id[pop.code == "CEU"]
    # --- Seqclose [] ---
    # Key functions: seqClose
    ---------------------------------------------------------------------------------------------------
    seqClose(file)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seqarray_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seqarray_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seqarray_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQARRAY:", paste0("    seqarray: ", packageVersion("SeqArray"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seqarray_results.csv
    touch ${prefix}_seqarray_output.rds
    echo "BIOC_SEQARRAY:" > versions.yml
    echo "    seqarray: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQARRAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQARRAY(ch_input)

    emit:
    results  = BIOC_SEQARRAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQARRAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQARRAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQARRAY.out.versions  // channel: path(versions.yml)
}
