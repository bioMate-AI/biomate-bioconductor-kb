#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: INPower — gwas_future_study_power_estimation
// Estimate the total number of susceptibility loci, effect size distribution, and predict power/discoveries for future GWAS under one-stage or two-stage designs.
// Input: data.rda
// Container: quay.io/biocontainers/bioconductor-inpower:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: INPower
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the GWAS discovery data containing MAFs, betas, and power
//  * 2. [Core Analysis] Extract MAFs, betas, and power vectors
//  * 3. [Core Analysis] Run INPower for a one-stage design with total genetic variance (tgv)
//  * 4. [Core Analysis] Run INPower for a one-stage design without tgv
//  * 5. [Core Analysis] Run INPower for a two-stage design by specifying multi.stage.option

nextflow.enable.dsl = 2

process BIOC_INPOWER_GWAS_FUTURE_STUDY_POWER_ESTIMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("INPower")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # 1. Load the GWAS discovery data containing MAFs, betas, and power
    library(INPower)
    
    # Load user-provided data.rda from the working directory
    load("data.rda")
    
    # 2. Extract MAFs, betas, and power vectors
    MAFs  <- data[, "MAF"]
    betas <- data[, "Beta"]
    pow   <- data[, "Power"] 
    
    # 3. Run INPower for a one-stage design with total genetic variance (tgv)
    res1 <- INPower(MAFs, betas, pow, span=0.5, binary.outcome=FALSE, 
                    sample.size=seq(25000,125000,by=25000), 
                    signif.lvl=10^(-7), tgv=0.8, k=seq(25,125,by=25))
    
    # 4. Run INPower for a one-stage design without tgv
    res2 <- INPower(MAFs, betas, pow, span=0.5, binary.outcome=FALSE, 
                    sample.size=seq(25000,125000,by=25000), 
                    signif.lvl=10^(-7), k=seq(25,125,by=25))
    
    # 5. Run INPower for a two-stage design by specifying multi.stage.option
    res3 <- INPower(MAFs, betas, pow, span=0.5, binary.outcome=FALSE,
                    sample.size=seq(25000,125000,by=25000), 
                    signif.lvl=10^(-7), multi.stage.option=list(al=5*10^(-5), pi=0.3),
                    tgv=0.8 , k=seq(25,125,by=25))
    
    # 6. Save results to output files
    saveRDS(res1, "inpower_onestage_tgv.rds")
    saveRDS(res2, "inpower_onestage_notgv.rds")
    saveRDS(res3, "inpower_twostage_tgv.rds")
    
    # Export key tables to CSV
    write.csv(res1\$esdist.summary\$es.dist, "onestage_tgv_es_dist.csv", row.names=FALSE)
    write.csv(res1\$future.study.summary\$e.discov, "onestage_tgv_e_discov.csv", row.names=FALSE)
    write.csv(res1\$future.study.summary\$prob.k, "onestage_tgv_prob_k.csv", row.names=FALSE)
    
    write.csv(res2\$esdist.summary\$es.dist, "onestage_notgv_es_dist.csv", row.names=FALSE)
    write.csv(res2\$future.study.summary\$e.discov, "onestage_notgv_e_discov.csv", row.names=FALSE)
    write.csv(res2\$future.study.summary\$prob.k, "onestage_notgv_prob_k.csv", row.names=FALSE)
    
    write.csv(res3\$esdist.summary\$es.dist, "twostage_tgv_es_dist.csv", row.names=FALSE)
    write.csv(res3\$future.study.summary\$e.discov, "twostage_tgv_e_discov.csv", row.names=FALSE)
    write.csv(res3\$future.study.summary\$prob.k, "twostage_tgv_prob_k.csv", row.names=FALSE)
    
    # Generate comparison plot
    pdf("expected_discoveries_comparison.pdf", width=7, height=5)
    plot(res1\$future.study.summary\$e.discov\$sample.size, res1\$future.study.summary\$e.discov\$e.discov, 
         type="b", col="blue", pch=19, ylim=c(0, max(res1\$future.study.summary\$e.discov\$e.discov) * 1.1),
         xlab="Sample Size", ylab="Expected Discoveries", 
         main="Expected Discoveries by Study Design")
    lines(res2\$future.study.summary\$e.discov\$sample.size, res2\$future.study.summary\$e.discov\$e.discov, 
          type="b", col="red", pch=18)
    lines(res3\$future.study.summary\$e.discov\$sample.size, res3\$future.study.summary\$e.discov\$e.discov, 
          type="b", col="green", pch=17)
    legend("bottomright", legend=c("One-stage (tgv=0.8)", "One-stage (no tgv)", "Two-stage (tgv=0.8)"), 
           col=c("blue", "red", "green"), pch=c(19, 18, 17), lty=1)
    dev.off()

    writeLines(c(
        '"BIOC_INPOWER_GWAS_FUTURE_STUDY_POWER_ESTIMATION":',
        paste0('    INPower: ', as.character(packageVersion('INPower')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gwas_future_study_power_estimation.csv versions.yml
    """
}

workflow BIOC_INPOWER_GWAS_FUTURE_STUDY_POWER_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data.rda ] ]

    main:
    BIOC_INPOWER_GWAS_FUTURE_STUDY_POWER_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_INPOWER_GWAS_FUTURE_STUDY_POWER_ESTIMATION.out.tables
    plots    = BIOC_INPOWER_GWAS_FUTURE_STUDY_POWER_ESTIMATION.out.plots
    objects  = BIOC_INPOWER_GWAS_FUTURE_STUDY_POWER_ESTIMATION.out.objects
    versions = BIOC_INPOWER_GWAS_FUTURE_STUDY_POWER_ESTIMATION.out.versions
}
