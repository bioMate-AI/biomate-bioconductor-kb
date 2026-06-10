#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SpliceWiz — novel_splicing_analysis
// Detect and analyze novel alternative splicing events by enabling novel splicing detection during collation.
// Input: genome.fa, transcripts.gtf, sample1.bam
// Container: quay.io/biocontainers/bioconductor-splicewiz:1.12.0--r45ha27e39d_0
// Requires: SpliceWiz
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build reference using buildRef()
//  * 2. [Core Analysis] Process BAM files using processBAM()
//  * 3. [Visualization & Output] Find processed outputs using findSpliceWizOutput()
//  * 4. [Core Analysis] Collate data with novel splicing enabled using collateData(..., novelSplicing = TRUE)
//  * 5. [Input & Preparation] Import collated data as NxtSE using makeSE()

nextflow.enable.dsl = 2

process BIOC_SPLICEWIZ_NOVEL_SPLICING_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("SpliceWiz")
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
        
        library(SpliceWiz)
        
        # 1. Build reference using buildRef()
        ref_path <- file.path(getwd(), "Reference")
        buildRef(
          reference_path = ref_path,
          fasta = "genome.fa",
          gtf = "transcripts.gtf",
          ontologySpecies = "Homo sapiens"
        )
        
        # 2. Process BAM files using processBAM()
        bams <- data.frame(
          path = "sample1.bam",
          sample = "sample1",
          stringsAsFactors = FALSE
        )
        
        pb_path <- file.path(getwd(), "pb_output")
        processBAM(
          bamfiles = bams\$path,
          sample_names = bams\$sample,
          reference_path = ref_path,
          output_path = pb_path
        )
        
        # 3. Find processed outputs using findSpliceWizOutput()
        expr <- findSpliceWizOutput(pb_path)
        
        # 4. Collate data with novel splicing enabled using collateData()
        nxtse_path <- file.path(getwd(), "NxtSE_output_novel")
        collateData(
          Experiment = expr,
          reference_path = ref_path,
          output_path = nxtse_path,
          novelSplicing = TRUE,
          novelSplicing_requireOneAnnotatedSJ = TRUE,
          novelSplicing_minSamples = 1,
          novelSplicing_minSamplesAboveThreshold = 1,
          novelSplicing_countThreshold = 10,
          novelSplicing_useTJ = TRUE
        )
        
        # 5. Import collated data as NxtSE using makeSE()
        se <- makeSE(nxtse_path)
        
        # Save outputs
        saveRDS(se, "NxtSE_novel.rds")
        
        # Export ASE events table
        ase_events <- as.data.frame(rowData(se))
        write.csv(ase_events, "novel_splicing_ASE_events.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SPLICEWIZ_NOVEL_SPLICING_ANALYSIS":',
        paste0('    SpliceWiz: ', as.character(packageVersion('SpliceWiz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_novel_splicing_analysis.csv versions.yml
    """
}

workflow BIOC_SPLICEWIZ_NOVEL_SPLICING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome.fa, transcripts.gtf, sample1.bam ] ]

    main:
    BIOC_SPLICEWIZ_NOVEL_SPLICING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SPLICEWIZ_NOVEL_SPLICING_ANALYSIS.out.tables
    plots    = BIOC_SPLICEWIZ_NOVEL_SPLICING_ANALYSIS.out.plots
    objects  = BIOC_SPLICEWIZ_NOVEL_SPLICING_ANALYSIS.out.objects
    versions = BIOC_SPLICEWIZ_NOVEL_SPLICING_ANALYSIS.out.versions
}
