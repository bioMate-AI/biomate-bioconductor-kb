#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ramwas
// A complete toolset for methylome-wide association studies (MWAS). It is specifically designed for da
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ramwas/inst/doc/RW1_intro.R
// Upstream  : knitr, pander
// Downstream: none
//
// Install: BiocManager::install("ramwas")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAMWAS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ramwas"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ramwas:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ramwas:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ramwas_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ramwas_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ramwas_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ramwas)
    library(jsonlite)


    # --- Load Knitr [] ---
    # Key functions: set, panderOptions, digits, suppressPackageStartupMessages, tempdir, ramwas0createArtificialData
    library("knitr")
    # opts_chunk$set(eval = FALSE)
    opts_chunk$set(fig.width = 6, fig.height = 6)
    library(pander)
    panderOptions("digits", 3)
    suppressPackageStartupMessages(library(ramwas))
    # dr = "D:/temp"
    library(ramwas)
    dr = paste0(tempdir(), "/simulated_project")
    ramwas0createArtificialData(
                dir = dr,
                nsamples = 20,
                nreads = 100e3,
                ncpgs = 25e3,
                threads = 2)
    cat("Project directory:", dr)

    # --- Parameters [] ---
    # Key functions: ramwasParameters, ramwas1scanBams, bams, bam_list.txt, Simulated_chromosome.rds, covariates.txt, age, grch37.ensembl.org

    # --- Plot Fsd [] ---
    # Key functions: readRDS, as.double, readLines, plotFragmentSizeDistributionEstimate, ramwas3normalizedCoverage, ramwas4PCA
    qc = readRDS(paste0(pfull$dirqc, "/summary_total/qclist.rds"))
    frdata = qc$total$hist.isolated.dist1
    estimate = as.double(readLines(
        con = paste0(pfull$dirproject,"/Fragment_size_distribution.txt")))
    plotFragmentSizeDistributionEstimate(frdata, estimate)
    ramwas3normalizedCoverage(param)
    ramwas4PCA(param)

    # --- Plot PCA [] ---
    # Key functions: fm.load, fm.open, plotPCvalues, plotPCvectors, close, read.table, pander
    eigenvalues = fm.load(paste0(pfull$dirpca, "/eigenvalues"));
    eigenvectors = fm.open(
                    filenamebase = paste0(pfull$dirpca, "/eigenvectors"),
                    readonly = TRUE);
    plotPCvalues(eigenvalues)
    plotPCvectors(eigenvectors[,1], 1)
    plotPCvectors(eigenvectors[,2], 2)
    close(eigenvectors)
    tblcr = read.table(
                file = paste0(pfull$dirpca, "/PC_vs_covs_corr.txt"),
                header = TRUE,
                sep = "\t")
    pander(head(tblcr, 3))
    tblpv = read.table(
                file = paste0(pfull$dirpca, "/PC_vs_covs_pvalue.txt"),
                header = TRUE,
                sep = "\t")
    pander(head(tblpv, 3))

    # --- Mwas99 [] ---
    # Key functions: ramwas5MWAS, getMWASandLocations, layout, qqPlotFast, manPlotPrepare, manPlotFast, ramwas7riskScoreCV
    ramwas5MWAS(param)
    mwas = getMWASandLocations(param)
    layout(matrix(c(1,2), 1, 2, byrow = TRUE), widths=c(1,2.2))
    qqPlotFast(mwas$`p-value`)
    man = manPlotPrepare(
            pvalues = mwas$`p-value`,
            chr = mwas$chr,
            pos = mwas$start,
            chrmargins = 0)
    manPlotFast(man)
    ramwas7riskScoreCV(param)

    # --- Plot Cv1 [] ---
    # Key functions: readRDS, plotPrediction, success, plotCVcors, parameterPreprocess
    cv = readRDS(paste0(pfull$dircv, "/rds/CpGs=000050_alpha=0.000000.rds"))
    plotPrediction(
            param = pfull,
            outcome = cv$outcome,
            forecast = cv$forecast,
            cpgs2use = 50,
            main = "Prediction success (EN on coverage)")
    cl = readRDS(sprintf("%s/rds/cor_data_alpha=%f.rds",
                        pfull$dircv,
                        pfull$mmalpha))
    plotCVcors(cl, pfull)
    pfull = parameterPreprocess(param)
    cat("CpG score directory:", "\n", pfull$dircoveragenorm,"\n")
    cat("PCA directory:", "\n", pfull$dirpca, "\n")
    cat("MWAS directory:", "\n", pfull$dirmwas, "\n")
    cat("MRS directory:", "\n", pfull$dircv, "\n")
    cat("CpG-SNP directory:", "\n", pfull$dirSNPs, "\n")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ramwas_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ramwas_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ramwas_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RAMWAS:", paste0("    ramwas: ", packageVersion("ramwas"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ramwas_results.csv
    touch ${prefix}_ramwas_output.rds
    echo "BIOC_RAMWAS:" > versions.yml
    echo "    ramwas: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RAMWAS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RAMWAS(ch_input)

    emit:
    results  = BIOC_RAMWAS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RAMWAS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RAMWAS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RAMWAS.out.versions  // channel: path(versions.yml)
}
