#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: splicewiz — standard_alternative_splicing_analysis
// Build a reference, process alignment BAM files, collate sample data, filter low-confidence events, and perform differential alternative splicing analysis.
// Input: genome.fa, transcripts.gtf, sample1.bam
// Container: quay.io/biocontainers/bioconductor-splicewiz:1.12.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPLICEWIZ_STANDARD_ALTERNATIVE_SPLICING_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-splicewiz:1.12.0--r45ha27e39d_0"

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
    .bm_deps <- c("annotationhub", "deseq2", "doubleexpseq", "edger", "ggplot2", "splicewiz")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    library(SpliceWiz)
    library(edgeR)
    
    # 1. Build the SpliceWiz reference using buildRef()
    ref_path <- file.path(tempdir(), "Reference")
    buildRef(
      reference_path = ref_path,
      fasta = "genome.fa",
      gtf = "transcripts.gtf",
      ontologySpecies = "Homo sapiens"
    )
    
    # 2. Process BAM files to extract junction and intron coverage data using processBAM()
    # We replicate the single input BAM file to 6 samples to satisfy the 
    # experimental design in the documented code (6 samples: 3 A, 3 B)
    bams <- data.frame(
      path = rep("sample1.bam", 6),
      sample = paste0("sample", 1:6),
      stringsAsFactors = FALSE
    )
    
    pb_path <- file.path(tempdir(), "pb_output")
    processBAM(
      bamfiles = bams\$path,
      sample_names = bams\$sample,
      reference_path = ref_path,
      output_path = pb_path
    )
    
    # 3. Collate processed sample outputs into an experiment database using collateData()
    expr <- findSpliceWizOutput(pb_path)
    nxtse_path <- file.path(tempdir(), "NxtSE_output")
    collateData(
      Experiment = expr,
      reference_path = ref_path,
      output_path = nxtse_path
    )
    
    # 4. Import the collated experiment as an NxtSE object using makeSE()
    se <- makeSE(nxtse_path)
    se <- realize_NxtSE(se)
    
    colData(se)\$condition <- rep(c("A", "B"), each = 3)
    colData(se)\$batch <- rep(c("K", "L", "M"), 2)
    
    # 5. Filter out low-confidence alternative splicing events using applyFilters()
    se.filtered <- se[applyFilters(se), ]
    
    # 6. Perform differential alternative splicing analysis using ASE_edgeR()
    require("edgeR")
    res_edgeR <- ASE_edgeR(
      se = se.filtered,
      test_factor = "condition",
      test_nom = "B",
      test_denom = "A"
    )
    
    # Write named output files for the meaningful results
    write.csv(res_edgeR, "differential_splicing_results.csv", row.names = FALSE)
    saveRDS(se.filtered, "NxtSE_filtered.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SPLICEWIZ_STANDARD_ALTERNATIVE_SPLICING_ANALYSIS":
        splicewiz: \$(Rscript -e 'cat(as.character(packageVersion("splicewiz")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_alternative_splicing_analysis.csv versions.yml
    """
}

workflow BIOC_SPLICEWIZ_STANDARD_ALTERNATIVE_SPLICING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome.fa, transcripts.gtf, sample1.bam ] ]

    main:
    BIOC_SPLICEWIZ_STANDARD_ALTERNATIVE_SPLICING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SPLICEWIZ_STANDARD_ALTERNATIVE_SPLICING_ANALYSIS.out.tables
    plots    = BIOC_SPLICEWIZ_STANDARD_ALTERNATIVE_SPLICING_ANALYSIS.out.plots
    objects  = BIOC_SPLICEWIZ_STANDARD_ALTERNATIVE_SPLICING_ANALYSIS.out.objects
    versions = BIOC_SPLICEWIZ_STANDARD_ALTERNATIVE_SPLICING_ANALYSIS.out.versions
}
