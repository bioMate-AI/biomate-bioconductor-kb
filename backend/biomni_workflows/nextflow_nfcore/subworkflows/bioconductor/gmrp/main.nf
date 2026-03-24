#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GMRP
// Perform Mendelian randomization analysis of multiple SNPs to determine risk factors causing disease 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GMRP/inst/doc/GMRP.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("GMRP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GMRP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gmrp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gmrp:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gmrp:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("${meta.id}_gmrp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gmrp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gmrp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DataFrame)
    library(jsonlite)

    # --- Fmerge [] ---
    # Key functions: runif, frame
    ## data1 <- matrix(NA, 20, 4)
    ## data2 <- matrix(NA, 30, 7)
    ## SNPID1 <- paste("rs", seq(1:20), sep="")
    ## SNPID2 <- paste("rs", seq(1:30), sep="")
    ## data1[,1:4] <- c(round(runif(20), 4), round(runif(20), 4), round(runif(20), 4), round(runif(20), 4))
    # --- Data [] ---
    # Key functions: DataFrame
    data(cad.data)
    #cad <- DataFrame(cad.data)
    cad<-cad.data
    head(cad)
    # --- Step1 [] ---
    # Key functions: cbind
    ## pvalue.LDL <- lpd$P.value.LDL
    ## pvalue.HDL <-lpd$P.value.HDL
    ## pvalue.TG <- lpd$P.value.TG
    ## pvalue.TC <- lpd$P.value.TC
    ## pv <- cbind(pvalue.LDL, pvalue.HDL, pvalue.TG, pvalue.TC)
    # --- Step2 [] ---
    # Key functions: cbind
    ## beta.LDL <- lpd$beta.LDL
    ## beta.HDL <- lpd$beta.HDL
    ## beta.TG <- lpd$beta.TG
    ## beta.TC <- lpd$beta.TC
    ## beta <- cbind(beta.LDL, beta.HDL, beta.TG, beta.TC)
    # --- Step3 [] ---
    # Key functions: cbind
    ## a1.LDL <- lpd$A1.LDL
    ## a1.HDL <- lpd$A1.HDL
    ## a1.TG <- lpd$A1.TG
    ## a1.TC <- lpd$A1.TC
    ## alle1 <- cbind(a1.LDL, a1.HDL, a1.TG, a1.TC)
    # --- Step4 [] ---
    # Key functions: cbind
    ## N.LDL <- lpd$N.LDL
    ## N.HDL <- lpd$N.HDL
    ## N.TG <- lpd$N.TG
    ## N.TC <- lpd$N.TC
    ## ss <- cbind(N.LDL, N.HDL, N.TG, N.TC)
    # --- Step5 [] ---
    # Key functions: cbind
    ## freq.LDL<-lpd$Freq.A1.1000G.EUR.LDL
    ## freq.HDL<-lpd$Freq.A1.1000G.EUR.HDL
    ## freq.TG<-lpd$Freq.A1.1000G.EUR.TG
    ## freq.TC<-lpd$Freq.A1.1000G.EUR.TC
    ## freq<-cbind(freq.LDL,freq.HDL,freq.TG,freq.TC)
    # --- Step6 [] ---
    # Key functions: rep, cbind
    ## sd.LDL <- rep(37.42, length(pvj))
    ## sd.HDL <- rep(14.87, length(pvj))
    ## sd.TG <-rep(92.73, length(pvj))
    ## sd.TC <- rep(42.74, length(pvj))
    ## sd <- cbind(sd.LDL, sd.HDL, sd.TG, sd.TC)
    # --- Step8 [] ---
    # Key functions: chrp
    ## chr<-chrp(hg=hg19)
    # --- Step9 [] ---
    # Key functions: frame
    ## newdata<-cbind(freq,beta,sd,pvj,ss,pcj)
    ## newdata<-cbind(chr,rsid,alle1,as.data.frame(newdata))
    ## dim(newdata)
    # --- Step11 [] ---
    # Key functions: frame
    ## newcad <- cbind(freq.d, beta.d, N.case, N.ctr, freq.case)
    ## newcad <- cbind(hg18.d, SNP.d, a1.d, as.data.frame(newcad))
    ## dim(newcad)
    # --- Step13 [] ---
    # Key functions: mktable, DataFrame
    ## mybeta <- mktable(cdata=newdata, ddata=newcad, rt="beta", varname=varname, LG=1, Pv=0.00000005, Pc=0.979, Pd=0.979)
    ## dim(mybeta)
    ## beta <- mybeta[,4:8]   #  standard beta table for path analysis
    ## snp <- mybeta[,1:3]   #  snp data for annotation analysis
    ## beta<-DataFrame(beta)
    # --- Data [] ---
    # Key functions: DataFrame
    data(beta.data)
    beta.data<-DataFrame(beta.data)
    CAD <- beta.data$cad
    LDL <- beta.data$ldl
    HDL <- beta.data$hdl
    # --- Twoscatterplot [] ---
    # Key functions: lm
    par(mfrow=c(2, 2), mar=c(5.1, 4.1, 4.1, 2.1), oma=c(0, 0, 0, 0))
    plot(LDL,CAD, pch=19, col="blue", xlab="beta of SNPs on LDL", ylab="beta of SNP on CAD", cex.lab=1.5, cex.axis=1.5, cex.main=2)
    abline(lm(CAD~LDL), col="red", lwd=2)
    plot(HDL, CAD, pch=19,col="blue", xlab="beta of SNPs on HDL", ylab="beta of SNP on CAD", cex.lab=1.5, cex.axis=1.5, cex.main=2)
    abline(lm(CAD~HDL), col="red", lwd=2)
    # --- Figtwoscatterplot [] ---
    # Key functions: lm
    par(mfrow=c(2, 2), mar=c(5.1, 4.1, 4.1, 2.1), oma=c(0, 0, 0, 0))
    plot(LDL,CAD, pch=19, col="blue", xlab="beta of SNPs on LDL", ylab="beta of SNP on CAD", cex.lab=1.5, cex.axis=1.5, cex.main=2)
    abline(lm(CAD~LDL), col="red", lwd=2)
    plot(HDL, CAD, pch=19,col="blue", xlab="beta of SNPs on HDL", ylab="beta of SNP on CAD", cex.lab=1.5, cex.axis=1.5, cex.main=2)
    abline(lm(CAD~HDL), col="red", lwd=2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gmrp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gmrp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gmrp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GMRP:", paste0("    gmrp: ", packageVersion("GMRP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gmrp_results.csv
    touch ${prefix}_gmrp_output.rds
    echo "BIOC_GMRP:" > versions.yml
    echo "    gmrp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GMRP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input_file) ]

    main:
    BIOC_GMRP(ch_input)

    emit:
    results  = BIOC_GMRP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GMRP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GMRP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GMRP.out.versions  // channel: path(versions.yml)
}
