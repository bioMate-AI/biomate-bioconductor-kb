#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lola — genomic_region_enrichment_analysis
// Run enrichment analysis on user-provided genomic region sets against a reference database using a custom background universe, and extract/save the results.
// Input: setA_100.bed, setB_100.bed, setC_100.bed, activeDHS_universe.bed
// Container: quay.io/biocontainers/bioconductor-lola:1.40.1--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LOLA_GENOMIC_REGION_ENRICHMENT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-lola:1.40.1--r45hdfd78af_0"

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
    .bm_deps <- c("data.table", "lola")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library("LOLA")
    library("data.table")
    
    # 1. Load the reference database
    # The database is expected to be located at "LOLACore/hg19" in the working directory
    regionDB = loadRegionDB("LOLACore/hg19")
    
    # 2. Read user region sets and the background universe
    # Reading exactly the files specified by the user from the working directory
    regionSetA = readBed("setA_100.bed")
    regionSetB = readBed("setB_100.bed")
    regionSetC = readBed("setC_100.bed")
    activeDHS = readBed("activeDHS_universe.bed")
    
    # 3. Combine user region sets into a GRangesList
    userSets = GRangesList(regionSetA, regionSetB, regionSetC)
    
    # 4. Run the enrichment analysis
    locResults = runLOLA(userSets, activeDHS, regionDB, cores=1)
    
    # 5. Order and explore results
    orderedResults = locResults[order(meanRnk, decreasing=FALSE),][1:20,]
    
    # Save ordered top results to a CSV file
    write.csv(orderedResults, file = "ordered_top20_lola_results.csv", row.names = FALSE)
    # Save full results as an RDS object
    saveRDS(locResults, file = "lola_results.rds")
    
    # 6. Write results to files using writeCombinedEnrichment
    writeCombinedEnrichment(locResults, outFolder= "lolaResults", includeSplits=TRUE)
    
    # 7. Extract specific overlapping regions for a given result
    oneResult = locResults[2,]
    overlaps = extractEnrichmentOverlaps(oneResult, userSets, regionDB)
    
    # Save the extracted overlaps to an RDS file
    saveRDS(overlaps, file = "extracted_overlaps.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_LOLA_GENOMIC_REGION_ENRICHMENT_ANALYSIS":
        lola: \$(Rscript -e 'cat(as.character(packageVersion("lola")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_region_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_LOLA_GENOMIC_REGION_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ setA_100.bed, setB_100.bed, setC_100.bed, activeDHS_universe.bed ] ]

    main:
    BIOC_LOLA_GENOMIC_REGION_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_LOLA_GENOMIC_REGION_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_LOLA_GENOMIC_REGION_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_LOLA_GENOMIC_REGION_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_LOLA_GENOMIC_REGION_ENRICHMENT_ANALYSIS.out.versions
}
