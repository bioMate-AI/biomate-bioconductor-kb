#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GEWIST
// This 'GEWIST' package provides statistical tools to efficiently optimize SNP prioritization for gene
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GEWIST/inst/doc/GEWIST.R
// Upstream  : car
// Downstream: none
//
// Install: BiocManager::install("GEWIST")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEWIST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gewist"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gewist:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gewist:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gewist_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gewist_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gewist_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GEWIST)
    library(jsonlite)

    # --- Gewist.Rnw:62 68 [] ---
    # Key functions: gewistLevene
    library(GEWIST)
    optim_result <- gewistLevene(p=0.2, N=10000, theta_gc=0.002,
     theta_c=0.15, M = 250000, K = 20000, verbose = FALSE)
    class(optim_result)
    print(optim_result)
    # --- Gewist.Rnw:86 88 [] ---
    # Key functions: gewistLevene
    optim_ver <- gewistLevene(p=0.2, N=10000, theta_gc=0.002,
    theta_c=0.2, M = 250000, K = 20000, verbose = TRUE)
    # --- Gewist.Rnw:122 126 [] ---
    # Key functions: effectPDF
    weibull_exp1 <- effectPDF(distribution = "weibull", parameter1 = 0.8, parameter2 = 0.3,
    parameter3 = NULL, p = 0.1 ,N = 10000, theta_c = 0.1, M = 350000, K = 10000, nb_incr = 50, range = c(0.025/100,0.3/100), verbose = FALSE)
    print(weibull_exp1)
    # --- Gewist.Rnw:142 146 [] ---
    # Key functions: effectPDF
    weibull_exp2 <- effectPDF(distribution = "weibull", parameter1 = 0.8, parameter2 = 0.3,
    parameter3 = NULL, p = 0.1 ,N = 10000, theta_c = 0.1, M = 350000,
    K = 10000, nb_incr = 50, range = c(0.025/100,0.3/100), verbose = T)
    # --- Gewist.Rnw:163 209 [] ---
    # Key functions: sample, frame
    ##### simulating SNPs
    # number of SNPs
    	nb_SNPs <- 100
    	MAF <- round(sample(seq(0.05,0.5,length.out= nb_SNPs)),2)
     	SNPset <- data.frame(SNPname = paste("SNP", seq(1: nb_SNPs)), MAF)
    # --- Gewist.Rnw:228 240 [] ---
    # Key functions: leveneTest, factor
    n  <- dim(GenoSet)[1]
    m <- dim(GenoSet)[2]
    library(car)
    levene_pval <- NA
    # --- Gewist.Rnw:252 262 [] ---
    # Key functions: gewistLevene
    optimal_pval <- NA
    for ( i in 1: m){
    optimal_pval[i] <- gewistLevene(p = SNPset[i,2], N = n, theta_gc = theta_gc,
    theta_c = theta_c, M = m )$Optimal_pval
    			    }
    # --- Gewist.Rnw:276 288 [] ---
    # Key functions: lm
    SNPind <- which(levene_pval < optimal_pval)
     Reduced <- GenoSet[,SNPind]
     intPval <- NA

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gewist_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gewist_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gewist_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GEWIST:", paste0("    gewist: ", packageVersion("GEWIST"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gewist_results.csv
    touch ${prefix}_gewist_output.rds
    echo "BIOC_GEWIST:" > versions.yml
    echo "    gewist: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GEWIST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GEWIST(ch_input)

    emit:
    results  = BIOC_GEWIST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GEWIST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GEWIST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GEWIST.out.versions  // channel: path(versions.yml)
}
