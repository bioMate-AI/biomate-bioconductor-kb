#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeneBreak
// Recurrent breakpoint gene detection on copy number aberration profiles.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeneBreak/inst/doc/GeneBreak.R
// Upstream  : CGHcall, biomaRt
// Downstream: none
//
// Install: BiocManager::install("GeneBreak")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEBREAK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genebreak"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genebreak:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genebreak:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genebreak_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genebreak_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genebreak_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Used)
    library(jsonlite)

    # --- Loadingcopynumberdata [] ---
    # Key functions: data
    library(CGHcall)
    data( "copynumber.data.chr20" )
    # --- Getbreakpoints [] ---
    # Key functions: getBreakpoints
    breakpoints <- getBreakpoints( data = copynumber.data.chr20 )
    breakpoints
    # --- Getbreakpointsalternative [] ---
    # Key functions: frame, chromosomes, bpstart, bpend, segmented, calls
    ## library(CGHcall)
    ## cgh <- copynumber.data.chr20
    ##
    ## segmented <- data.frame( Chromosome=chromosomes(cgh), Start=bpstart(cgh),
    ##  End=bpend(cgh), FeatureName=rownames(cgh), segmented(cgh))
    # --- Bpfilter [] ---
    # Key functions: bpFilter
    breakpointsFiltered <- bpFilter( breakpoints, filter = "CNA-ass" )
    breakpointsFiltered
    # --- Loadingannotation [] ---
    # Key functions: data
    data( "ens.gene.ann.hg18" )
    # --- Addgeneannotation [] ---
    # Key functions: addGeneAnnotation
    breakpointsAnnotated <- addGeneAnnotation( breakpointsFiltered, ens.gene.ann.hg18 )
    # --- Showfeatures Pcmtd2 [] ---
    # Key functions: featuresPerGene
    featuresPerGene ( breakpointsAnnotated , geneName = "PCMTD2" )
    # --- Showgeneassociatedfeatureinfo [] ---
    # Key functions: geneInfo
    geneFeatures <- geneInfo( breakpointsAnnotated )
    head( geneFeatures[ ,
      c("Gene", "Chromosome", "Start", "End", "featureTotal",
        "featureNames", "remarks") ] )
    # --- Bpgenes [] ---
    # Key functions: bpGenes
    breakpointGenes <- bpGenes( breakpointsAnnotated )
    # --- Headbreakpointgenes [] ---
    # Key functions: geneInfo
    result_BreakpointGenes <- geneInfo ( breakpointGenes )
    head( result_BreakpointGenes[ which ( result_BreakpointGenes$sampleCount > 0 ) ,
      c( "Gene", "Chromosome", "Start", "End", "featureTotal", "nrOfBreakLocations",
         "sampleCount", "sampleNamesWithBreakpoints") ] )
    # --- Bpstats [] ---
    # Key functions: bpStats
    breakpointStatistics <- bpStats( breakpointGenes,
      level = "gene", method = "Gilbert" )
    # --- Recurrentgenes [] ---
    # Key functions: recurrentGenes
    head( recurrentGenes( breakpointStatistics ) )
    # --- Bpstats [] ---
    # Key functions: bpStats
    breakpointStatistics <- bpStats(
      breakpointStatistics, level = "feature", method = "BH" )
    # --- Recurrentgenes [] ---
    # Key functions: featureInfo
    head( featureInfo( breakpointStatistics ) )
    # --- Bpplot [] ---
    # Key functions: bpPlot
    bpPlot( breakpointStatistics, fdr.threshold = 0.1 )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genebreak_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genebreak_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genebreak_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENEBREAK:", paste0("    genebreak: ", packageVersion("GeneBreak"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genebreak_results.csv
    touch ${prefix}_genebreak_output.rds
    echo "BIOC_GENEBREAK:" > versions.yml
    echo "    genebreak: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENEBREAK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENEBREAK(ch_input)

    emit:
    results  = BIOC_GENEBREAK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENEBREAK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENEBREAK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENEBREAK.out.versions  // channel: path(versions.yml)
}
