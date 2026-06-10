#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: generegionscan — analyze_and_visualize_probe_level_data
// Plot probe-level expression along a gene, test for group differences, and analyze coexpression.
// Input: exampleProbeLevelSet, mrna, genomic
// Container: quay.io/biocontainers/bioconductor-generegionscan:1.66.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEREGIONSCAN_ANALYZE_AND_VISUALIZE_PROBE_LEVEL_DATA {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-generegionscan:1.66.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biobase", "Biostrings", "GeneRegionScan")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(GeneRegionScan)
    library(Biobase)
    library(Biostrings)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read exampleProbeLevelSet (ProbeLevelSet object)
    if (file.exists("exampleProbeLevelSet.rds")) {
      exampleProbeLevelSet <- readRDS("exampleProbeLevelSet.rds")
    } else if (file.exists("exampleProbeLevelSet")) {
      exampleProbeLevelSet <- readRDS("exampleProbeLevelSet")
    } else {
      stop("Error: 'exampleProbeLevelSet' file not found in the working directory.")
    }
    
    # Read mrna (mRNA sequence as DNAStringSet)
    if (file.exists("mrna.rds")) {
      mrna <- readRDS("mrna.rds")
    } else if (file.exists("mrna.fa")) {
      mrna <- Biostrings::readDNAStringSet("mrna.fa")
    } else if (file.exists("mrna.fasta")) {
      mrna <- Biostrings::readDNAStringSet("mrna.fasta")
    } else if (file.exists("mrna")) {
      mrna <- tryCatch(
        readRDS("mrna"),
        error = function(e) Biostrings::readDNAStringSet("mrna")
      )
    } else {
      stop("Error: 'mrna' file not found in the working directory.")
    }
    
    # Read genomic (genomic sequence with one FASTA entry per exon)
    if (file.exists("genomic.rds")) {
      genomic <- readRDS("genomic.rds")
    } else if (file.exists("genomic.fa")) {
      genomic <- Biostrings::readDNAStringSet("genomic.fa")
    } else if (file.exists("genomic.fasta")) {
      genomic <- Biostrings::readDNAStringSet("genomic.fasta")
    } else if (file.exists("genomic")) {
      genomic <- tryCatch(
        readRDS("genomic"),
        error = function(e) Biostrings::readDNAStringSet("genomic")
      )
    } else {
      stop("Error: 'genomic' file not found in the working directory.")
    }
    
    # ==========================================
    # 2. Execute Workflow & Save Outputs
    # ==========================================
    
    # Preview and save pData
    pdata_preview <- pData(exampleProbeLevelSet)[1:3,]
    write.csv(pdata_preview, "pdata_preview.csv", row.names = TRUE)
    
    # Stage 1: Plot median probe expression along the gene
    pdf("plot_basic.pdf", width = 8, height = 6)
    plotOnGene(exampleProbeLevelSet, mrna)
    dev.off()
    
    # Stage 2 & 3: Zoom in on specific intervals and display individual sample dots with exon structure
    pdf("plot_dots_exon.pdf", width = 8, height = 6)
    plotOnGene(exampleProbeLevelSet, mrna, summaryType="dots", interval=c(500,1000))
    exonStructure(mrna, genomic)
    dev.off()
    
    # Stage 4: Test for group differences (Wilcoxon) and highlight significant probes
    pdf("plot_gender_exon.pdf", width = 8, height = 6)
    plotOnGene(exampleProbeLevelSet, mrna, label="gender", testType="wilcoxon", verbose=FALSE)
    exonStructure(mrna, genomic)
    dev.off()
    
    # Stage 4 (cont.): Test for group differences (Linear Model) and highlight significant probes
    pdf("plot_genotype1_exon.pdf", width = 8, height = 6)
    plotOnGene(exampleProbeLevelSet, mrna, label="genotype1", testType="linear model", verbose=FALSE)
    exonStructure(mrna, genomic)
    dev.off()
    
    # Stage 5: Analyze probe coexpression
    mrna_subset<-mrna[[1]]
    mrna_subset<-mrna_subset[500:1000]
    
    pdf("plot_coexpression.pdf", width = 8, height = 8)
    plotCoexpression(exampleProbeLevelSet, gene=mrna_subset, correlationCutoff=0.5, probeLevelInfo=c("probeid","sequence"), verbose=FALSE)
    dev.off()
    
    # Stage 6: Perform a comprehensive region scan across multiple genes
    pdf("gene_region_scan.pdf", width = 10, height = 8)
    geneRegionScan(exampleProbeLevelSet, gene=mrna, genomicData=genomic, label="genotype3", testType="linear model", correlationCutoff=0.5, probeLevelInfo=c("probeid","sequence"), verbose=FALSE)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GENEREGIONSCAN_ANALYZE_AND_VISUALIZE_PROBE_LEVEL_DATA":
        generegionscan: \$(Rscript -e 'cat(as.character(packageVersion("generegionscan")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_analyze_and_visualize_probe_level_data.csv versions.yml
    """
}

workflow BIOC_GENEREGIONSCAN_ANALYZE_AND_VISUALIZE_PROBE_LEVEL_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exampleProbeLevelSet, mrna, genomic ] ]

    main:
    BIOC_GENEREGIONSCAN_ANALYZE_AND_VISUALIZE_PROBE_LEVEL_DATA(ch_input)

    emit:
    tables   = BIOC_GENEREGIONSCAN_ANALYZE_AND_VISUALIZE_PROBE_LEVEL_DATA.out.tables
    plots    = BIOC_GENEREGIONSCAN_ANALYZE_AND_VISUALIZE_PROBE_LEVEL_DATA.out.plots
    objects  = BIOC_GENEREGIONSCAN_ANALYZE_AND_VISUALIZE_PROBE_LEVEL_DATA.out.objects
    versions = BIOC_GENEREGIONSCAN_ANALYZE_AND_VISUALIZE_PROBE_LEVEL_DATA.out.versions
}
