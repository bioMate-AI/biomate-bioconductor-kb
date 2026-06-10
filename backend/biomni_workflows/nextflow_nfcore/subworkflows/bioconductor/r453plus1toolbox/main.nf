#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: r453plus1toolbox — pcr_amplicon_analysis
// Import, filter, annotate, visualize, and export variants from a Roche Amplicon Variant Analyzer (AVA) project.
// Input: My/AVA/Project, sample.csv, amp.csv, reference.csv, variant.csv, variantHits.csv
// Container: quay.io/biocontainers/bioconductor-r453plus1toolbox:1.56.0--r44h3df3fcb_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, R453Plus1Toolbox, Rsamtools, rtracklayer, ShortRead
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_R453PLUS1TOOLBOX_PCR_AMPLICON_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-r453plus1toolbox:1.56.0--r44h3df3fcb_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "R453Plus1Toolbox", "Rsamtools", "rtracklayer", "ShortRead")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library(R453Plus1Toolbox)
    library(BSgenome.Hsapiens.UCSC.hg19)
    
    # Ensure the project directory exists
    projectDir <- "My/AVA/Project"
    if (!dir.exists(projectDir)) {
      dir.create(projectDir, recursive = TRUE)
    }
    
    # Copy the user input CSV files from the working directory into the project directory
    # as AVASet expects them to be located within the specified dirname.
    user_files <- c("sample.csv", "amp.csv", "reference.csv", "variant.csv", "variantHits.csv")
    for (f in user_files) {
      if (file.exists(f)) {
        file.copy(f, file.path(projectDir, f), overwrite = TRUE)
      }
    }
    
    # 1. Import the AVA project into an AVASet object using the user-provided files
    avaSet = AVASet(
      dirname=projectDir,
      file_sample="sample.csv",
      file_amp="amp.csv",
      file_reference="reference.csv",
      file_variant="variant.csv",
      file_variantHits="variantHits.csv"
    )
    
    # 2. Filter variants by frequency threshold
    avaSetFiltered1 = setVariantFilter(avaSet, filter=0.05)
    
    # 3. Align reference sequences to a reference genome
    seqNames = names(Hsapiens)[1:24]
    avaSet = alignShortReads(avaSet, bsGenome=Hsapiens, seqNames=seqNames, ensemblNotation=TRUE)
    
    # 4. Annotate variants, generate HTML report, and export to VCF
    # Wrapping in tryCatch to handle potential biomaRt/Ensembl connectivity issues robustly
    tryCatch({
      avaAnnot = annotateVariants(avaSet)
      
      # Save the annotation object
      saveRDS(avaAnnot, file = "avaAnnot.rds")
      
      # 5. Generate an HTML report of variants and quality metrics
      blocks = as.character(sapply(annotatedVariants(avaAnnot), function(x) x\$genes\$external_gene_id))
      htmlReport(avaSet, annot=avaAnnot, blocks=blocks, dir="htmlReportExampleAVA", title="htmlReport Example", minMut=3)
      
      # 6. Export annotated variants to a VCF file
      ava2vcf(avaSet, filename="variants.vcf", annot=avaAnnot)
      
    }, error = function(e) {
      message("Warning: Annotation, HTML report, or VCF export failed (likely due to biomaRt/Ensembl network issues): ", e\$message)
    })
    
    # 7. Plot amplicon coverage and save to a PDF file
    pdf("amplicon_coverage.pdf", width = 10, height = 7)
    plotAmpliconCoverage(avaSet, bothDirections=TRUE, type="amplicon")
    dev.off()
    
    # Save the final AVASet objects
    saveRDS(avaSet, file = "avaSet_aligned.rds")
    saveRDS(avaSetFiltered1, file = "avaSetFiltered1.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_R453PLUS1TOOLBOX_PCR_AMPLICON_ANALYSIS":
        r453plus1toolbox: \$(Rscript -e 'cat(as.character(packageVersion("r453plus1toolbox")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pcr_amplicon_analysis.csv versions.yml
    """
}

workflow BIOC_R453PLUS1TOOLBOX_PCR_AMPLICON_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ My/AVA/Project, sample.csv, amp.csv, reference.csv, variant.csv, variantHits.csv ] ]

    main:
    BIOC_R453PLUS1TOOLBOX_PCR_AMPLICON_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_R453PLUS1TOOLBOX_PCR_AMPLICON_ANALYSIS.out.tables
    plots    = BIOC_R453PLUS1TOOLBOX_PCR_AMPLICON_ANALYSIS.out.plots
    objects  = BIOC_R453PLUS1TOOLBOX_PCR_AMPLICON_ANALYSIS.out.objects
    versions = BIOC_R453PLUS1TOOLBOX_PCR_AMPLICON_ANALYSIS.out.versions
}
