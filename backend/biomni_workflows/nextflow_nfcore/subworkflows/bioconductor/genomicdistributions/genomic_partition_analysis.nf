#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenomicDistributions — genomic_partition_analysis
// Calculate and visualize how genomic ranges overlap with genomic partitions (promoters, exons, introns, intergenic, etc.) using percentage, expected, and cumulat
// Input: queryFile.bed
// Container: quay.io/biocontainers/bioconductor-genomicdistributions:1.18.0--r45hdfd78af_0
// Requires: GenomeInfoDb, GenomicDistributions, GenomicRanges, biomaRt, ggplot2, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import query genomic ranges
//  * 2. [Core Analysis] Calculate percentage partition overlaps using calcPartitionsRef
//  * 3. [Visualization & Output] Plot percentage partitions using plotPartitions
//  * 4. [Core Analysis] Calculate expected partition overlaps using calcExpectedPartitionsRef
//  * 5. [Visualization & Output] Plot expected partitions using plotExpectedPartitions
//  * 6. [Core Analysis] Calculate cumulative partition distributions using calcCumulativePartitionsRef
//  * 7. [Visualization & Output] Plot cumulative partitions using plotCumulativePartitions
//  * 8. [Input & Preparation] Build custom partition list using getGeneModels and genomePartitionList and run custom partition calculations using calcPartitions

nextflow.enable.dsl = 2

process BIOC_GENOMICDISTRIBUTIONS_GENOMIC_PARTITION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("GenomeInfoDb", "GenomicDistributions", "GenomicRanges", "biomaRt", "ggplot2", "rtracklayer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library("GenomicDistributions")
    library("rtracklayer")
    library("GenomicRanges")
    library("GenomeInfoDb")
    library("ggplot2")
    
    # 1. Import query genomic ranges
    queryFile = "queryFile.bed"
    if (!file.exists(queryFile)) {
      stop("Error: 'queryFile.bed' not found in the working directory.")
    }
    
    query = rtracklayer::import(queryFile)
    query2 = GenomicRanges::shift(query, 1e6)
    queryList = GRangesList(vistaEnhancers=query, shifted=query2)
    
    # 2. Calculate percentage partition overlaps using calcPartitionsRef
    gp = calcPartitionsRef(query, "hg19")
    gp2 = calcPartitionsRef(queryList, "hg19")
    gp3 = calcPartitionsRef(queryList, "hg19", bpProportion=TRUE)
    
    # Save calculated partitions to CSV
    write.csv(as.data.frame(gp), "gp_partitions.csv", row.names=FALSE)
    write.csv(as.data.frame(gp2), "gp2_partitions_list.csv", row.names=FALSE)
    write.csv(as.data.frame(gp3), "gp3_partitions_list_bpProp.csv", row.names=FALSE)
    
    # 3. Plot percentage partitions using plotPartitions
    pdf("plots_partitions.pdf", width=8, height=6)
    p1 = plotPartitions(gp)
    print(p1)
    p2 = plotPartitions(gp2)
    print(p2)
    p3 = plotPartitions(gp2, numbers=TRUE)
    print(p3)
    p4 = plotPartitions(gp3)
    print(p4)
    dev.off()
    
    # 4. Calculate expected partition overlaps using calcExpectedPartitionsRef
    ep = calcExpectedPartitionsRef(query, "hg19")
    ep2 = calcExpectedPartitionsRef(queryList, "hg19")
    ep3 = calcExpectedPartitionsRef(queryList, "hg19", bpProportion=TRUE)
    
    # Save expected partitions to CSV
    write.csv(as.data.frame(ep), "ep_expected_partitions.csv", row.names=FALSE)
    write.csv(as.data.frame(ep2), "ep2_expected_partitions_list.csv", row.names=FALSE)
    write.csv(as.data.frame(ep3), "ep3_expected_partitions_list_bpProp.csv", row.names=FALSE)
    
    # 5. Plot expected partitions using plotExpectedPartitions
    pdf("plots_expected_partitions.pdf", width=8, height=6)
    pe1 = plotExpectedPartitions(ep)
    print(pe1)
    pe2 = plotExpectedPartitions(ep2)
    print(pe2)
    pe3 = plotExpectedPartitions(ep2, pval=TRUE)
    print(pe3)
    pe4 = plotExpectedPartitions(ep3)
    print(pe4)
    dev.off()
    
    # 6. Calculate cumulative partition distributions using calcCumulativePartitionsRef
    cp = calcCumulativePartitionsRef(query, "hg19")
    cp2 = calcCumulativePartitionsRef(queryList, "hg19")
    
    # Save cumulative partitions to CSV
    write.csv(as.data.frame(cp), "cp_cumulative_partitions.csv", row.names=FALSE)
    write.csv(as.data.frame(cp2), "cp2_cumulative_partitions_list.csv", row.names=FALSE)
    
    # 7. Plot cumulative partitions using plotCumulativePartitions
    pdf("plots_cumulative_partitions.pdf", width=8, height=6)
    pc1 = plotCumulativePartitions(cp)
    print(pc1)
    pc2 = plotCumulativePartitions(cp2)
    print(pc2)
    dev.off()
    
    # 8. Build custom partition list using getGeneModels and genomePartitionList and run custom partition calculations using calcPartitions
    tryCatch({
      library("biomaRt")
      funcgen = biomaRt::useMart("ENSEMBL_MART_FUNCGEN", host="grch37.ensembl.org")
      funcgen = biomaRt::useDataset("hsapiens_regulatory_feature", mart=funcgen)
      enhancers = biomaRt::getBM(attributes=c('chromosome_name', 'chromosome_start', 'chromosome_end', 'feature_type_name'), 
                                 filters='regulatory_feature_type_name', 
                                 values='Enhancer', 
                                 mart=funcgen)
      enhancers\$chromosome_name = paste("chr", enhancers\$chromosome_name, sep="")
      gr1 = GenomicRanges::sort(GenomeInfoDb::sortSeqlevels(GenomicDistributions::dtToGr(enhancers, chr="chromosome_name", start="chromosome_start", end="chromosome_end")))
      
      geneModels = GenomicDistributions::getGeneModels("hg19")
      partitionList = GenomicDistributions::genomePartitionList(geneModels\$genesGR, geneModels\$exonsGR, geneModels\$threeUTRGR, geneModels\$fiveUTRGR)
      partitionList[["enhancer"]] = gr1
      
      perc3 = calcPartitions(queryList, partitionList)
      write.csv(as.data.frame(perc3), "perc3_custom_partitions.csv", row.names=FALSE)
      
      pdf("plots_custom_partitions.pdf", width=8, height=6)
      p_custom = plotPartitions(perc3)
      print(p_custom)
      dev.off()
    }, error = function(e) {
      message("Warning: Custom partition analysis with biomaRt failed. Error message:")
      message(e)
    })

    writeLines(c(
        '"BIOC_GENOMICDISTRIBUTIONS_GENOMIC_PARTITION_ANALYSIS":',
        paste0('    GenomicDistributions: ', as.character(packageVersion('GenomicDistributions')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_partition_analysis.csv versions.yml
    """
}

workflow BIOC_GENOMICDISTRIBUTIONS_GENOMIC_PARTITION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ queryFile.bed ] ]

    main:
    BIOC_GENOMICDISTRIBUTIONS_GENOMIC_PARTITION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GENOMICDISTRIBUTIONS_GENOMIC_PARTITION_ANALYSIS.out.tables
    plots    = BIOC_GENOMICDISTRIBUTIONS_GENOMIC_PARTITION_ANALYSIS.out.plots
    objects  = BIOC_GENOMICDISTRIBUTIONS_GENOMIC_PARTITION_ANALYSIS.out.objects
    versions = BIOC_GENOMICDISTRIBUTIONS_GENOMIC_PARTITION_ANALYSIS.out.versions
}
