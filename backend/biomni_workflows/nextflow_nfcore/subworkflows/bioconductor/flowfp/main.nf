#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowFP
// Fingerprint generation of flow cytometry data, used to facilitate the application of machine learnin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowFP/inst/doc/flowFP_HowTo.R
// Upstream  : none
// Downstream: flowBin
//
// Install: BiocManager::install("flowFP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWFP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowfp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowfp:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowfp:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowfp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowfp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowfp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowFP)
    library(jsonlite)

    # --- Model [] ---
    # Key functions: flowFPModel, show
    mod <-  flowFPModel(fs1, name="CD45/SS Model", parameters=c(2,5), nRecursions=7)
    show(mod)
    # --- Fingerprint [] ---
    # Key functions: flowFP, show
    fp <- flowFP (fs1, mod)
    show(fp)
    plot (fp, type="stack")
    # --- Plex1 [] ---
    # Key functions: flowFPModel, flowFP, flowFPPlex
    data(fs2)
    mod1 <-  flowFPModel(fs1, name="CD45/SS Model vs fs1", parameters=c("SS Log", "FL3 Log"), nRecursions=7)
    mod2 <-  flowFPModel(fs2, name="CD45/SS Model vs fs2", parameters=c("SS Log", "FL3 Log"), nRecursions=7)
    fp1_1 <- flowFP (fs1, mod1)
    fp1_2 <- flowFP (fs1, mod2)
    # --- Plex2 [] ---
    # Key functions: flowFP, flowFPPlex, nRecursions, append
    fp <- flowFP (fs1, param=c("SS Log", "FL3 Log"), nRecursions=8)
    plex <- flowFPPlex()
    for (levels in 8:5) {
    	nRecursions(fp) <- levels
    	plex <- append (plex, fp)
    # --- Qc1 [] ---
    # Key functions: flowFP
    fp1 <- flowFP (fs1, parameters=c("SS Log", "FL3 Log"), name="self model: fs1", nRecursions=5)
    plot (fp1, type="qc", main="Gate QC for Sample fs1")
    # --- Qc2 [] ---
    # Key functions: flowFP
    fp2 <- flowFP (fs2, parameters=c("SS Log", "FL3 Log"), name="self model: fs2", nRecursions=5)
    plot (fp2, type="qc", main="Gate QC for Sample fs2")
    # --- Subsample [] ---
    # Key functions: phenoData, factor, exprs, sample, flowFP
    phenoData(fs2)$Tube <- factor(1:7)   #$
    for (i in 1:7) {
    	exprs(fs2[[i]]) = exprs(fs2[[i]])[sample(1:nrow(fs2[[i]]),size=2500),]
    }
    fp2 <- flowFP (fs2, param=c(2,5), nRec=5)
    # --- Fvizfigure [] ---
    # Key functions: xyplot
    xyplot (`FL3 Log` ~ `SS Log` | Tube, data=fs2)
    # --- Plot [] ---
    # Key functions: object
    plot(trellis.last.object())
    # --- Qc4 [] ---
    # Key functions: flowFP
    data(plate)
    fp <- flowFP (plate, parameters=c("SSC-H","FL3-H","FL4-H"), nRecursions=5)
    plot (fp, type='plate')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowfp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowfp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowfp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWFP:", paste0("    flowfp: ", packageVersion("flowFP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowfp_results.csv
    touch ${prefix}_flowfp_output.rds
    echo "BIOC_FLOWFP:" > versions.yml
    echo "    flowfp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWFP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWFP(ch_input)

    emit:
    results  = BIOC_FLOWFP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWFP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWFP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWFP.out.versions  // channel: path(versions.yml)
}
