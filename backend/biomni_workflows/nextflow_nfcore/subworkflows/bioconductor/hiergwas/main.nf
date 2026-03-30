#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: hierGWAS
// Testing individual SNPs, as well as arbitrarily large groups of SNPs in GWA studies, using a joint m
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/hierGWAS/inst/doc/hierGWAS.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("hierGWAS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HIERGWAS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hiergwas"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hiergwas:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hiergwas:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hiergwas_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hiergwas_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hiergwas_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(hierGWAS)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data, cbind
    library(hierGWAS)
    data(simGWAS)
    sim.geno <- data.matrix(simGWAS[,1:1000])
    sim.pheno <- simGWAS$y
    sim.covar <- cbind(simGWAS$sex,simGWAS$age)
    # --- Cluster Snps [] ---
    # Key functions: snp
    # cluster SNPs in chromosome 1
    SNPindex.chrom1 <- seq(1,500)
    dendr.chrom1 <- cluster.snp(sim.geno,SNP_index = SNPindex.chrom1)
    # cluster SNPs in chromosome 2
    SNPindex.chrom2 <- seq(501,1000)
    # --- Multi Split [] ---
    # Key functions: multisplit, show
    res.multisplit <- multisplit(sim.geno,sim.pheno,covar = sim.covar)
    # the matrix of selected coefficients for each sample split
    show(res.multisplit$sel.coeff[1:10,1:10])
    # the samples which will be used for testing
    show(res.multisplit$out.sample[1:10,1:10])
    # --- Hierarchical Testing [] ---
    # Key functions: hierarchy, show
    result.chrom1 <- test.hierarchy(sim.geno, sim.pheno, dendr.chrom1, res.multisplit,
                                    covar = sim.covar, SNP_index = SNPindex.chrom1)
    result.chrom2 <- test.hierarchy(sim.geno, sim.pheno, dendr.chrom1, res.multisplit,
                                    covar = sim.covar, SNP_index = SNPindex.chrom2,
                                    global.test = FALSE, verbose = FALSE)
    # --- R2 Computation [] ---
    # Key functions: r2, show
    SNP_index <- seq(991,1000)
    res.r2 <- compute.r2(sim.geno, sim.pheno, res.multisplit, covar = sim.covar, SNP_index = SNP_index)
    show(res.r2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hiergwas_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hiergwas_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hiergwas_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HIERGWAS:", paste0("    hiergwas: ", packageVersion("hierGWAS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hiergwas_results.csv
    touch ${prefix}_hiergwas_output.rds
    echo "BIOC_HIERGWAS:" > versions.yml
    echo "    hiergwas: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HIERGWAS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HIERGWAS(ch_input)

    emit:
    results  = BIOC_HIERGWAS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HIERGWAS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HIERGWAS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HIERGWAS.out.versions  // channel: path(versions.yml)
}
