#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: traseR — gwas_snp_enrichment_analysis
// Perform enrichment analysis of trait-associated SNPs in genomic intervals and explore/visualize the results.
// Input: genomic_intervals.csv
// Container: quay.io/biocontainers/bioconductor-traser:1.40.0--r45hdfd78af_0
// R packages: traseR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRASER_GWAS_SNP_ENRICHMENT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-traser:1.40.0--r45hdfd78af_0"

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
    .bm_deps <- c("traseR")
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
    
    # Load the required package
    library(traseR)
    
    # Retrieve the built-in databases from the package namespace/environment
    # without using the forbidden data() function
    taSNP <- get("taSNP")
    taSNPLD <- get("taSNPLD")
    CEU <- get("CEU")
    
    # Read the user-provided genomic intervals
    Tcell <- read.csv("genomic_intervals.csv", stringsAsFactors = FALSE)
    
    # Ensure the columns are correctly named for traseR compatibility
    colnames(Tcell)[1:3] <- c("chr", "start", "end")
    
    # 1. Run enrichment analysis using traseR with default background
    x=traseR(taSNP,Tcell)
    print(x)
    saveRDS(x, "traseR_results_default.rds")
    
    # 2. Run enrichment analysis using traseR with LD SNPs
    x=traseR(snpdb=taSNPLD,region=Tcell)
    print(x)
    saveRDS(x, "traseR_results_LD.rds")
    
    # 3. Run enrichment analysis using traseR with CEU background
    x=traseR(snpdb=taSNP,region=Tcell,snpdb.bg=CEU)
    print(x)
    saveRDS(x, "traseR_results_CEU.rds")
    
    # 4. Visualize SNP functional class distribution using plotContext
    pdf("plot_context.pdf")
    plotContext(snpdb=taSNP,region=Tcell,keyword="Autoimmune")
    dev.off()
    
    # 5. Visualize p-value distribution using plotPvalue
    pdf("plot_pvalue.pdf")
    plotPvalue(snpdb=taSNP,region=Tcell,keyword="autoimmune",plot.type="densityplot")
    dev.off()
    
    # 6. Plot SNPs/genes in a specific genomic interval using plotInterval
    pdf("plot_interval.pdf")
    plotInterval(snpdb=taSNP,data.frame(chr="chrX",start=152633780,end=152737085))
    dev.off()
    
    # 7. Query the database by keyword, gene, or SNP ID
    x=queryKeyword(snpdb=taSNP,region=Tcell,keyword="autoimmune",returnby="SNP")
    print(head(x))
    write.csv(x, "query_keyword_results.csv", row.names = FALSE)
    
    x=queryGene(snpdb=taSNP,genes=c("AGRN","UBE2J2","SSU72"))
    print(x)
    saveRDS(x, "query_gene_results.rds")
    write.csv(as.data.frame(x), "query_gene_results.csv", row.names = FALSE)
    
    x=querySNP(snpdb=taSNP,snpid=c("rs3766178","rs880051"))
    print(x)
    saveRDS(x, "query_snp_results.rds")
    write.csv(as.data.frame(x), "query_snp_results.csv", row.names = FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_TRASER_GWAS_SNP_ENRICHMENT_ANALYSIS":
        traseR: \$(Rscript -e 'cat(as.character(packageVersion("traseR")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gwas_snp_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_TRASER_GWAS_SNP_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genomic_intervals.csv ] ]

    main:
    BIOC_TRASER_GWAS_SNP_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TRASER_GWAS_SNP_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_TRASER_GWAS_SNP_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_TRASER_GWAS_SNP_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_TRASER_GWAS_SNP_ENRICHMENT_ANALYSIS.out.versions
}
