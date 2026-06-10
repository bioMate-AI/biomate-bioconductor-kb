#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gothic — standard_gothic_pipeline
// Identify significant genomic interactions from raw aligned paired-end reads (Bowtie output) using the standard GOTHiC pipeline.
// Input: fileName1, fileName2
// Container: quay.io/biocontainers/bioconductor-gothic:1.46.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GOTHIC_STANDARD_GOTHIC_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-gothic:1.46.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg18", "gothic")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    library(GOTHiC)
    library(BSgenome.Hsapiens.UCSC.hg18)
    
    fileName1 <- "fileName1"
    fileName2 <- "fileName2"
    
    if (!file.exists(fileName1) || !file.exists(fileName2)) {
      stop("Required input files 'fileName1' and/or 'fileName2' are missing from the working directory.")
    }
    
    paired = pairReads(fileName1, fileName2, sampleName="lymphoid_chr20", 
    DUPLICATETHRESHOLD = 1, fileType="Table")
    
    mapped=mapReadsToRestrictionSites(paired, sampleName="lymphoid_chr20", 
    BSgenomeName="BSgenome.Hsapiens.UCSC.hg18", 
    genome=BSgenome.Hsapiens.UCSC.hg18, 
    restrictionSite="A^AGCTT", enzyme="HindIII", parallel=FALSE, cores=1)
    
    binom=GOTHiC(fileName1,fileName2, sampleName="lymphoid_chr20", 
    res=1000000, BSgenomeName="BSgenome.Hsapiens.UCSC.hg18",
    genome=BSgenome.Hsapiens.UCSC.hg18, 
    restrictionSite="A^AGCTT", enzyme="HindIII" ,cistrans="all", filterdist=10000,
    DUPLICATETHRESHOLD=1, fileType="Table", parallel=FALSE, cores=NULL)
    
    saveRDS(paired, "paired_reads.rds")
    saveRDS(mapped, "mapped_reads.rds")
    saveRDS(binom, "gothic_interactions.rds")
    write.csv(binom, "gothic_interactions.csv", row.names=FALSE)
    
    pdf("gothic_pvalue_density.pdf")
    if (!is.null(binom)) {
      if ("pvalue" %in% colnames(binom)) {
        plot(density(binom\$pvalue), main="P-value distribution", xlab="p-value", col="blue", lwd=2)
      } else if ("p-value" %in% colnames(binom)) {
        plot(density(binom\$`p-value`), main="P-value distribution", xlab="p-value", col="blue", lwd=2)
      }
    }
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GOTHIC_STANDARD_GOTHIC_PIPELINE":
        gothic: \$(Rscript -e 'cat(as.character(packageVersion("gothic")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_gothic_pipeline.csv versions.yml
    """
}

workflow BIOC_GOTHIC_STANDARD_GOTHIC_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fileName1, fileName2 ] ]

    main:
    BIOC_GOTHIC_STANDARD_GOTHIC_PIPELINE(ch_input)

    emit:
    tables   = BIOC_GOTHIC_STANDARD_GOTHIC_PIPELINE.out.tables
    plots    = BIOC_GOTHIC_STANDARD_GOTHIC_PIPELINE.out.plots
    objects  = BIOC_GOTHIC_STANDARD_GOTHIC_PIPELINE.out.objects
    versions = BIOC_GOTHIC_STANDARD_GOTHIC_PIPELINE.out.versions
}
