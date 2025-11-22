# 1000-Scenario Test Results - V5 Detection Logic

**Date:** 2025-11-07T16:52:34.438Z
**Pass Rate:** 84.40%
**Passed:** 844/1000

## By Use Case

- RNA-seq Bulk: 27/34 (79.4%)
- Proteomics DIA: 29/34 (85.3%)
- Single-cell RNA: 29/34 (85.3%)
- scATAC-seq: 29/34 (85.3%)
- Multimodal SC: 29/34 (85.3%)
- Spatial Transcriptomics: 28/34 (82.4%)
- Spatial Proteomics: 29/34 (85.3%)
- Imaging MS: 29/34 (85.3%)
- Short-read Metagenomics: 29/34 (85.3%)
- Nanopore Metagenomics: 29/34 (85.3%)
- PacBio Metagenomics: 29/34 (85.3%)
- Clinical LIS: 29/34 (85.3%)
- Clinical Diagnostics: 29/34 (85.3%)
- Germline Variants: 29/34 (85.3%)
- Somatic Variants: 29/34 (85.3%)
- Copy Number Variants: 29/34 (85.3%)
- Structural Variants: 29/34 (85.3%)
- Epigenomics: 29/34 (85.3%)
- Metabolomics: 29/34 (85.3%)
- Multi-omics: 28/34 (82.4%)
- Drug Discovery: 27/32 (84.4%)
- Synthetic Biology: 26/32 (81.3%)
- Agricultural Genomics: 27/32 (84.4%)
- Environmental Meta: 27/32 (84.4%)
- Patient Monitoring: 29/32 (90.6%)
- EMR Integration: 27/32 (84.4%)
- Core Facility: 25/32 (78.1%)
- Pharmacogenomics: 27/32 (84.4%)
- Microbiome Functional: 27/32 (84.4%)
- Cloud/HPC: 26/32 (81.3%)

## By Expertise

- beginner: 292/300 (97.3%)
- intermediate: 354/420 (84.3%)
- expert: 198/280 (70.7%)

## By Expected Mode

- iterative: 425/560 (75.9%)
- legacy: 419/440 (95.2%)

## All Failures (156)


### 1. [RNA-seq Bulk] beginner - Quick analysis
- **Query:** "Quick differential expression with Salmon"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Complex query


### 2. [RNA-seq Bulk] beginner - Run tool
- **Query:** "Run fastp for differential expression"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Complex query


### 3. [RNA-seq Bulk] intermediate - Intermediate need
- **Query:** "I need to fusion detection for RNA-seq Bulk"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 4. [RNA-seq Bulk] intermediate - Quick analysis
- **Query:** "Quick isoform analysis with fastp"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Low confidence (0.70)


### 5. [RNA-seq Bulk] intermediate - Run tool
- **Query:** "Run Kallisto for isoform analysis"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Analysis request


### 6. [RNA-seq Bulk] expert - Expert optimization
- **Query:** "Optimize edgeR parameters for fusion detection with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 7. [RNA-seq Bulk] expert - Quick analysis
- **Query:** "Quick differential expression with edgeR"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Complex query


### 8. [Proteomics DIA] intermediate - Intermediate need
- **Query:** "I need to protein inference for Proteomics DIA"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 9. [Proteomics DIA] intermediate - Intermediate need
- **Query:** "I need to DIA quantification for Proteomics DIA"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 10. [Proteomics DIA] expert - Standard workflow
- **Query:** "Generate standard DIA quantification workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 11. [Proteomics DIA] expert - Expert optimization
- **Query:** "Optimize quantms parameters for protein inference with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 12. [Proteomics DIA] expert - Intermediate need
- **Query:** "I need to spectral library for Proteomics DIA"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 13. [Single-cell RNA] intermediate - Intermediate need
- **Query:** "I need to trajectory for Single-cell RNA"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 14. [Single-cell RNA] intermediate - Intermediate need
- **Query:** "I need to clustering for Single-cell RNA"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 15. [Single-cell RNA] expert - Standard workflow
- **Query:** "Generate standard clustering workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 16. [Single-cell RNA] expert - Expert optimization
- **Query:** "Optimize Scanpy parameters for trajectory with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 17. [Single-cell RNA] expert - Intermediate need
- **Query:** "I need to cell type annotation for Single-cell RNA"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 18. [scATAC-seq] intermediate - Intermediate need
- **Query:** "I need to chromatin for scATAC-seq"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 19. [scATAC-seq] intermediate - Intermediate need
- **Query:** "I need to peak calling for scATAC-seq"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 20. [scATAC-seq] expert - Standard workflow
- **Query:** "Generate standard peak calling workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 21. [scATAC-seq] expert - Expert optimization
- **Query:** "Optimize Scanpy parameters for chromatin with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 22. [scATAC-seq] expert - Intermediate need
- **Query:** "I need to motif enrichment for scATAC-seq"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 23. [Multimodal SC] intermediate - Intermediate need
- **Query:** "I need to cross-modal for Multimodal SC"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 24. [Multimodal SC] intermediate - Intermediate need
- **Query:** "I need to RNA+ATAC integration for Multimodal SC"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 25. [Multimodal SC] expert - Standard workflow
- **Query:** "Generate standard RNA+ATAC integration workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 26. [Multimodal SC] expert - Expert optimization
- **Query:** "Optimize 10X Multiome parameters for cross-modal with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 27. [Multimodal SC] expert - Intermediate need
- **Query:** "I need to WNN for Multimodal SC"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 28. [Spatial Transcriptomics] intermediate - Intermediate need
- **Query:** "I need to cell-cell interaction for Spatial Transcriptomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 29. [Spatial Transcriptomics] intermediate - Quick analysis
- **Query:** "Quick niche analysis with MERFISH"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Low confidence (0.70)


### 30. [Spatial Transcriptomics] intermediate - Run tool
- **Query:** "Run Visium for niche analysis"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Analysis request


### 31. [Spatial Transcriptomics] intermediate - Intermediate need
- **Query:** "I need to spatial clustering for Spatial Transcriptomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 32. [Spatial Transcriptomics] expert - Standard workflow
- **Query:** "Generate standard spatial clustering workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 33. [Spatial Transcriptomics] expert - Expert optimization
- **Query:** "Optimize seqFISH parameters for cell-cell interaction with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 34. [Spatial Proteomics] intermediate - Intermediate need
- **Query:** "I need to tissue segmentation for Spatial Proteomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 35. [Spatial Proteomics] intermediate - Intermediate need
- **Query:** "I need to antibody imaging for Spatial Proteomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 36. [Spatial Proteomics] expert - Standard workflow
- **Query:** "Generate standard antibody imaging workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 37. [Spatial Proteomics] expert - Expert optimization
- **Query:** "Optimize seqFISH parameters for tissue segmentation with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 38. [Spatial Proteomics] expert - Intermediate need
- **Query:** "I need to LC-MS spatial for Spatial Proteomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 39. [Imaging MS] intermediate - Intermediate need
- **Query:** "I need to metabolite mapping for Imaging MS"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 40. [Imaging MS] intermediate - Intermediate need
- **Query:** "I need to metabolite mapping for Imaging MS"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 41. [Imaging MS] expert - Standard workflow
- **Query:** "Generate standard tissue imaging workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 42. [Imaging MS] expert - Expert optimization
- **Query:** "Optimize MALDI-TOF parameters for tissue imaging with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 43. [Imaging MS] expert - Intermediate need
- **Query:** "I need to metabolite mapping for Imaging MS"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 44. [Short-read Metagenomics] intermediate - Intermediate need
- **Query:** "I need to binning for Short-read Metagenomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 45. [Short-read Metagenomics] intermediate - Intermediate need
- **Query:** "I need to taxonomic profiling for Short-read Metagenomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 46. [Short-read Metagenomics] expert - Standard workflow
- **Query:** "Generate standard taxonomic profiling workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 47. [Short-read Metagenomics] expert - Expert optimization
- **Query:** "Optimize Raven parameters for binning with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 48. [Short-read Metagenomics] expert - Intermediate need
- **Query:** "I need to assembly for Short-read Metagenomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 49. [Nanopore Metagenomics] intermediate - Intermediate need
- **Query:** "I need to strain profiling for Nanopore Metagenomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 50. [Nanopore Metagenomics] intermediate - Intermediate need
- **Query:** "I need to strain profiling for Nanopore Metagenomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 51. [Nanopore Metagenomics] expert - Standard workflow
- **Query:** "Generate standard long-read assembly workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 52. [Nanopore Metagenomics] expert - Expert optimization
- **Query:** "Optimize Flye parameters for long-read assembly with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 53. [Nanopore Metagenomics] expert - Intermediate need
- **Query:** "I need to strain profiling for Nanopore Metagenomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 54. [PacBio Metagenomics] intermediate - Intermediate need
- **Query:** "I need to complete genomes for PacBio Metagenomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 55. [PacBio Metagenomics] intermediate - Intermediate need
- **Query:** "I need to complete genomes for PacBio Metagenomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 56. [PacBio Metagenomics] expert - Standard workflow
- **Query:** "Generate standard HiFi metagenomics workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 57. [PacBio Metagenomics] expert - Expert optimization
- **Query:** "Optimize Flye parameters for HiFi metagenomics with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 58. [PacBio Metagenomics] expert - Intermediate need
- **Query:** "I need to complete genomes for PacBio Metagenomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 59. [Clinical LIS] intermediate - Intermediate need
- **Query:** "I need to critical alerts for Clinical LIS"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 60. [Clinical LIS] intermediate - Intermediate need
- **Query:** "I need to order management for Clinical LIS"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 61. [Clinical LIS] expert - Standard workflow
- **Query:** "Generate standard order management workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 62. [Clinical LIS] expert - Expert optimization
- **Query:** "Optimize Bahmni parameters for critical alerts with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 63. [Clinical LIS] expert - Intermediate need
- **Query:** "I need to auto-verification for Clinical LIS"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 64. [Clinical Diagnostics] intermediate - Intermediate need
- **Query:** "I need to delta checks for Clinical Diagnostics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 65. [Clinical Diagnostics] intermediate - Intermediate need
- **Query:** "I need to instrument integration for Clinical Diagnostics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 66. [Clinical Diagnostics] expert - Standard workflow
- **Query:** "Generate standard instrument integration workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 67. [Clinical Diagnostics] expert - Expert optimization
- **Query:** "Optimize Cobas parameters for delta checks with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Very specific technical request


### 68. [Clinical Diagnostics] expert - Intermediate need
- **Query:** "I need to QC rules for Clinical Diagnostics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 69. [Germline Variants] intermediate - Intermediate need
- **Query:** "I need to annotation for Germline Variants"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 70. [Germline Variants] intermediate - Intermediate need
- **Query:** "I need to joint calling for Germline Variants"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 71. [Germline Variants] expert - Standard workflow
- **Query:** "Generate standard joint calling workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 72. [Germline Variants] expert - Expert optimization
- **Query:** "Optimize Mutect2 parameters for annotation with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 73. [Germline Variants] expert - Intermediate need
- **Query:** "I need to VQSR for Germline Variants"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 74. [Somatic Variants] intermediate - Intermediate need
- **Query:** "I need to CNV for Somatic Variants"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 75. [Somatic Variants] intermediate - Intermediate need
- **Query:** "I need to tumor-normal for Somatic Variants"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 76. [Somatic Variants] expert - Standard workflow
- **Query:** "Generate standard tumor-normal workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 77. [Somatic Variants] expert - Expert optimization
- **Query:** "Optimize Mutect2 parameters for CNV with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 78. [Somatic Variants] expert - Intermediate need
- **Query:** "I need to panel of normals for Somatic Variants"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 79. [Copy Number Variants] intermediate - Intermediate need
- **Query:** "I need to WES CNV for Copy Number Variants"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 80. [Copy Number Variants] intermediate - Intermediate need
- **Query:** "I need to WES CNV for Copy Number Variants"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 81. [Copy Number Variants] expert - Standard workflow
- **Query:** "Generate standard WGS CNV workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 82. [Copy Number Variants] expert - Expert optimization
- **Query:** "Optimize CNVkit parameters for WGS CNV with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 83. [Copy Number Variants] expert - Intermediate need
- **Query:** "I need to WES CNV for Copy Number Variants"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 84. [Structural Variants] intermediate - Intermediate need
- **Query:** "I need to breakpoint refinement for Structural Variants"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 85. [Structural Variants] intermediate - Intermediate need
- **Query:** "I need to breakpoint refinement for Structural Variants"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 86. [Structural Variants] expert - Standard workflow
- **Query:** "Generate standard SV detection workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 87. [Structural Variants] expert - Expert optimization
- **Query:** "Optimize Lumpy parameters for SV detection with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 88. [Structural Variants] expert - Intermediate need
- **Query:** "I need to breakpoint refinement for Structural Variants"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 89. [Epigenomics] intermediate - Intermediate need
- **Query:** "I need to methylation for Epigenomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 90. [Epigenomics] intermediate - Intermediate need
- **Query:** "I need to ChIP-seq peaks for Epigenomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 91. [Epigenomics] expert - Standard workflow
- **Query:** "Generate standard ChIP-seq peaks workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 92. [Epigenomics] expert - Expert optimization
- **Query:** "Optimize MACS2 parameters for methylation with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 93. [Epigenomics] expert - Intermediate need
- **Query:** "I need to ATAC-seq for Epigenomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 94. [Metabolomics] intermediate - Intermediate need
- **Query:** "I need to targeted quant for Metabolomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 95. [Metabolomics] intermediate - Intermediate need
- **Query:** "I need to targeted quant for Metabolomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 96. [Metabolomics] expert - Standard workflow
- **Query:** "Generate standard untargeted workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 97. [Metabolomics] expert - Expert optimization
- **Query:** "Optimize XCMS parameters for untargeted with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 98. [Metabolomics] expert - Intermediate need
- **Query:** "I need to targeted quant for Metabolomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 99. [Multi-omics] beginner - Quick analysis
- **Query:** "Quick factor analysis with mixOmics"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Low confidence (0.70)


### 100. [Multi-omics] intermediate - Quick analysis
- **Query:** "Quick factor analysis with mixOmics"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Low confidence (0.70)


### 101. [Multi-omics] intermediate - Quick analysis
- **Query:** "Quick factor analysis with mixOmics"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Low confidence (0.70)


### 102. [Multi-omics] expert - Standard workflow
- **Query:** "Generate standard integration workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 103. [Multi-omics] expert - Expert optimization
- **Query:** "Optimize MOFA parameters for integration with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 104. [Multi-omics] expert - Quick analysis
- **Query:** "Quick factor analysis with mixOmics"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Low confidence (0.70)


### 105. [Drug Discovery] intermediate - Intermediate need
- **Query:** "I need to virtual screening for Drug Discovery"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 106. [Drug Discovery] intermediate - Intermediate need
- **Query:** "I need to virtual screening for Drug Discovery"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 107. [Drug Discovery] expert - Standard workflow
- **Query:** "Generate standard docking workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 108. [Drug Discovery] expert - Expert optimization
- **Query:** "Optimize AutoDock Vina parameters for docking with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 109. [Drug Discovery] expert - Intermediate need
- **Query:** "I need to virtual screening for Drug Discovery"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 110. [Synthetic Biology] beginner - Run tool
- **Query:** "Run COBRApy for pathway design"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Low confidence (0.70)


### 111. [Synthetic Biology] intermediate - Intermediate need
- **Query:** "I need to strain engineering for Synthetic Biology"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 112. [Synthetic Biology] intermediate - Run tool
- **Query:** "Run COBRApy for pathway design"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Low confidence (0.70)


### 113. [Synthetic Biology] intermediate - Intermediate need
- **Query:** "I need to strain engineering for Synthetic Biology"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 114. [Synthetic Biology] expert - Standard workflow
- **Query:** "Generate standard pathway design workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 115. [Synthetic Biology] expert - Intermediate need
- **Query:** "I need to strain engineering for Synthetic Biology"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 116. [Agricultural Genomics] intermediate - Intermediate need
- **Query:** "I need to genomic selection for Agricultural Genomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 117. [Agricultural Genomics] intermediate - Intermediate need
- **Query:** "I need to genomic selection for Agricultural Genomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 118. [Agricultural Genomics] expert - Standard workflow
- **Query:** "Generate standard GWAS workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 119. [Agricultural Genomics] expert - Expert optimization
- **Query:** "Optimize TASSEL parameters for GWAS with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 120. [Agricultural Genomics] expert - Intermediate need
- **Query:** "I need to genomic selection for Agricultural Genomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 121. [Environmental Meta] intermediate - Intermediate need
- **Query:** "I need to biodiversity for Environmental Meta"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 122. [Environmental Meta] intermediate - Intermediate need
- **Query:** "I need to biodiversity for Environmental Meta"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 123. [Environmental Meta] expert - Standard workflow
- **Query:** "Generate standard 16S amplicon workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 124. [Environmental Meta] expert - Expert optimization
- **Query:** "Optimize Raven parameters for 16S amplicon with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 125. [Environmental Meta] expert - Intermediate need
- **Query:** "I need to biodiversity for Environmental Meta"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 126. [Patient Monitoring] beginner - Run tool
- **Query:** "Run R for trend analysis"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Analysis request


### 127. [Patient Monitoring] intermediate - Run tool
- **Query:** "Run R for trend analysis"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Analysis request


### 128. [Patient Monitoring] expert - Standard workflow
- **Query:** "Generate standard trend analysis workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 129. [EMR Integration] intermediate - Intermediate need
- **Query:** "I need to message routing for EMR Integration"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 130. [EMR Integration] intermediate - Intermediate need
- **Query:** "I need to message routing for EMR Integration"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 131. [EMR Integration] expert - Standard workflow
- **Query:** "Generate standard bidirectional sync workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 132. [EMR Integration] expert - Expert optimization
- **Query:** "Optimize HL7 parameters for bidirectional sync with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 133. [EMR Integration] expert - Intermediate need
- **Query:** "I need to message routing for EMR Integration"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 134. [Core Facility] beginner - Standard workflow
- **Query:** "Generate standard sample tracking workflow"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Complex query


### 135. [Core Facility] beginner - Run tool
- **Query:** "Run BaseSpace for sample tracking"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Complex query


### 136. [Core Facility] intermediate - Intermediate need
- **Query:** "I need to QC dashboards for Core Facility"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 137. [Core Facility] intermediate - Standard workflow
- **Query:** "Generate standard sample tracking workflow"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Complex query


### 138. [Core Facility] intermediate - Run tool
- **Query:** "Run BaseSpace for sample tracking"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Complex query


### 139. [Core Facility] intermediate - Intermediate need
- **Query:** "I need to QC dashboards for Core Facility"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 140. [Core Facility] expert - Intermediate need
- **Query:** "I need to QC dashboards for Core Facility"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 141. [Pharmacogenomics] intermediate - Intermediate need
- **Query:** "I need to drug metabolism for Pharmacogenomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 142. [Pharmacogenomics] intermediate - Intermediate need
- **Query:** "I need to drug metabolism for Pharmacogenomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 143. [Pharmacogenomics] expert - Standard workflow
- **Query:** "Generate standard PGx genotyping workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 144. [Pharmacogenomics] expert - Expert optimization
- **Query:** "Optimize PharmCAT parameters for PGx genotyping with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 145. [Pharmacogenomics] expert - Intermediate need
- **Query:** "I need to drug metabolism for Pharmacogenomics"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 146. [Microbiome Functional] intermediate - Intermediate need
- **Query:** "I need to pathway abundance for Microbiome Functional"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 147. [Microbiome Functional] intermediate - Intermediate need
- **Query:** "I need to pathway abundance for Microbiome Functional"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 148. [Microbiome Functional] expert - Standard workflow
- **Query:** "Generate standard functional profiling workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 149. [Microbiome Functional] expert - Expert optimization
- **Query:** "Optimize HUMAnN parameters for functional profiling with batch correction"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 150. [Microbiome Functional] expert - Intermediate need
- **Query:** "I need to pathway abundance for Microbiome Functional"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 151. [Cloud/HPC] beginner - Run tool
- **Query:** "Run Nextflow for workflow orchestration"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Workflow generation


### 152. [Cloud/HPC] intermediate - Intermediate need
- **Query:** "I need to cloud deployment for Cloud/HPC"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 153. [Cloud/HPC] intermediate - Run tool
- **Query:** "Run Snakemake for workflow orchestration"
- **Expected:** legacy
- **Got:** iterative
- **Reason:** Workflow generation


### 154. [Cloud/HPC] intermediate - Intermediate need
- **Query:** "I need to cloud deployment for Cloud/HPC"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question


### 155. [Cloud/HPC] expert - Standard workflow
- **Query:** "Generate standard workflow orchestration workflow"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** Simple + adequate confidence


### 156. [Cloud/HPC] expert - Intermediate need
- **Query:** "I need to cloud deployment for Cloud/HPC"
- **Expected:** iterative
- **Got:** legacy
- **Reason:** General question

