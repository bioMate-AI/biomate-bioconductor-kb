#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: otubase — otu_based_analysis
// Import Mothur OTU files and metadata, generate an abundance table, estimate richness, cluster samples, and subset the dataset.
// Input: sogin.groups, sogin.unique.filter.fn.list, sample_metadata.txt, sogin.fasta
// Container: quay.io/biocontainers/bioconductor-otubase:1.60.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OTUBASE_OTU_BASED_ANALYSIS {
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
    .bm_deps <- c("otubase", "vegan")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(OTUbase)
    library(vegan)
    
    # 1. Define directory path (working directory where user files are located)
    dirPath <- "."
    
    # 2. Read OTU data and metadata using readOTUset
    soginOTU <- readOTUset(
      dirPath = dirPath,
      level = "0.03",
      samplefile = "sogin.groups",
      fastafile = "sogin.fasta",
      otufile = "sogin.unique.filter.fn.list",
      sampleADF = "sample_metadata.txt"
    )
    
    # Print object summary
    print(soginOTU)
    
    # 3. Access sequence and sample IDs
    cat("--- Sequence IDs ---\n")
    print(head(id(soginOTU)))
    
    cat("--- Sequences ---\n")
    print(head(sread(soginOTU)))
    
    cat("--- Sample IDs ---\n")
    print(head(sampleID(soginOTU)))
    
    cat("--- Sample Metadata ---\n")
    print(head(sData(soginOTU)))
    
    cat("--- OTU IDs ---\n")
    print(head(otuID(soginOTU)))
    
    # 4. Generate OTU abundance table
    abundOTU <- abundance(soginOTU, weighted = FALSE, collab = 'Site')
    cat("--- Abundance Table ---\n")
    print(head(abundOTU))
    
    # Save abundance table to CSV
    write.csv(abundOTU, file = "abundance_table.csv", row.names = TRUE)
    
    # 5. Estimate richness using vegan::estimateR
    estrichOTU <- apply(abundOTU, 2, estimateR)
    cat("--- Richness Estimates ---\n")
    print(estrichOTU)
    
    # Save richness estimates to CSV
    write.csv(estrichOTU, file = "richness_estimates.csv", row.names = TRUE)
    
    # 6. Cluster samples (plots a dendrogram, save to PDF)
    pdf("sample_clustering.pdf", width = 8, height = 6)
    clusterSamples(soginOTU, distmethod = 'jaccard', clustermethod = 'complete', collab = 'Site')
    dev.off()
    
    # 7. Subset the OTU set
    # Wrapped in tryCatch to handle cases where user-provided metadata/groups 
    # might not contain these exact sample IDs.
    tryCatch({
      soginReduced <- subOTUset(soginOTU, samples = c("137", "138", "53R", "55R"))
      print(soginReduced)
      saveRDS(soginReduced, file = "sogin_reduced.rds")
    }, error = function(e) {
      warning("Could not subset OTU set with the specified sample IDs: ", e\$message)
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_OTUBASE_OTU_BASED_ANALYSIS":
        otubase: \$(Rscript -e 'cat(as.character(packageVersion("otubase")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_otu_based_analysis.csv versions.yml
    """
}

workflow BIOC_OTUBASE_OTU_BASED_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sogin.groups, sogin.unique.filter.fn.list, sample_metadata.txt, sogin.fasta ] ]

    main:
    BIOC_OTUBASE_OTU_BASED_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_OTUBASE_OTU_BASED_ANALYSIS.out.tables
    plots    = BIOC_OTUBASE_OTU_BASED_ANALYSIS.out.plots
    objects  = BIOC_OTUBASE_OTU_BASED_ANALYSIS.out.objects
    versions = BIOC_OTUBASE_OTU_BASED_ANALYSIS.out.versions
}
