#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MAGAR
// "Methylation-Aware Genotype Association in R" (MAGAR) computes methQTL from DNA methylation and geno
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MAGAR/inst/doc/MAGAR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MAGAR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MAGAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-magar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-magar:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-magar:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_magar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_magar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_magar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MAGAR)
    library(jsonlite)

    # --- qtl Set Option [] ---
    # Key functions: qtlSetOption
    rnb.set <- load.rnb.set("rnb_set_dir")
    data.loc <- list(idat.dir=rnb.set,geno.dir=plink.dir)
    qtlSetOption(geno.data.type="plink",
    # --- call methQTL [] ---
    # Key functions: qtlSetOption
    imp.data <- loadMethQTLInput(system.file("extdata","reduced_methQTL",package="MAGAR"))
    qtlSetOption(standard.deviation.gauss=100,
    meth.qtl.res <- doMethQTL(imp.data,default.options=FALSE,p.val.cutoff=0.05)
    # --- qtl Plot S N P Cp G Interaction [] ---
    # Key functions: qtlPlotSNPCpGInteraction, qtlDistanceScatterplot
    result.table <- result.table[order(result.table$P.value,decreasing=FALSE),]
    qtlPlotSNPCpGInteraction(imp.data,result.table$CpG[1],result.table$SNP[1])
    qtlDistanceScatterplot(meth.qtl.res)
    # --- qtl Base Substitution Enrichment [] ---
    # Key functions: qtlBaseSubstitutionEnrichment
    res <- qtlBaseSubstitutionEnrichment(meth.qtl.res)
    # --- qtl Venn Plot [] ---
    # Key functions: qtlVennPlot, qtlUpsetPlot
    meth.qtl.res.2 <- loadMethQTLResult(system.file("extdata","MethQTLResult_chr18",package="MAGAR"))
    meth.qtl.list <- list(First=meth.qtl.res,Second=meth.qtl.res.2)
    qtlVennPlot(meth.qtl.list,out.folder=getwd())
    # --- qtl Set Option [] ---
    # Key functions: qtlSetOption
    qtlSetOption(cluster.config = c(h_vmem="60G",mem_free="20G"))
    qtlSetOption(rscript.path = "/usr/bin/Rscript")
    meth.qtl.res <- doMethQTL(meth.qtl = imp.data,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_magar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_magar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_magar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MAGAR:", paste0("    magar: ", packageVersion("MAGAR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_magar_results.csv
    touch ${prefix}_magar_output.rds
    echo "BIOC_MAGAR:" > versions.yml
    echo "    magar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MAGAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MAGAR(ch_input)

    emit:
    results  = BIOC_MAGAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MAGAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MAGAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MAGAR.out.versions  // channel: path(versions.yml)
}
