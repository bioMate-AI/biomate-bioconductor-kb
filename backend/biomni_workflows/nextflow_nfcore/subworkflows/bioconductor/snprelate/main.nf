#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SNPRelate
// Genome-wide association studies (GWAS) are widely used to investigate the genetic basis of diseases 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SNPRelate/inst/doc/SNPRelate.R
// Upstream  : MASS
// Downstream: RAIDS, SeqSQC
//
// Install: BiocManager::install("SNPRelate")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNPRELATE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-snprelate"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-snprelate:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-snprelate:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_snprelate_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_snprelate_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_snprelate_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SNPRelate)
    library(SNPs)
    library(jsonlite)

    # --- Data Conversion and Import ---
    # Key functions: snpgdsBED2GDS, snpgdsSummary
    bed.fn <- system.file("extdata", "plinkhapmap.bed.gz", package="SNPRelate")
    fam.fn <- system.file("extdata", "plinkhapmap.fam.gz", package="SNPRelate")
    bim.fn <- system.file("extdata", "plinkhapmap.bim.gz", package="SNPRelate")
    snpgdsBED2GDS(bed.fn, fam.fn, bim.fn, "test.gds", verbose=FALSE)
    gds_summary <- snpgdsSummary("test.gds")

    # --- Linkage Disequilibrium Pruning ---
    # Key functions: snpgdsOpen, snpgdsLDpruning, snpgdsClose
    genofile <- snpgdsOpen(snpgdsExampleFileName())
    snpset <- snpgdsLDpruning(genofile,
                              ld.threshold=0.2,
                              missing.rate=0.05,
                              maf=0.05,
                              verbose=FALSE)
    pruned_snps <- unlist(unname(snpset))
    saveRDS(pruned_snps, file="pruned_snps.rds")
    snpgdsClose(genofile)

    # --- Principal Component Analysis ---
    # Key functions: snpgdsOpen, snpgdsPCA, snpgdsClose
    genofile <- snpgdsOpen(snpgdsExampleFileName())
    pca <- snpgdsPCA(genofile, num.thread=1, verbose=FALSE)
    pca_df <- data.frame(sample.id = pca$sample.id,
                         EV1 = pca$eigenvect[,1],
                         EV2 = pca$eigenvect[,2],
                         stringsAsFactors = FALSE)
    saveRDS(pca_df, file="pca_results.rds")
    snpgdsClose(genofile)

    # --- Identity-By-Descent Analysis ---
    # Key functions: snpgdsOpen, snpgdsIBDMoM, snpgdsIBDSelection, snpgdsClose
    genofile <- snpgdsOpen(snpgdsExampleFileName())
    ibd <- snpgdsIBDMoM(genofile, num.thread=1, verbose=FALSE)
    ibd_coeff <- snpgdsIBDSelection(ibd)
    saveRDS(ibd_coeff, file="ibd_coefficients.rds")
    snpgdsClose(genofile)

    # --- Population Stratification and Fst Estimation ---
    # Key functions: snpgdsOpen, snpgdsFst, snpgdsClose
    genofile <- snpgdsOpen(snpgdsExampleFileName())
    pop_code <- read.gdsn(index.gdsn(genofile, "sample.annot/pop.group"))
    fst_results <- snpgdsFst(genofile,
                             population=as.factor(pop_code),
                             verbose=FALSE)
    saveRDS(fst_results, file="fst_results.rds")
    snpgdsClose(genofile)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_snprelate_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_snprelate_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_snprelate_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SNPRELATE:", paste0("    snprelate: ", packageVersion("SNPRelate"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snprelate_results.csv
    touch ${prefix}_snprelate_output.rds
    echo "BIOC_SNPRELATE:" > versions.yml
    echo "    snprelate: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SNPRELATE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SNPRELATE(ch_input)

    emit:
    results  = BIOC_SNPRELATE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SNPRELATE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SNPRELATE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SNPRELATE.out.versions  // channel: path(versions.yml)
}
