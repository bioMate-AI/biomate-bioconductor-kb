#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SubCellBarCode
// Mass-Spectrometry based spatial proteomics have enabled the proteome-wide mapping of protein subcell
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SubCellBarCode/inst/doc/SubCellBarCode.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SubCellBarCode")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SUBCELLBARCODE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-subcellbarcode"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-subcellbarcode:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-subcellbarcode:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_subcellbarcode_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_subcellbarcode_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_subcellbarcode_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SubCellBarCode)
    library(jsonlite)

    # --- Dimensionality Reduction [] ---
    # Key functions: tsneVisualization
    tsne.map <- tsneVisualization(
        protein.data = df_sub,
        markerProteins = r.markers,
        dims = 2,
        theta = 0.5,
        perplexity = 60
    )


    # --- Subcellular Classification [] ---
    # Key functions: svmClassification, computeThresholdCompartment, applyThresholdCompartment, computeThresholdNeighborhood, applyThresholdNeighborhood, mergeCls
    cls <- svmClassification(
        markerProteins = r.markers,
        protein.data = df_sub,
        markerprot.df = markerProteins
    )
    test.A <- cls[[1]]$svm.test.prob.out
    test.B <- cls[[2]]$svm.test.prob.out
    all.A <- cls[[1]]$all.prot.pred
    all.B <- cls[[2]]$all.prot.pred
    t.c.df <- computeThresholdCompartment(test.repA = test.A, test.repB = test.B)
    c.cls.df <- applyThresholdCompartment(
        all.repA = all.A,
        all.repB = all.B,
        threshold.df = t.c.df
    )
    t.n.df <- computeThresholdNeighborhood(test.repA = test.A, test.repB = test.B)
    n.cls.df <- applyThresholdNeighborhood(
        all.repA = all.A,
        all.repB = all.B,
        threshold.df = t.n.df
    )
    cls.df <- mergeCls(compartmentCls = c.cls.df, neighborhoodCls = n.cls.df)


    # --- Relocation Analysis [] ---
    # Key functions: plotBarcode, plotMultipleProtein, candidateRelocatedProteins
    plotBarcode(
        sampleClassification = cls.df,
        protein = "NLRP4",
        s1PSM = hcc827CtrlPSMCount
    )
    proteasome26s <- c("PSMA7", "PSMC3", "PSMA4", "PSMB4")
    plotMultipleProtein(
        sampleClassification = cls.df,
        proteinList = proteasome26s
    )
    candidate.df <- candidateRelocatedProteins(
        sampleCls1 = cls.df,
        s1PSM = hcc827CtrlPSMCount,
        s1Quant = hcc827Ctrl,
        sampleCls2 = hcc827GEFClass,
        s2PSM = hcc827GefPSMCount,
        s2Quant = hcc827GEF,
        min.psm = 2,
        pearson.cor = 0.8
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_subcellbarcode_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_subcellbarcode_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_subcellbarcode_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SUBCELLBARCODE:", paste0("    subcellbarcode: ", packageVersion("SubCellBarCode"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_subcellbarcode_results.csv
    touch ${prefix}_subcellbarcode_output.rds
    echo "BIOC_SUBCELLBARCODE:" > versions.yml
    echo "    subcellbarcode: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SUBCELLBARCODE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SUBCELLBARCODE(ch_input)

    emit:
    results  = BIOC_SUBCELLBARCODE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SUBCELLBARCODE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SUBCELLBARCODE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SUBCELLBARCODE.out.versions  // channel: path(versions.yml)
}
