#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dagLogo — biomart_peptide_analysis
// Fetch peptide sequences from BioMart using gene identifiers and anchoring positions, build a background model, perform differential amino acid usage (DAU) testi
// Input: peptides4dagLogo.csv
// Container: quay.io/biocontainers/bioconductor-daglogo:1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: UniProt.ws, biomaRt, dagLogo
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Clean input peptides using cleanPeptides
//  * 2. [Input & Preparation] Fetch sequences from BioMart using fetchSequence
//  * 3. [Input & Preparation] Prepare a proteome background using prepareProteome
//  * 4. [Input & Preparation] Build a background model using buildBackgroundModel
//  * 5. [Core Analysis] Test for differential amino acid usage (DAU) using testDAU
//  * 6. [Visualization & Output] Visualize results using dagHeatmap and dagLogo

nextflow.enable.dsl = 2

process BIOC_DAGLOGO_BIOMART_PEPTIDE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("dagLogo", "biomaRt", "UniProt.ws")
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
    library(dagLogo)
    library(biomaRt)
    library(UniProt.ws)
    
    # 1. Read the input file from the working directory
    dat <- read.csv("peptides4dagLogo.csv")
    
    # 2. Clean input peptides using cleanPeptides
    dat <- unique(cleanPeptides(dat, anchors = c("s", "t")))
    
    # 3. Fetch sequences from BioMart using fetchSequence
    mart <- useMart("ensembl", "hsapiens_gene_ensembl")
    seq <- fetchSequence(toupper(as.character(dat\$symbol)), 
                         type="hgnc_symbol",
                         anchorAA=as.character(dat\$anchor),
                         anchorPos=as.character(dat\$peptides), 
                         mart=mart, 
                         upstreamOffset=7, 
                         downstreamOffset=7)
    
    # 4. Prepare a proteome background using prepareProteome
    proteome <- prepareProteome("UniProt", species = "Homo sapiens")
    
    # 5. Build a background model using buildBackgroundModel
    bg_ztest <- buildBackgroundModel(seq, background = "wholeProteome", 
                                     proteome = proteome, testType = "ztest")
    
    # 6. Test for differential amino acid usage (DAU) using testDAU
    t0 <- testDAU(seq, dagBackground = bg_ztest)
    
    # 7. Save the meaningful results to files
    saveRDS(t0, file = "dau_test_results.rds")
    
    # 8. Visualize results using dagHeatmap and dagLogo, saving to PDF
    pdf("dag_heatmap.pdf", width = 8, height = 6)
    dagHeatmap(t0)
    dev.off()
    
    pdf("dag_logo.pdf", width = 8, height = 6)
    dagLogo(t0)
    dev.off()

    writeLines(c(
        '"BIOC_DAGLOGO_BIOMART_PEPTIDE_ANALYSIS":',
        paste0('    dagLogo: ', as.character(packageVersion('dagLogo')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biomart_peptide_analysis.csv versions.yml
    """
}

workflow BIOC_DAGLOGO_BIOMART_PEPTIDE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peptides4dagLogo.csv ] ]

    main:
    BIOC_DAGLOGO_BIOMART_PEPTIDE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DAGLOGO_BIOMART_PEPTIDE_ANALYSIS.out.tables
    plots    = BIOC_DAGLOGO_BIOMART_PEPTIDE_ANALYSIS.out.plots
    objects  = BIOC_DAGLOGO_BIOMART_PEPTIDE_ANALYSIS.out.objects
    versions = BIOC_DAGLOGO_BIOMART_PEPTIDE_ANALYSIS.out.versions
}
