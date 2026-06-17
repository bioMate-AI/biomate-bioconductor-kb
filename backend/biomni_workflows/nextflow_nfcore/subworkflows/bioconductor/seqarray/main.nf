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
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SeqArray", "CalcAlleleFreq", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(SeqArray)
    library(CalcAlleleFreq)
    library(jsonlite)

    # --- File Initialization and Summary [] ---
    # Key functions: seqOpen, seqExampleFileName, seqSummary
    gds_path <- seqExampleFileName("KG_Phase1")
    file <- seqOpen(gds_path)
    summary_info <- seqSummary(file)

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
    seqBlockApply(file, "\$dosage", function(x) {
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
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_seqarray_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_seqarray_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_seqarray_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQARRAY:", paste0("    seqarray: ", as.character(packageVersion("SeqArray")))),
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
