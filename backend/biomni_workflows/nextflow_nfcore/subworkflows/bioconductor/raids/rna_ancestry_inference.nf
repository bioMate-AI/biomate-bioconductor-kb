#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: raids — rna_ancestry_inference
// Infer genetic ancestry from RNA sequencing data using gene-aware block annotations and profile-specific parameter optimization.
// Input: demoPedigreeEx1, studyDF, ex1_good_small_1KG.gds, ex1_good_small_1KG_Annot.gds, snpPileupRNA
// Container: quay.io/biocontainers/bioconductor-raids:1.8.0--r45hdfd78af_0
// R packages: RAIDS, SNPRelate, gdsfmt
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAIDS_RNA_ANCESTRY_INFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-raids:1.8.0--r45hdfd78af_0"

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
    .bm_deps <- c("RAIDS", "SNPRelate", "gdsfmt")
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
    library(RAIDS)
    library(gdsfmt)
    library(SNPRelate)
    
    # Helper function to read user input files robustly (supporting RDS or CSV)
    read_input_file <- function(base_name) {
      if (file.exists(base_name)) {
        tryCatch({
          return(readRDS(base_name))
        }, error = function(e) {
          tryCatch({
            return(read.csv(base_name, stringsAsFactors=FALSE))
          }, error = function(e2) {
            stop(paste("Could not read file:", base_name))
          })
        })
      }
      rds_path <- paste0(base_name, ".rds")
      if (file.exists(rds_path)) return(readRDS(rds_path))
      csv_path <- paste0(base_name, ".csv")
      if (file.exists(csv_path)) return(read.csv(csv_path, stringsAsFactors=FALSE))
      
      stop(paste("Required input file not found:", base_name))
    }
    
    # 1. Load pedigree information and study metadata
    demoPedigreeEx1 <- read_input_file("demoPedigreeEx1")
    studyDF <- read_input_file("studyDF")
    
    fileGDS <- "ex1_good_small_1KG.gds"
    fileAnnotGDS <- "ex1_good_small_1KG_Annot.gds"
    pathGeno <- "snpPileupRNA"
    
    # 2. Open reference GDS and select reference profiles using select1KGPop
    set.seed(3043)
    gds1KG <- snpgdsOpen(fileGDS)
    dataRef <- select1KGPop(gds1KG, nbProfiles=2L)
    closefn.gds(gds1KG)
    
    # Save selected reference profiles as an RDS object
    saveRDS(dataRef, "selected_reference_profiles.rds")
    
    # 3. Load chromosome length information from BSgenome
    if (requireNamespace("Seqinfo", quietly=TRUE) && requireNamespace("BSgenome.Hsapiens.UCSC.hg38", quietly=TRUE)) {
        chrInfo <- Seqinfo::seqlengths(BSgenome.Hsapiens.UCSC.hg38::Hsapiens)[1:25]
        
        pathProfileGDS <- file.path(getwd(), "exampleRNA", "outRNA.tmp")
        pathOut <- file.path(getwd(), "exampleRNA", "resRNA.out")
        
        if (!dir.exists(file.path(getwd(), "exampleRNA"))) {
            dir.create(file.path(getwd(), "exampleRNA"), recursive=TRUE)
        }
        if (!dir.exists(pathProfileGDS)) {
            dir.create(pathProfileGDS, recursive=TRUE)
        }
        if (!dir.exists(pathOut)) {
            dir.create(pathOut, recursive=TRUE)
        }
        
        # 4. Run RNA ancestry inference using runRNAAncestry with blockTypeID specified
        runRNAAncestry(
            pedStudy=demoPedigreeEx1, 
            studyDF=studyDF, 
            pathProfileGDS=pathProfileGDS, 
            pathGeno=pathGeno, 
            pathOut=pathOut, 
            fileReferenceGDS=fileGDS, 
            fileReferenceAnnotGDS=fileAnnotGDS, 
            chrInfo=chrInfo, 
            syntheticRefDF=dataRef, 
            blockTypeID="GeneS.Ensembl.Hsapiens.v86", 
            genoSource="VCF"
        )
        
        # 5. Read and inspect the output ancestry CSV file
        resAncestry <- read.csv(file.path(pathOut, paste0(demoPedigreeEx1\$Name.ID[1], ".Ancestry.csv")))
        print(resAncestry)
        
        # Write final output to working directory
        write.csv(resAncestry, "ancestry_results.csv", row.names=FALSE)
    } else {
        stop("Required packages 'Seqinfo' or 'BSgenome.Hsapiens.UCSC.hg38' are not available.")
    }

    writeLines(c(
        '"BIOC_RAIDS_RNA_ANCESTRY_INFERENCE":',
        paste0('        raids: ', as.character(packageVersion("raids")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_ancestry_inference.csv versions.yml
    """
}

workflow BIOC_RAIDS_RNA_ANCESTRY_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ demoPedigreeEx1, studyDF, ex1_good_small_1KG.gds, ex1_good_small_1KG_Annot.gds, snpPileupRNA ] ]

    main:
    BIOC_RAIDS_RNA_ANCESTRY_INFERENCE(ch_input)

    emit:
    tables   = BIOC_RAIDS_RNA_ANCESTRY_INFERENCE.out.tables
    plots    = BIOC_RAIDS_RNA_ANCESTRY_INFERENCE.out.plots
    objects  = BIOC_RAIDS_RNA_ANCESTRY_INFERENCE.out.objects
    versions = BIOC_RAIDS_RNA_ANCESTRY_INFERENCE.out.versions
}
