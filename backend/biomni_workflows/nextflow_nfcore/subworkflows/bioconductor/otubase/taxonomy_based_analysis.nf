#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: otubase — taxonomy_based_analysis
// Import RDP taxonomic classification files and metadata, generate a taxonomic abundance table, estimate richness, and cluster samples.
// Input: sogin.groups, sogin.unique.fix.tax, sogin.names, sample_metadata.txt, sogin.fasta
// Container: quay.io/biocontainers/bioconductor-otubase:1.60.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-otubase:1.60.0--r45hdfd78af_0"

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
    .bm_deps <- c("OTUbase", "vegan")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library("OTUbase")
    library("vegan")
    
    # 1. Define directory path (using current working directory where user files are located)
    dirPath <- "."
    
    # 2. Read taxonomy data and metadata using readTAXset
    soginTAX <- readTAXset(dirPath=dirPath, fastafile='sogin.fasta', sampleADF='sample_metadata.txt', taxfile='sogin.unique.fix.tax', namefile='sogin.names', samplefile='sogin.groups')
    print(soginTAX)
    
    # 3. Access taxonomic classifications
    tax_data <- tax(soginTAX)
    print(head(tax_data))
    write.csv(tax_data, "taxonomic_classifications.csv", row.names=TRUE)
    
    # 4. Generate taxonomic abundance table at a specific rank
    abundTAX <- abundance(soginTAX, weighted=F, taxCol='genus', collab='Site')
    print(head(abundTAX))
    write.csv(abundTAX, "taxonomic_abundance_genus.csv", row.names=TRUE)
    
    # 5. Estimate richness
    estrichTAX <- apply(abundTAX, 2, estimateR)
    print(estrichTAX)
    write.csv(estrichTAX, "richness_estimates_genus.csv", row.names=TRUE)
    
    # 6. Cluster samples and save the dendrogram plot
    pdf("sample_clustering_genus.pdf")
    clusterSamples(soginTAX, taxCol='genus', distmethod='jaccard', clustermethod='complete', collab='Site')
    dev.off()
    
    # Save the constructed TAXset object
    saveRDS(soginTAX, "soginTAX.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS":
        otubase: \$(Rscript -e 'cat(as.character(packageVersion("otubase")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_taxonomy_based_analysis.csv versions.yml
    """
}

workflow BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sogin.groups, sogin.unique.fix.tax, sogin.names, sample_metadata.txt, sogin.fasta ] ]

    main:
    BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS.out.tables
    plots    = BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS.out.plots
    objects  = BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS.out.objects
    versions = BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS.out.versions
}
