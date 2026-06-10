#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: phyloseq — differential_abundance_deseq2
// Convert a phyloseq object to a DESeq2 object to perform negative binomial differential abundance testing and visualize the results.
// Input: phyloseq_object
// Container: quay.io/biocontainers/bioconductor-phyloseq:1.54.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2 {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-phyloseq:1.54.0--r45hdfd78af_0"

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
    .bm_deps <- c("DESeq2", "ggplot2", "phyloseq")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(phyloseq)
    library(DESeq2)
    library(ggplot2)
    
    # 1. Read the user input file (phyloseq S4 object)
    kostic <- readRDS("phyloseq_object")
    
    # Define alpha threshold for significance filtering
    alpha <- 0.01
    
    # 2. Filter out low-read samples and clean up metadata
    kostic <- subset_samples(kostic, DIAGNOSIS != "None")
    kostic <- prune_samples(sample_sums(kostic) > 500, kostic)
    
    # 3. Convert the phyloseq object to a DESeq2 dataset
    diagdds = phyloseq_to_deseq2(kostic, ~ DIAGNOSIS)
    
    # 4. Estimate size factors using geometric means and run DESeq2
    gm_mean = function(x, na.rm=TRUE){ exp(sum(log(x[x > 0]), na.rm=na.rm) / length(x)) }
    geoMeans = apply(counts(diagdds), 1, gm_mean)
    diagdds = estimateSizeFactors(diagdds, geoMeans = geoMeans)
    diagdds = DESeq(diagdds, fitType="local")
    
    # 5. Extract and filter significant results
    res = results(diagdds)
    res = res[order(res\$padj, na.last=NA), ]
    sigtab = res[(res\$padj < alpha), ]
    sigtab = cbind(as(sigtab, "data.frame"), as(tax_table(kostic)[rownames(sigtab), ], "matrix"))
    
    # Prepare the sigtabgen object for plotting (filtering out NA Genus if present)
    if ("Genus" %in% colnames(sigtab)) {
      sigtabgen = subset(sigtab, !is.na(Genus))
    } else {
      sigtabgen = sigtab
    }
    
    # 6. Visualize the results using ggplot2
    p <- ggplot(sigtabgen, aes(y=Genus, x=log2FoldChange, color=Phylum)) + 
      geom_vline(xintercept = 0.0, color = "gray", size = 0.5) + 
      geom_point(size=6) + 
      theme(axis.text.x = element_text(angle = -90, hjust = 0, vjust=0.5))
    
    # 7. Save outputs to the working directory
    write.csv(as.data.frame(res), "deseq2_results_all.csv", row.names = TRUE)
    write.csv(as.data.frame(sigtab), "deseq2_results_significant.csv", row.names = TRUE)
    saveRDS(diagdds, "deseq2_dataset.rds")
    ggsave("differential_abundance_plot.pdf", plot = p, width = 12, height = 8)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2":
        phyloseq: \$(Rscript -e 'cat(as.character(packageVersion("phyloseq")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_abundance_deseq2.csv versions.yml
    """
}

workflow BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ phyloseq_object ] ]

    main:
    BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2(ch_input)

    emit:
    tables   = BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2.out.tables
    plots    = BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2.out.plots
    objects  = BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2.out.objects
    versions = BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2.out.versions
}
