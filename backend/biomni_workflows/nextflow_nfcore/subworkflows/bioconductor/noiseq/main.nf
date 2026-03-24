#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NOISeq
// Analysis of RNA-seq expression data or other similar kind of data. Exploratory plots to evualuate sa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NOISeq/inst/doc/NOISeq.R
// Upstream  : none
// Downstream: metaSeq
//
// Install: BiocManager::install("NOISeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NOISEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-noiseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-noiseq:2.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-noiseq:2.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_noiseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_noiseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_noiseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ARSyNseq)
    library(QCreport)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(NOISeq)
    data(Marioni)
    # --- Factors [] ---
    # Key functions: frame
    myfactors = data.frame(Tissue=c("Kidney","Liver","Kidney","Liver","Liver","Kidney","Liver",
                                    "Kidney","Liver","Kidney"),
                           TissueRun = c("Kidney_1","Liver_1","Kidney_1","Liver_1","Liver_1",
                                         "Kidney_1","Liver_1","Kidney_2","Liver_2","Kidney_2"),
                           Run = c(rep("R1", 7), rep("R2", 3)))
    # --- Readdata [] ---
    # Key functions: readData
    mydata <- readData(data=mycounts,length=mylength, gc=mygc, biotype=mybiotypes,
                       chromosome=mychroms, factors=myfactors)
    mydata
    # --- Str [] ---
    # Key functions: assayData, pData, featureData
    str(mydata)
    head(assayData(mydata)$exprs)
    head(pData(mydata))
    head(featureData(mydata)@data)
    # --- Readdata2 [] ---
    # Key functions: readData
    mydata <- readData(data=mycounts,chromosome=mychroms, factors=myfactors)
    # --- Readdata3 [] ---
    # Key functions: addData
    mydata <- addData(mydata, length=mylength, biotype=mybiotypes, gc = mygc)
    # --- Dat [] ---
    # Key functions: dat
    myexplodata <- dat(mydata, type = "biodetection")
    explo.plot(myexplodata, plottype = "persample")
    # --- Nicedata [] ---
    # Key functions: dat2save
    mynicedata <- dat2save(myexplodata)
    # --- Fig Biodetection [] ---
    # Key functions: dat, plots
    mybiodetection <- dat(mydata, k = 0, type = "biodetection", factor = NULL)
    par(mfrow = c(1,2))  # we need this instruction because two plots (one per sample) will be generated
    explo.plot(mybiodetection, samples=c(1,2), plottype = "persample")
    # --- Fig Biodetection2 [] ---
    # Key functions: plots
    par(mfrow = c(1,2))  # we need this instruction because two plots (one per sample) will be generated
    explo.plot(mybiodetection, samples=c(1,2), toplot = "protein_coding", plottype = "comparison")
    # --- Fig Boxplot1 [] ---
    # Key functions: dat
    mycountsbio = dat(mydata, factor = NULL, type = "countsbio")
    explo.plot(mycountsbio, toplot = 1, samples = 1, plottype = "boxplot")
    # --- Fig Sat1 [] ---
    # Key functions: dat
    mysaturation = dat(mydata, k = 0, ndepth = 7, type = "saturation")
    explo.plot(mysaturation, toplot = 1, samples = 1:2, yleftlim = NULL, yrightlim = NULL)
    # --- Fig Length [] ---
    # Key functions: dat
    mylengthbias = dat(mydata, factor = "Tissue", type = "lengthbias")
    explo.plot(mylengthbias, samples = NULL, toplot = "global")
    # --- Fig Gc [] ---
    # Key functions: dat
    myGCbias = dat(mydata, factor = "Tissue", type = "GCbias")
    explo.plot(myGCbias, samples = NULL, toplot = "global")
    # --- Fig Countdistr [] ---
    # Key functions: dat
    mycd = dat(mydata, type = "cd", norm = FALSE, refColumn = 1)
    explo.plot(mycd)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_noiseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_noiseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_noiseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NOISEQ:", paste0("    noiseq: ", packageVersion("NOISeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_noiseq_results.csv
    touch ${prefix}_noiseq_output.rds
    echo "BIOC_NOISEQ:" > versions.yml
    echo "    noiseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NOISEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NOISEQ(ch_input)

    emit:
    results  = BIOC_NOISEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NOISEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NOISEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NOISEQ.out.versions  // channel: path(versions.yml)
}
