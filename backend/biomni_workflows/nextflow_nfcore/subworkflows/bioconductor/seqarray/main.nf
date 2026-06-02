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
    library(SeqArray)
    library(CalcAlleleFreq)
    library(jsonlite)

    # --- Allele Frequency Calculation [] ---
    # Key functions: seqApply, seqNumAllele, seqAlleleFreq, seqParallelSetup
    seqParallelSetup(2)
    af <- seqApply(file, "genotype", as.is="double",
        margin="by.variant",
        FUN=function(x) { mean(x==0L, na.rm=TRUE) })
    num_alleles <- seqNumAllele(file)
    ref_af <- seqAlleleFreq(file, ref.allele=0L)
    seqParallelSetup(FALSE)


    # --- Genomic Region Filtering and VCF Export [] ---
    # Key functions: seqSetFilterChrom, seqAsVCF
    seqSetFilterChrom(file, 22, from.bp=10000000, to.bp=30000000)
    vcf_data <- seqAsVCF(file, chr.prefix="chr")


    # --- Dosage Matrix Block Processing [] ---
    # Key functions: seqBlockApply
    s <- 0
    seqBlockApply(file, "$dosage", function(x) {
        p <- 0.5 * colMeans(x, na.rm=TRUE)
        g <- (t(x) - 2*p) / sqrt(p*(1-p))
        g[is.na(g)] <- 0
        s <<- s + crossprod(g)
    }, margin="by.variant")
    s_scaled <- s * (nrow(s) / sum(diag(s)))
    eig <- eigen(s_scaled, symmetric=TRUE)


    # --- Sample Annotation and Data Extraction [] ---
    # Key functions: seqGetData
    sample_ids <- seqGetData(file, "sample.id")
    pop_code <- factor(seqGetData(file, "sample.annotation/Population"))
    ceu_samples <- sample_ids[pop_code == "CEU"]

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
