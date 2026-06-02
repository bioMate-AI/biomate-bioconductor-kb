#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ChemmineR
// ChemmineR is a cheminformatics package for analyzing drug-like small molecule data in R. Its latest 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ChemmineR/inst/doc/ChemmineR.R
// Upstream  : RCurl, fmcsR, gplots, rgl, scatterplot3d
// Downstream: eiR, fmcsR, ChemmineDrugs
//
// Install: BiocManager::install("ChemmineR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHEMMINER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chemminer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chemminer:3.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chemminer:3.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chemminer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chemminer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chemminer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SDFDataTable)
    library(jsonlite)

    # --- Filter by row sum threshold [] ---
    # Key functions: conMA, rowSums
    conMA(sdfset[1:2],
    exclude=c("H")) # Create bond matrix for first two molecules in sdfset
    conMA(sdfset[[1]], exclude=c("H")) # Return bond matrix for first molecule
    # --- Hierarchical clustering [] ---
    # Key functions: hclust
    simMA <- sapply(cid(fpset), function(x) fpSim(fpset[x], fpset, sorted=FALSE))
    hc <- hclust(as.dist(1-simMA), method="single")
    plot(as.dendrogram(hc), edgePar=list(col=4, lwd=2), horiz=TRUE)
    # --- Sdf2smiles analysis [] ---
    # Key functions: sdf2smiles, smiles2sdf, view, atomcountMA, SDFDataTable, fmcs, plotMCS, cid
    inchis <- c(
    "InChI=1S/C15H26O/c1-9(2)11-6-5-10(3)15-8-7-14(4,16)13(15)12(11)15/h9-13,16H,5-8H2,1-4H3/t10-,11+,12-,13+,14+,15-/m1/s1",
    "InChI=1S/C15H20Br2O2/c1-2-12(17)13-7-3-4-8-14-15(19-13)10-11(18-14)6-5-9-16/h3-4,6,9,11-15H,2,7-8,10H2,1H3/t5-,11-,12+,13+,14-,15-/m1/s1",

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chemminer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chemminer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chemminer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHEMMINER:", paste0("    chemminer: ", packageVersion("ChemmineR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chemminer_results.csv
    touch ${prefix}_chemminer_output.rds
    echo "BIOC_CHEMMINER:" > versions.yml
    echo "    chemminer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHEMMINER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHEMMINER(ch_input)

    emit:
    results  = BIOC_CHEMMINER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHEMMINER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHEMMINER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHEMMINER.out.versions  // channel: path(versions.yml)
}
