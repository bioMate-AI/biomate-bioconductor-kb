#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RnBeads
// RnBeads facilitates comprehensive analysis of various types of DNA methylation data at the genome sc
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RnBeads/inst/doc/RnBeads.R
// Upstream  : ggplot2, rtracklayer
// Downstream: MAGAR
//
// Install: BiocManager::install("RnBeads")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNBEADS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rnbeads"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rnbeads:2.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rnbeads:2.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rnbeads_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rnbeads_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rnbeads_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(M)
    library(jsonlite)

    # --- Analysis [] ---
    # Key functions: analysis
    ## rnb.run.analysis(dir.reports=report.dir, sample.sheet=sample.annotation,
    ##     data.dir=idat.dir, data.type="infinium.idat.dir")
    # --- Data [] ---
    # Key functions: data
    library(RnBeads.hg19)
    data(small.example.object)
    rnb.set.example
    # --- Nsites [] ---
    # Key functions: nsites, samples
    nsites(rnb.set.example)
    samples(rnb.set.example)
    # --- Pheno [] ---
    # Key functions: pheno
    pheno(rnb.set.example)[, 1:4]
    # --- Meth [] ---
    # Key functions: meth
    mm <- meth(rnb.set.example)
    # --- Regions [] ---
    # Key functions: regions
    summarized.regions(rnb.set.example)
    # --- Meth [] ---
    # Key functions: meth
    rnb.options(identifiers.column="Sample_ID")
    meth(rnb.set.example, type="promoters", row.names=TRUE, i=1:5, j=1:3)
    # --- Mval [] ---
    # Key functions: mval
    mval(rnb.set.example, type="promoters", row.names=TRUE)[1:5, 1:3]
    # --- Annotation [] ---
    # Key functions: annotation
    annot.sites <- annotation(rnb.set.example)
    head(annot.sites)
    annot.promoters <- annotation(rnb.set.example, type="promoters")
    head(annot.promoters)
    # --- Samples [] ---
    # Key functions: samples, setdiff, sites, nsites, pheno, addPheno
    # Remove samples
    rnb.set2 <- remove.samples(rnb.set.example, samples(rnb.set.example)[c(2, 6, 10)])
    setdiff(samples(rnb.set.example), samples(rnb.set2))
    # Remove probes which are not in CpG context
    notCpG <- annot.sites[,"Context"]!="CG"
    # --- Boxplot [] ---
    # Key functions: annotation
    # boxplot of control probes
    rnb.plot.control.boxplot(rnb.set.example)
    # barplot of a selected control probe
    control.meta.data <- rnb.get.annotation("controls450")
    ctrl.probe<-paste0(unique(control.meta.data[["Target"]])[4], ".1")
    # --- Qc [] ---
    # Key functions: qc
    qc_data<-qc(rnb.set.example)
    # --- Start [] ---
    # Key functions: start
    ## logger.start(fname=NA)
    # --- Import [] ---
    # Key functions: import
    ## result <- rnb.run.import(data.source=data.source,
    ##     data.type="infinium.idat.dir", dir.reports=report.dir)
    ## rnb.set <- result$rnb.set
    # --- Summary [] ---
    # Key functions: pheno, M, meth, dpval, qc
    ## rnb.set
    ## summary(pheno(rnb.set))
    ## dim(M(rnb.set))
    ## summary(M(rnb.set))
    ## dim(meth(rnb.set))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rnbeads_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rnbeads_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rnbeads_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RNBEADS:", paste0("    rnbeads: ", packageVersion("RnBeads"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnbeads_results.csv
    touch ${prefix}_rnbeads_output.rds
    echo "BIOC_RNBEADS:" > versions.yml
    echo "    rnbeads: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RNBEADS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RNBEADS(ch_input)

    emit:
    results  = BIOC_RNBEADS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RNBEADS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RNBEADS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RNBEADS.out.versions  // channel: path(versions.yml)
}
