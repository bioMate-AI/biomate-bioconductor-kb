#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: quasr — chip_seq_workflow
// Align single-end ChIP-seq reads, perform quality control, export coverage tracks, and quantify alignments at promoters and TSS profiles.
// Input: samples_chip_single.txt, hg19sub.fa, auxiliaries.txt, hg19sub_annotation.gtf
// Container: quay.io/biocontainers/bioconductor-quasr:1.50.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QUASR_CHIP_SEQ_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-quasr:1.50.0--r45ha27e39d_0"

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
    .bm_deps <- c("Rsamtools", "biocmanager", "biostrings", "bsgenome", "genomicfeatures", "gviz", "quasr", "rtracklayer", "txdbmaker")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(QuasR)
    library(Rsamtools)
    library(rtracklayer)
    library(GenomicFeatures)
    library(txdbmaker)
    
    # Define input files from the working directory
    sampleFile <- "samples_chip_single.txt"
    auxFile <- "auxiliaries.txt"
    genomeFile <- "hg19sub.fa"
    annotFile <- "hg19sub_annotation.gtf"
    annotationFile <- "hg19sub_annotation.gtf"
    
    # 1. Align reads to genome and auxiliary targets using qAlign
    proj1 <- qAlign(sampleFile, genome = genomeFile, auxiliaryFile = auxFile)
    print(proj1)
    
    # 2. Generate quality control report using qQCReport
    qQCReport(proj1, pdfFilename = "qc_report.pdf")
    
    # 3. Retrieve alignment statistics using alignmentStats
    stats <- alignmentStats(proj1)
    print(stats)
    write.csv(stats, "alignment_stats.csv", row.names = TRUE)
    
    # 4. Export coverage tracks to wiggle format using qExportWig
    qExportWig(proj1, binsize = 100L, scaling = TRUE, collapseBySample = TRUE)
    
    # 5. Quantify promoter region counts using qCount
    chrLen <- scanFaIndex(genomeFile)
    chrominfo <- data.frame(chrom = as.character(seqnames(chrLen)),
                            length = width(chrLen),
                            is_circular = rep(FALSE, length(chrLen)))
    
    txdb <- makeTxDbFromGFF(file = annotFile, format = "gtf",
                            chrominfo = chrominfo,
                            dataSource = "Ensembl",
                            organism = "Homo sapiens")
    
    promReg <- promoters(txdb, upstream = 1000, downstream = 500,
                         columns = c("gene_id","tx_id"))
    
    gnId <- vapply(mcols(promReg)\$gene_id,
                   FUN = paste, FUN.VALUE = "",
                   collapse = ",")
    
    promRegSel <- promReg[ match(unique(gnId), gnId) ]
    names(promRegSel) <- unique(gnId)
    
    cnt <- qCount(proj1, promRegSel)
    print(cnt)
    write.csv(cnt, "promoter_counts.csv", row.names = TRUE)
    
    # 6. Calculate average alignment profiles around TSS using qProfile
    tssRegions <- import.gff(annotationFile, format = "gtf",
                             feature.type = "start_codon",
                             colnames = "gene_name")
    tssRegions <- tssRegions[!duplicated(tssRegions)]
    names(tssRegions) <- rep("TSS", length(tssRegions))
    
    prS <- qProfile(proj1, tssRegions, upstream = 3000, downstream = 3000, 
                    orientation = "same")
    prO <- qProfile(proj1, tssRegions, upstream = 3000, downstream = 3000, 
                    orientation = "opposite")
    
    # Save profile results
    saveRDS(prS, "profile_same.rds")
    saveRDS(prO, "profile_opposite.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_QUASR_CHIP_SEQ_WORKFLOW":
        quasr: \$(Rscript -e 'cat(as.character(packageVersion("quasr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chip_seq_workflow.csv versions.yml
    """
}

workflow BIOC_QUASR_CHIP_SEQ_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ samples_chip_single.txt, hg19sub.fa, auxiliaries.txt, hg19sub_annotation.gtf ] ]

    main:
    BIOC_QUASR_CHIP_SEQ_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_QUASR_CHIP_SEQ_WORKFLOW.out.tables
    plots    = BIOC_QUASR_CHIP_SEQ_WORKFLOW.out.plots
    objects  = BIOC_QUASR_CHIP_SEQ_WORKFLOW.out.objects
    versions = BIOC_QUASR_CHIP_SEQ_WORKFLOW.out.versions
}
