# Workflow Input Recipe — 2026-05-29

**Total workflows scanned:** 2182

**Workflows with `params.mock_mode` actually implemented:** 1

**Workflows with required-input guards:** 23


This doc lists, per workflow:

- **required**: params that abort with `error` if missing (must provide)

- **mock?**: whether `params.mock_mode` is actually implemented (truthy = can fire blank for CI)

- **declared**: total `params.X = ...` declarations in the .nf file

- **DB-only**: params the workflow DB claims but the .nf doesn't actually have (DB indexer hallucination)


## biochemistry

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| analyze_circular_dichroism_spectra | — |  | 8 |  |
| analyze_enzyme_kinetics_assay | — |  | 7 |  |
| analyze_itc_binding_thermodynamics | — |  | 6 |  |
| analyze_protease_kinetics | — |  | 7 |  |
| analyze_protein_conservation | — |  | 3 |  |
| analyze_rna_secondary_structure_features | — |  | 3 |  |
| dose_response | — |  | 4 |  |
| michaelis_menten | — |  | 4 |  |
| one_site_model | — |  | 5 |  |

## bioconductor

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| a4 | — |  | 0 | `count_data` |
| a4classif | — |  | 0 | `count_data` |
| a4core | — |  | 0 | `count_data` |
| a4preproc | — |  | 0 | `count_data` |
| abseqr | — |  | 0 | `ggplot_object` |
| absseq | — |  | 0 | `count_data` |
| acde | — |  | 0 | `count_data` |
| ace | — |  | 0 | `background_image_path`, `control_image_path`, `sample_image_path`, `output_dir` |
| acgh | — |  | 0 | `count_data` |
| acme | — |  | 0 | `count_data` |
| adacgh2 | — |  | 0 | `count_data` |
| adapt | — |  | 0 | `count_data` |
| adductomicsr | — |  | 0 | `count_data` |
| adsplit | — |  | 0 | `count_data` |
| adverscarial | — |  | 0 | `count_data` |
| affixcan | — |  | 0 | `count_data` |
| affy | — |  | 0 | `count_data` |
| affycomp | — |  | 0 | `count_data` |
| affycontam | — |  | 0 | `count_data` |
| affycoretools | — |  | 0 | `expressionset` |
| affyilm | — |  | 0 | `count_data` |
| affylmgui | — |  | 0 | `count_data` |
| affyplm | — |  | 0 | `count_data` |
| affyrnadegradation | — |  | 0 | `count_data` |
| agdex | — |  | 0 | `count_data` |
| aggregatebiovar | — |  | 0 | `deseqdataset` |
| agilp | — |  | 0 | `count_data` |
| agimicrorna | — |  | 0 | `count_data` |
| ahmassbank | — |  | 0 | `count_data` |
| aims | — |  | 0 | `count_data` |
| airpart | — |  | 0 | `count_data` |
| alabaster_base | — |  | 0 | `count_data` |
| alabaster_bumpy | — |  | 0 | `count_data` |
| alabaster_files | — |  | 0 | `count_data` |
| alabaster_mae | — |  | 0 | `input_file` |
| alabaster_matrix | — |  | 0 | `count_data` |
| alabaster_ranges | — |  | 0 | `count_data` |
| alabaster_sce | — |  | 0 | `count_data` |
| alabaster_se | — |  | 0 | `count_data` |
| alabaster_spatial | — |  | 0 | `count_data` |
| alabaster_string | — |  | 0 | `count_data` |
| alabaster_vcf | — |  | 0 | `count_data` |
| aldex2 | — |  | 0 | `count_data` |
| alevinqc | — |  | 0 | `count_data` |
| alphabeta | — |  | 0 | `count_data` |
| alphamissenser | — |  | 0 | `count_data` |
| alpsnmr | — |  | 0 | `count_data` |
| altcdfenvs | — |  | 0 | `count_data` |
| amaretto | — |  | 0 | `count_data` |
| amountain | — |  | 0 | `count_data` |
| amplican | — |  | 0 | `count_data` |
| ancombc | — |  | 0 | `count_data` |
| anf | — |  | 0 | `count_data` |
| annaffy | — |  | 0 | `count_data` |
| annotate | — |  | 0 | `ch_vcf`, `ch_fasta`, `ch_vep_cache`, `ch_vep_extra_files`, `ch_snpeff_cache` |
| annotationhub | — |  | 0 | `count_data` |
| annotationtools | — |  | 0 | `count_data` |
| anota | — |  | 0 | `count_data` |
| anota2seq | — |  | 0 | `count_data` |
| antiprofiles | — |  | 0 | `count_data` |
| anvil | — |  | 0 | `count_data` |
| anvilaz | — |  | 0 | `count_data` |
| anvilbase | — |  | 0 | `count_data` |
| anvilbilling | — |  | 0 | `count_data` |
| anvilworkflow | — |  | 0 | `count_data` |
| apalyzer | — |  | 0 | `count_data` |
| apcomplex | — |  | 0 | `count_data` |
| apeglm | — |  | 0 | `count_data` |
| apl | — |  | 0 | `sample_fasta_files`, `reference_genome_path`, `output_dir` |
| appreci8r | — |  | 0 | `plot_object` |
| arrayexpress | — |  | 0 | `count_data` |
| arraymvout | — |  | 0 | `count_data` |
| arrayqualitymetrics | — |  | 0 | `count_data` |
| arrmnormalization | — |  | 0 | `count_data` |
| aseb | — |  | 0 | `count_data` |
| asgsca | — |  | 0 | `count_data` |
| asics | — |  | 0 | `count_data` |
| aspli | — |  | 0 | `input_file` |
| assessorf | — |  | 0 | `count_data` |
| asset | — |  | 0 | `count_data` |
| assign | — |  | 0 | `count_data` |
| asurat | — |  | 0 | `count_data` |
| atacseqqc | — |  | 0 | `count_data` |
| atacseqtfea | — |  | 0 | `count_data` |
| atena | — |  | 0 | `count_data` |
| attract | — |  | 0 | `count_data` |
| aucell | — |  | 0 | `count_data` |
| awfisher | — |  | 0 | `count_data` |
| awst | — |  | 0 | `summarizedexperiment` |
| baalchip | — |  | 0 | `count_data` |
| bacon | — |  | 0 | `summarizedexperiment` |
| bader | — |  | 0 | `count_data` |
| badregionfinder | — |  | 0 | `count_data` |
| bags | — |  | 0 | `count_data` |
| ballgown | — |  | 0 | `count_data` |
| bambu | — |  | 0 | `count_data` |
| bamsignals | — |  | 0 | `count_data` |
| bandits | — |  | 0 | `count_data` |
| bandle | — |  | 0 | `count_data` |
| banksy | — |  | 0 | `count_data` |
| banocc | — |  | 0 | `count_data` |
| barcodetrackr | — |  | 0 | `count_data` |
| basecallqc | — |  | 0 | `count_data` |
| basespacer | — |  | 0 | `count_data` |
| basic4cseq | — |  | 0 | `count_data` |
| basics | — |  | 0 | `count_data` |
| basicstan | — |  | 0 | `count_data` |
| basicstarrseq | — |  | 0 | `count_data` |
| basilisk | — |  | 0 | `count_data` |
| batchelor | — |  | 0 | `count_data` |
| batchqc | — |  | 0 | `count_data` |
| bayesknockdown | — |  | 0 | `count_data` |
| bayesspace | — |  | 0 | `count_data` |
| baynorm | — |  | 0 | `singlecellexperiment` |
| bayseq | — |  | 0 | `count_data` |
| bbcanalyzer | — |  | 0 | `count_data` |
| bcrank | — |  | 0 | `count_data` |
| bcseq | — |  | 0 | `count_data` |
| beaddatapackr | — |  | 0 | `count_data` |
| beat | — |  | 0 | `video_path`, `roi_count`, `min_freq`, `max_freq`, `output_dir` |
| beclear | — |  | 0 | `count_data` |
| beer | — |  | 0 | `count_data` |
| benchdamic | — |  | 0 | `count_data` |
| bert | — |  | 0 | `count_data` |
| betahmm | — |  | 0 | `count_data` |
| bettr | — |  | 0 | `count_data` |
| bg2 | — |  | 0 | `count_data` |
| bgeedb | — |  | 0 | `count_data` |
| bicare | — |  | 0 | `count_data` |
| biggr | — |  | 0 | `count_data` |
| bigmelon | — |  | 0 | `count_data` |
| bindingsitefinder | — |  | 0 | `count_data` |
| biobase | — |  | 0 | `count_data` |
| biobroom | — |  | 0 | `count_data` |
| biobtreer | — |  | 0 | `count_data` |
| biocancer | — |  | 0 | `count_data` |
| biocartaimage | — |  | 0 | `count_data` |
| biocbook | — |  | 0 | `count_data` |
| biocgraph | — |  | 0 | `count_data` |
| biocor | — |  | 0 | `count_data` |
| biocpkgtools | — |  | 0 | `count_data` |
| biocroxytest | — |  | 0 | `count_data` |
| biocset | — |  | 0 | `deseqdataset` |
| biocsklearn | — |  | 0 | `count_data` |
| biocthis | — |  | 0 | `count_data` |
| biocviews | — |  | 0 | `count_data` |
| biodb | — |  | 0 | `count_data` |
| biodbchebi | — |  | 0 | `count_data` |
| biodbhmdb | — |  | 0 | `count_data` |
| biodbncbi | — |  | 0 | `count_data` |
| biodbnci | — |  | 0 | `count_data` |
| biodbuniprot | — |  | 0 | `count_data` |
| biodist | — |  | 0 | `time_points`, `tissue_data` |
| bioga | — |  | 0 | `count_data` |
| biomart | — |  | 0 | `count_data` |
| biomformat | — |  | 0 | `count_data` |
| biomvrcns | — |  | 0 | `count_data` |
| bionar | — |  | 0 | `count_data` |
| bionero | — |  | 0 | `plot_object` |
| bionet | — |  | 0 | `count_data` |
| bioqc | — |  | 0 | `count_data` |
| biosigner | — |  | 0 | `count_data` |
| biostrings | — |  | 0 | `count_data` |
| biotip | — |  | 0 | `count_data` |
| biotmle | — |  | 0 | `count_data` |
| biovizbase | — |  | 0 | `count_data` |
| birewire | — |  | 0 | `count_data` |
| biscuiteer | — |  | 0 | `count_data` |
| biseq | — |  | 0 | `count_data` |
| blacksheepr | — |  | 0 | `count_data` |
| blima | — |  | 0 | `count_data` |
| blma | — |  | 0 | `count_data` |
| bloodgen3module | — |  | 0 | `count_data` |
| bnbc | — |  | 0 | `count_data` |
| bnem | — |  | 0 | `count_data` |
| bobafit | — |  | 0 | `count_data` |
| borealis | — |  | 0 | `count_data` |
| bprmeth | — |  | 0 | `count_data` |
| brain | — |  | 0 | `dwi_file_path`, `b_values`, `output_path`, `mask_file_path` |
| branchpointer | — |  | 0 | `count_data` |
| brendadb | — |  | 0 | `deseq2results` |
| brew3r_r | — |  | 0 | `count_data` |
| bridgedbr | — |  | 0 | `count_data` |
| broadseq | — |  | 0 | `count_data` |
| browserviz | — |  | 0 | `count_data` |
| bsgenome | — |  | 0 | `bsgenome` |
| bsgenomeforge | — |  | 0 | `count_data` |
| bsseq | — |  | 0 | `count_data` |
| bubbletree | — |  | 0 | `plot_object` |
| bufferedmatrix | — |  | 0 | `count_data` |
| bugsigdbr | — |  | 0 | `count_data` |
| bumhmm | — |  | 0 | `count_data` |
| bumphunter | — |  | 0 | `plot_object` |
| bumpymatrix | — |  | 0 | `count_data` |
| bus | — |  | 0 | `fa`, `gff`, `val_busco_lineages_path`, `val_busco_config` |
| buscorrect | — |  | 0 | `count_data` |
| busparse | — |  | 0 | `count_data` |
| busseq | — |  | 0 | `count_data` |
| cadra | — |  | 0 | `count_data` |
| caen | — |  | 0 | `count_data` |
| cafe | — |  | 0 | `count_data` |
| cagefightr | — |  | 0 | `cluster_object` |
| cageminer | — |  | 0 | `count_data` |
| camera | — |  | 0 | `count_data` |
| camutqc | — |  | 0 | `count_data` |
| cancer | — |  | 0 | `fcs_file_path` |
| cancerclass | — |  | 0 | `count_data` |
| cardelino | — |  | 0 | `count_data` |
| cardinal | — |  | 0 | `ggplot_object` |
| cardinalio | — |  | 0 | `count_data` |
| carnival | — |  | 0 | `count_data` |
| casper | — |  | 0 | `count_data` |
| catalyst | — |  | 0 | `singlecellexperiment` |
| category | — |  | 0 | `count_data` |
| categorycompare | — |  | 0 | `marraylm` |
| catscradle | — |  | 0 | `count_data` |
| causalr | — |  | 0 | `count_data` |
| cbaf | — |  | 0 | `count_data` |
| cbea | — |  | 0 | `count_data` |
| cbioportaldata | — |  | 0 | `count_data` |
| cbnplot | — |  | 0 | `character` |
| ccfindr | — |  | 0 | `count_data` |
| ccimpute | — |  | 0 | `count_data` |
| ccplotr | — |  | 0 | `count_data` |
| ccpromise | — |  | 0 | `count_data` |
| cdi | — |  | 0 | `count_data` |
| celaref | — |  | 0 | `count_data` |
| celda | — |  | 0 | `singlecellexperiment` |
| cellbarcode | — |  | 0 | `count_data` |
| cellbench | — |  | 0 | `count_data` |
| cellid | — |  | 0 | `count_data` |
| cellity | — |  | 0 | `count_data` |
| cellmapper | — |  | 0 | `count_data` |
| cellmixs | — |  | 0 | `count_data` |
| cellnoptr | — |  | 0 | `count_data` |
| cellscore | — |  | 0 | `count_data` |
| cellxgenedp | — |  | 0 | `count_data` |
| cemitool | — |  | 0 | `count_data` |
| censcyt | — |  | 0 | `count_data` |
| cepo | — |  | 0 | `count_data` |
| cetf | — |  | 0 | `count_data` |
| cexor | — |  | 0 | `count_data` |
| cfassay | — |  | 0 | `count_data` |
| cfdnakit | — |  | 0 | `count_data` |
| cfdnapro | — |  | 0 | `count_data` |
| cftools | — |  | 0 | `vcf`, `bed` |
| cgen | — |  | 0 | `count_data` |
| cghcall | — |  | 0 | `count_data` |
| cghmcr | — |  | 0 | `count_data` |
| cghnormaliter | — |  | 0 | `count_data` |
| cghregions | — |  | 0 | `count_data` |
| chemmineob | — |  | 0 | `count_data` |
| chemminer | — |  | 0 | `count_data` |
| chetah | — |  | 0 | `singlecellexperiment` |
| chicago | — |  | 0 | `count_data` |
| chihaya | — |  | 0 | `count_data` |
| chimeraviz | — |  | 0 | `count_data` |
| chipcomp | — |  | 0 | `count_data` |
| chipenrich | — |  | 0 | `count_data` |
| chipexoqual | — |  | 0 | `count_data` |
| chipqc | — |  | 0 | `count_data` |
| chipseeker | — |  | 0 | `count_data` |
| chipseq | — |  | 0 | `fastq`, `samplesheet` |
| chipseqr | — |  | 0 | `plot_object` |
| chipsim | — |  | 0 | `count_data` |
| chipxpress | — |  | 0 | `count_data` |
| chopsticks | — |  | 0 | `count_data` |
| chromdraw | — |  | 0 | `count_data` |
| chromheatmap | — |  | 0 | `count_data` |
| chromplot | — |  | 0 | `count_data` |
| chromstar | — |  | 0 | `count_data` |
| chromvar | — |  | 0 | `count_data` |
| circrnaprofiler | — |  | 0 | `count_data` |
| circseqaligntk | — |  | 0 | `count_data` |
| cispath | — |  | 0 | `count_data` |
| citefuse | — |  | 0 | `count_data` |
| classifyr | — |  | 0 | `count_data` |
| cleanuprnaseq | — |  | 0 | `count_data` |
| cleaver | — |  | 0 | `count_data` |
| clevrvis | — |  | 0 | `count_data` |
| clippda | — |  | 0 | `count_data` |
| clipper | — |  | 0 | `count_data` |
| cliprofiler | — |  | 0 | `count_data` |
| cliquems | — |  | 0 | `count_data` |
| clomial | — |  | 0 | `count_data` |
| clst | — |  | 0 | `count_data` |
| clstutils | — |  | 0 | `count_data` |
| clumsid | — |  | 0 | `count_data` |
| clustall | — |  | 0 | `count_data` |
| clustcomp | — |  | 0 | `count_data` |
| clusterexperiment | — |  | 0 | `count_data` |
| clusterfoldsimilarity | — |  | 0 | `count_data` |
| clusterjudge | — |  | 0 | `count_data` |
| clusterprofiler | — |  | 0 | `count_data` |
| clusterseq | — |  | 0 | `count_data` |
| clustersignificance | — |  | 0 | `count_data` |
| clusterstab | — |  | 0 | `count_data` |
| clustifyr | — |  | 0 | `count_data` |
| cma | — |  | 0 | `count_data` |
| cmapr | — |  | 0 | `count_data` |
| cn_farms | — |  | 0 | `count_data` |
| cn_mops | — |  | 0 | `count_data` |
| cnanorm | — |  | 0 | `count_data` |
| cner | — |  | 0 | `count_data` |
| cnordt | — |  | 0 | `count_data` |
| cnorfeeder | — |  | 0 | `count_data` |
| cnorfuzzy | — |  | 0 | `count_data` |
| cntools | — |  | 0 | `count_data` |
| cnvmetrics | — |  | 0 | `count_data` |
| cnvpanelizer | — |  | 0 | `count_data` |
| cnvranger | — |  | 0 | `count_data` |
| cnvrd2 | — |  | 0 | `count_data` |
| codex | — |  | 0 | `count_data` |
| cogaps | — |  | 0 | `ggplot_object` |
| cogena | — |  | 0 | `ggplot_object` |
| cogeqc | — |  | 0 | `count_data` |
| cogito | — |  | 0 | `count_data` |
| cogps | — |  | 0 | `count_data` |
| comapr | — |  | 0 | `count_data` |
| combi | — |  | 0 | `drug_list`, `include_mechanisms`, `include_management`, `data_lake_path` |
| comethdmr | — |  | 0 | `count_data` |
| compass | — |  | 0 | `count_matrix` |
| compcoder | — |  | 0 | `count_data` |
| compepitools | — |  | 0 | `count_data` |
| complexheatmap | — |  | 0 | `count_data` |
| compounddb | — |  | 0 | `count_data` |
| compran | — |  | 0 | `count_data` |
| compspot | — |  | 0 | `count_data` |
| condiments | — |  | 0 | `count_data` |
| consensus | — |  | 0 | `fasta` |
| consensusclusterplus | — |  | 0 | `expr_matrix_rds` |
| consensusseeker | — |  | 0 | `count_data` |
| consica | — |  | 0 | `count_data` |
| copa | — |  | 0 | `count_data` |
| cordon | — |  | 0 | `count_data` |
| coregx | — |  | 0 | `count_data` |
| cormotif | — |  | 0 | `count_data` |
| corral | — |  | 0 | `count_data` |
| coseq | — |  | 0 | `count_data` |
| cosia | — |  | 0 | `count_data` |
| cosmiq | — |  | 0 | `count_data` |
| cosnet | — |  | 0 | `seurat_object` |
| cotan | — |  | 0 | `count_data` |
| countsimqc | — |  | 0 | `count_data` |
| coveb | — |  | 0 | `count_data` |
| coverageview | — |  | 0 | `count_data` |
| covrna | — |  | 0 | `count_data` |
| cpvsnp | — |  | 0 | `count_data` |
| cqn | — |  | 0 | `count_data` |
| crimage | — |  | 0 | `count_data` |
| crisprball | — |  | 0 | `count_data` |
| crisprbase | — |  | 0 | `count_data` |
| crisprbwa | — |  | 0 | `count_data` |
| crisprdesign | — |  | 0 | `count_data` |
| crisprscore | — |  | 0 | `count_data` |
| crisprseek | — |  | 0 | `count_data` |
| crisprvariants | — |  | 0 | `count_data` |
| crisprviz | — |  | 0 | `count_data` |
| crlmm | — |  | 0 | `count_data` |
| csar | — |  | 0 | `count_data` |
| cssq | — |  | 0 | `count_data` |
| ctc | — |  | 0 | `clinical_data_file` |
| ctdata | — |  | 0 | `count_data` |
| ctrap | — |  | 0 | `count_data` |
| ctsv | — |  | 0 | `count_data` |
| cummerbund | — |  | 0 | `count_data` |
| curatedatlasqueryr | — |  | 0 | `count_data` |
| customcmpdb | — |  | 0 | `count_data` |
| customprodb | — |  | 0 | `count_data` |
| cyanofilter | — |  | 0 | `count_data` |
| cycle | — |  | 0 | `image_paths`, `output_dir` |
| cydar | — |  | 0 | `plot_object` |
| cytofpower | — |  | 0 | `count_data` |
| cytofqc | — |  | 0 | `count_data` |
| cytokernel | — |  | 0 | `count_data` |
| cytomapper | — |  | 0 | `count_data` |
| cytomds | — |  | 0 | `count_data` |
| cytomem | — |  | 0 | `count_data` |
| cytoml | — |  | 0 | `plot_object` |
| cytopipeline | — |  | 0 | `count_data` |
| cytopipelinegui | — |  | 0 | `count_data` |
| cytoviewer | — |  | 0 | `count_data` |
| dada2 | — |  | 0 | `count_data` |
| daglogo | — |  | 0 | `count_data` |
| damefinder | — |  | 0 | `count_data` |
| damirseq | — |  | 0 | `count_data` |
| damsel | — |  | 0 | `count_data` |
| dart | — |  | 0 | `count_data` |
| dcats | — |  | 0 | `count_data` |
| dce | — |  | 0 | `count_data` |
| ddct | — |  | 0 | `count_data` |
| ddpcrclust | — |  | 0 | `ggplot_object` |
| dearseq | — |  | 0 | `count_data` |
| decipher | — |  | 0 | `count_data` |
| decomptumor2sig | — |  | 0 | `deseq2results` |
| deconrnaseq | — |  | 0 | `count_data` |
| decontam | — |  | 0 | `ch_fasta_reads` |
| deconvr | — |  | 0 | `count_data` |
| decoupler | — |  | 0 | `count_data` |
| deepsnv | — |  | 0 | `count_data` |
| deeptarget | — |  | 0 | `count_data` |
| deformats | — |  | 0 | `count_data` |
| degcre | — |  | 0 | `count_data` |
| degnorm | — |  | 0 | `count_data` |
| degraph | — |  | 0 | `count_data` |
| degreport | — |  | 0 | `deseqdataset` |
| degseq | — |  | 0 | `count_data` |
| delayeddataframe | — |  | 0 | `count_data` |
| delayedrandomarray | — |  | 0 | `count_data` |
| delocal | — |  | 0 | `count_data` |
| deltagseg | — |  | 0 | `count_data` |
| demand | — |  | 0 | `count_data` |
| demixt | — |  | 0 | `count_data` |
| demuxmix | — |  | 0 | `count_data` |
| demuxsnp | — |  | 0 | `count_data` |
| densvis | — |  | 0 | `count_data` |
| dep | — |  | 0 | `bam`, `fa` |
| depecher | — |  | 0 | `count_data` |
| depinfer | — |  | 0 | `count_data` |
| deqms | — |  | 0 | `marraylm` |
| derfinder | — |  | 0 | `count_data` |
| derfinderhelper | — |  | 0 | `count_data` |
| derfinderplot | — |  | 0 | `count_data` |
| descan2 | — |  | 0 | `count_data` |
| deseq2 | — |  | 0 | `deseqdataset` |
| desingle | — |  | 0 | `count_data` |
| despace | — |  | 0 | `count_data` |
| destiny | — |  | 0 | `count_data` |
| dewseq | — |  | 0 | `count_data` |
| dexma | — |  | 0 | `count_data` |
| dexseq | — |  | 0 | `count_data` |
| dfp | — |  | 0 | `count_data` |
| dfplyr | — |  | 0 | `count_data` |
| diffbind | — |  | 0 | `count_data` |
| diffcoexp | — |  | 0 | `count_data` |
| diffcyt | — |  | 0 | `count_data` |
| differentialregulation | — |  | 0 | `count_data` |
| difflogo | — |  | 0 | `count_data` |
| diffustats | — |  | 0 | `count_data` |
| diggit | — |  | 0 | `count_data` |
| dino | — |  | 0 | `count_data` |
| dinor | — |  | 0 | `count_data` |
| dir_expiry | — |  | 0 | `count_data` |
| director | — |  | 0 | `count_data` |
| dirichletmultinomial | — |  | 0 | `count_data` |
| discordant | — |  | 0 | `count_data` |
| discorhythm | — |  | 0 | `summarizedexperiment` |
| distinct | — |  | 0 | `count_data` |
| dittoseq | — |  | 0 | `seurat_object` |
| dks | — |  | 0 | `count_data` |
| dmrcaller | — |  | 0 | `count_data` |
| dmrcate | — |  | 0 | `count_data` |
| dmrscan | — |  | 0 | `count_data` |
| dmrseq | — |  | 0 | `count_data` |
| dnacopy | — |  | 0 | `count_data` |
| dnafusion | — |  | 0 | `count_data` |
| dominoeffect | — |  | 0 | `count_data` |
| dominosignal | — |  | 0 | `count_data` |
| doppelgangr | — |  | 0 | `count_data` |
| doscheda | — |  | 0 | `count_data` |
| dose | — |  | 0 | `x`, `ic50`, `hill` |
| doser | — |  | 0 | `count_data` |
| doubletrouble | — |  | 0 | `count_data` |
| drawproteins | — |  | 0 | `count_data` |
| dreamlet | — |  | 0 | `count_data` |
| drimseq | — |  | 0 | `deseqdataset` |
| drivernet | — |  | 0 | `count_data` |
| dropletutils | — |  | 0 | `count_data` |
| drugtargetinteractions | — |  | 0 | `count_data` |
| drugvsdisease | — |  | 0 | `count_data` |
| dss | — |  | 0 | `count_data` |
| dstruct | — |  | 0 | `count_data` |
| dta | — |  | 0 | `count_data` |
| dune | — |  | 0 | `count_data` |
| duplexdiscoverer | — |  | 0 | `count_data` |
| dyebias | — |  | 0 | `count_data` |
| easier | — |  | 0 | `count_data` |
| easylift | — |  | 0 | `count_data` |
| easyreporting | — |  | 0 | `count_data` |
| easyrnaseq | — |  | 0 | `count_data` |
| ebarrays | — |  | 0 | `count_data` |
| ebcoexpress | — |  | 0 | `count_data` |
| ebimage | — |  | 0 | `count_data` |
| ebsea | — |  | 0 | `count_data` |
| ebseq | — |  | 0 | `count_data` |
| ecolitk | — |  | 0 | `count_data` |
| edaseq | — |  | 0 | `deseqdataset` |
| edge | — |  | 0 | `count_data` |
| edger | — |  | 0 | `count_data` |
| edirquery | — |  | 0 | `deseqdataset` |
| eds | — |  | 0 | `count_data` |
| eir | — |  | 0 | `count_data` |
| eisar | — |  | 0 | `count_data` |
| emdomics | — |  | 0 | `count_data` |
| empiricalbrownsmethod | — |  | 0 | `count_data` |
| enhancedvolcano | — |  | 0 | `deseqdataset` |
| enhancerhomologsearch | — |  | 0 | `count_data` |
| enmix | — |  | 0 | `count_data` |
| enrichdo | — |  | 0 | `count_data` |
| enrichedheatmap | — |  | 0 | `count_data` |
| enrichmentbrowser | — |  | 0 | `summarizedexperiment` |
| enrichplot | — |  | 0 | `count_data` |
| enrichviewnet | — |  | 0 | `count_data` |
| epialleler | — |  | 0 | `plot_object` |
| epicompare | — |  | 0 | `count_data` |
| epidecoder | — |  | 0 | `count_data` |
| epigenomix | — |  | 0 | `count_data` |
| epigrahmm | — |  | 0 | `count_data` |
| epimix | — |  | 0 | `count_data` |
| epimutacions | — |  | 0 | `count_data` |
| epinem | — |  | 0 | `count_data` |
| epiregulon | — |  | 0 | `count_data` |
| epiregulon_extra | — |  | 0 | `count_data` |
| epistack | — |  | 0 | `count_data` |
| epistasisga | — |  | 0 | `count_data` |
| epitxdb | — |  | 0 | `count_data` |
| epivizr | — |  | 0 | `count_data` |
| epivizrchart | — |  | 0 | `count_data` |
| erccdashboard | — |  | 0 | `count_data` |
| erma | — |  | 0 | `count_data` |
| erssa | — |  | 0 | `count_data` |
| escape | — |  | 0 | `count_data` |
| escher | — |  | 0 | `singlecellexperiment` |
| esetvis | — |  | 0 | `count_data` |
| eudysbiome | — |  | 0 | `count_data` |
| evaluomer | — |  | 0 | `count_data` |
| eventpointer | — |  | 0 | `count_data` |
| excluster | — |  | 0 | `count_data` |
| eximir | — |  | 0 | `count_data` |
| experimenthub | — |  | 0 | `count_data` |
| experimentsubset | — |  | 0 | `count_data` |
| extrachips | — |  | 0 | `count_data` |
| factdesign | — |  | 0 | `count_data` |
| factr | — |  | 0 | `count_data` |
| faers | — |  | 0 | `count_data` |
| famagg | — |  | 0 | `count_data` |
| famat | — |  | 0 | `count_data` |
| fastliquidassociation | — |  | 0 | `input_file` |
| fastqcleaner | — |  | 0 | `count_data` |
| fastseg | — |  | 0 | `count_data` |
| fccac | — |  | 0 | `count_data` |
| fci | — |  | 0 | `count_data` |
| feast | — |  | 0 | `count_data` |
| featseekr | — |  | 0 | `count_data` |
| fedup | — |  | 0 | `count_data` |
| fella | — |  | 0 | `count_data` |
| fenr | — |  | 0 | `count_data` |
| ffpe | — |  | 0 | `count_data` |
| fgga | — |  | 0 | `count_data` |
| fgnet | — |  | 0 | `count_data` |
| fgsea | — |  | 0 | `count_data` |
| filterffpe | — |  | 0 | `count_data` |
| findips | — |  | 0 | `count_data` |
| findit2 | — |  | 0 | `count_data` |
| fishalyser | — |  | 0 | `count_data` |
| fishpond | — |  | 0 | `count_data` |
| fithic | — |  | 0 | `count_data` |
| flagme | — |  | 0 | `plot_object` |
| flowbeads | — |  | 0 | `count_data` |
| flowbin | — |  | 0 | `count_data` |
| flowcatchr | — |  | 0 | `count_data` |
| flowchic | — |  | 0 | `count_data` |
| flowclean | — |  | 0 | `count_data` |
| flowclust | — |  | 0 | `count_data` |
| flowcore | — |  | 0 | `count_data` |
| flowcut | — |  | 0 | `count_data` |
| flowcybar | — |  | 0 | `count_data` |
| flowfp | — |  | 0 | `count_data` |
| flowgate | — |  | 0 | `count_data` |
| flowgraph | — |  | 0 | `count_data` |
| flowmatch | — |  | 0 | `count_data` |
| flowmeans | — |  | 0 | `count_data` |
| flowmerge | — |  | 0 | `count_data` |
| flowpeaks | — |  | 0 | `count_data` |
| flowploidy | — |  | 0 | `count_data` |
| flowplots | — |  | 0 | `count_data` |
| flowsom | — |  | 0 | `count_data` |
| flowspecs | — |  | 0 | `count_data` |
| flowstats | — |  | 0 | `count_data` |
| flowtime | — |  | 0 | `count_data` |
| flowtrans | — |  | 0 | `count_data` |
| flowviz | — |  | 0 | `count_data` |
| flowvs | — |  | 0 | `count_data` |
| fmcsr | — |  | 0 | `count_data` |
| fmrs | — |  | 0 | `count_data` |
| fraser | — |  | 0 | `count_data` |
| frenchfish | — |  | 0 | `count_data` |
| frgepistasis | — |  | 0 | `count_data` |
| frma | — |  | 0 | `count_data` |
| frmatools | — |  | 0 | `count_data` |
| funomics | — |  | 0 | `count_data` |
| fusesom | — |  | 0 | `count_data` |
| ga4ghclient | — |  | 0 | `count_data` |
| ga4ghshiny | — |  | 0 | `count_data` |
| gaga | — |  | 0 | `count_data` |
| gage | — |  | 0 | `count_data` |
| gaprediction | — |  | 0 | `count_data` |
| gars | — |  | 0 | `count_data` |
| gatefinder | — |  | 0 | `count_data` |
| gatom | — |  | 0 | `count_data` |
| gbscleanr | — |  | 0 | `count_data` |
| gcapc | — |  | 0 | `count_data` |
| gcatest | — |  | 0 | `count_data` |
| gcrisprtools | — |  | 0 | `marraylm` |
| gdnax | — |  | 0 | `count_data` |
| gdr | — |  | 0 | `count_data` |
| gdrimport | — |  | 0 | `count_data` |
| gdrutils | — |  | 0 | `count_data` |
| gdsarray | — |  | 0 | `count_data` |
| gdsfmt | — |  | 0 | `count_data` |
| gedi | — |  | 0 | `count_data` |
| gemini | — |  | 0 | `count_data` |
| gemma_r | — |  | 0 | `count_data` |
| genarise | — |  | 0 | `count_data` |
| genebreak | — |  | 0 | `count_data` |
| geneclassifiers | — |  | 0 | `count_data` |
| geneexpressionsignature | — |  | 0 | `count_data` |
| genefilter | — |  | 0 | `count_data` |
| genega | — |  | 0 | `count_data` |
| genegeneinter | — |  | 0 | `count_data` |
| genemeta | — |  | 0 | `count_data` |
| genenetworkbuilder | — |  | 0 | `count_data` |
| geneoverlap | — |  | 0 | `count_data` |
| geneplast | — |  | 0 | `count_data` |
| geneplotter | — |  | 0 | `count_data` |
| generecommender | — |  | 0 | `count_data` |
| generegionscan | — |  | 0 | `count_data` |
| generxcluster | — |  | 0 | `count_data` |
| geneselectmmd | — |  | 0 | `count_data` |
| genestructuretools | — |  | 0 | `count_data` |
| genetclassifier | — |  | 0 | `count_data` |
| geneticsped | — |  | 0 | `count_data` |
| genetonic | — |  | 0 | `count_data` |
| genie3 | — |  | 0 | `count_data` |
| genocn | — |  | 0 | `count_data` |
| genomation | — |  | 0 | `count_data` |
| genomautomorphism | — |  | 0 | `count_data` |
| genomeintervals | — |  | 0 | `count_data` |
| genomes | — |  | 0 | `count_data` |
| genomicalignments | — |  | 0 | `count_data` |
| genomicdatacommons | — |  | 0 | `deseqdataset` |
| genomicdistributions | — |  | 0 | `count_data` |
| genomicfeatures | — |  | 0 | `count_data` |
| genomicfiles | — |  | 0 | `count_data` |
| genomicinstability | — |  | 0 | `count_data` |
| genomicinteractionnodes | — |  | 0 | `count_data` |
| genomicinteractions | — |  | 0 | `count_data` |
| genomicozone | — |  | 0 | `count_data` |
| genomicplot | — |  | 0 | `count_data` |
| genomicranges | — |  | 0 | `count_data` |
| genomicscores | — |  | 0 | `count_data` |
| genomicsupersignature | — |  | 0 | `count_data` |
| genomictuples | — |  | 0 | `count_data` |
| genvisr | — |  | 0 | `count_data` |
| geodiff | — |  | 0 | `count_data` |
| geoexplorer | — |  | 0 | `count_data` |
| geofastq | — |  | 0 | `count_data` |
| geometrid | — |  | 0 | `count_data` |
| geomxtools | — |  | 0 | `count_data` |
| geoquery | — |  | 0 | `count_data` |
| geosubmission | — |  | 0 | `count_data` |
| geotcgadata | — |  | 0 | `deseq2results` |
| gep2pep | — |  | 0 | `count_data` |
| getdee2 | — |  | 0 | `count_data` |
| geva | — |  | 0 | `count_data` |
| gewist | — |  | 0 | `count_data` |
| gg4way | — |  | 0 | `deseqdataset` |
| ggbio | — |  | 0 | `count_data` |
| ggcyto | — |  | 0 | `count_data` |
| ggkegg | — |  | 0 | `count_data` |
| ggmanh | — |  | 0 | `count_data` |
| ggpa | — |  | 0 | `count_data` |
| ggseqalign | — |  | 0 | `count_data` |
| ggspavis | — |  | 0 | `plot_object` |
| ggtree | — |  | 0 | `count_data` |
| ggtreeextra | — |  | 0 | `phyloseq` |
| ggtreespace | — |  | 0 | `count_data` |
| gigsea | — |  | 0 | `count_data` |
| ginmapper | — |  | 0 | `count_data` |
| gintomics | — |  | 0 | `input_file` |
| girafe | — |  | 0 | `count_data` |
| glad | — |  | 0 | `count_data` |
| gladiatox | — |  | 0 | `count_data` |
| glimma | — |  | 0 | `count_data` |
| glmgampoi | — |  | 0 | `count_data` |
| glmsparsenet | — |  | 0 | `count_data` |
| globalancova | — |  | 0 | `count_data` |
| globaltest | — |  | 0 | `count_data` |
| gmapr | — |  | 0 | `count_data` |
| gmicr | — |  | 0 | `count_data` |
| gmoviz | — |  | 0 | `count_data` |
| gmrp | — |  | 0 | `input_file` |
| goexpress | — |  | 0 | `count_data` |
| gofuncr | — |  | 0 | `count_data` |
| goprofiles | — |  | 0 | `count_data` |
| gosemsim | — |  | 0 | `count_data` |
| goseq | — |  | 0 | `count_data` |
| gostag | — |  | 0 | `count_data` |
| gostats | — |  | 0 | `count_data` |
| gothic | — |  | 0 | `count_data` |
| gotools | — |  | 0 | `count_data` |
| gpa | — |  | 0 | `count_data` |
| gpls | — |  | 0 | `count_data` |
| gpumagic | — |  | 0 | `count_data` |
| grafgen | — |  | 0 | `count_data` |
| granulator | — |  | 0 | `count_data` |
| graper | — |  | 0 | `count_data` |
| graphalignment | — |  | 0 | `count_data` |
| graphite | — |  | 0 | `count_data` |
| grenits | — |  | 0 | `count_data` |
| greylistchip | — |  | 0 | `count_data` |
| grmetrics | — |  | 0 | `count_data` |
| grohmm | — |  | 0 | `count_data` |
| gsalightning | — |  | 0 | `count_data` |
| gsar | — |  | 0 | `input_file` |
| gsca | — |  | 0 | `count_data` |
| gscreend | — |  | 0 | `count_data` |
| gseabase | — |  | 0 | `count_data` |
| gseabenchmarker | — |  | 0 | `count_data` |
| gsealm | — |  | 0 | `count_data` |
| gseamining | — |  | 0 | `count_data` |
| gsgalgor | — |  | 0 | `ggplot_object` |
| gsreg | — |  | 0 | `count_data` |
| gsri | — |  | 0 | `count_data` |
| gsva | — |  | 0 | `count_data` |
| gtrellis | — |  | 0 | `count_data` |
| guideseq | — |  | 0 | `count_data` |
| guitar | — |  | 0 | `count_data` |
| gviz | — |  | 0 | `count_data` |
| gwas_bayes | — |  | 0 | `count_data` |
| gwascat | — |  | 0 | `count_data` |
| gwastools | — |  | 0 | `count_data` |
| gwena | — |  | 0 | `count_data` |
| gypsum | — |  | 0 | `count_data` |
| hapfabia | — |  | 0 | `count_data` |
| harman | — |  | 0 | `count_data` |
| harmonizr | — |  | 0 | `count_data` |
| hdtd | — |  | 0 | `count_data` |
| hdxmsqc | — |  | 0 | `count_data` |
| heatmaps | — |  | 0 | `count_data` |
| heatplus | — |  | 0 | `count_data` |
| helloranges | — |  | 0 | `count_data` |
| help | — |  | 0 | `count_data` |
| heron | — |  | 0 | `count_data` |
| herper | — |  | 0 | `count_data` |
| hiannotator | — |  | 0 | `count_data` |
| hibag | — |  | 0 | `count_data` |
| hicaggr | — |  | 0 | `count_data` |
| hicbricks | — |  | 0 | `count_data` |
| hiccompare | — |  | 0 | `count_data` |
| hicdcplus | — |  | 0 | `count_data` |
| hicdoc | — |  | 0 | `count_data` |
| hicexperiment | — |  | 0 | `count_data` |
| hicontacts | — |  | 0 | `count_data` |
| hicool | — |  | 0 | `count_data` |
| hicvenndiagram | — |  | 0 | `count_data` |
| hiergwas | — |  | 0 | `count_data` |
| hierinf | — |  | 0 | `count_data` |
| hilbertvis | — |  | 0 | `count_data` |
| hilda | — |  | 0 | `count_data` |
| hippo | — |  | 0 | `count_data` |
| hireadsprocessor | — |  | 0 | `count_data` |
| hireewas | — |  | 0 | `count_data` |
| hitc | — |  | 0 | `count_data` |
| hmdbquery | — |  | 0 | `count_data` |
| hmmcopy | — |  | 0 | `count_data` |
| holofoodr | — |  | 0 | `count_data` |
| hoodscanr | — |  | 0 | `count_data` |
| hopach | — |  | 0 | `count_data` |
| hpaanalyze | — |  | 0 | `count_data` |
| hpar | — |  | 0 | `count_data` |
| hpip | — |  | 0 | `count_data` |
| htqpcr | — |  | 0 | `count_data` |
| htsfilter | — |  | 0 | `count_data` |
| hubmapr | — |  | 0 | `count_data` |
| hummingbird | — |  | 0 | `count_data` |
| hybridmtest | — |  | 0 | `count_data` |
| hyper | — |  | 0 | `count_data` |
| hyperdraw | — |  | 0 | `count_data` |
| iaseq | — |  | 0 | `count_data` |
| iasva | — |  | 0 | `count_data` |
| ibbig | — |  | 0 | `count_data` |
| ibh | — |  | 0 | `count_data` |
| ibmq | — |  | 0 | `count_data` |
| icare | — |  | 0 | `count_data` |
| icetea | — |  | 0 | `count_data` |
| icheck | — |  | 0 | `count_data` |
| ichip | — |  | 0 | `count_data` |
| icnv | — |  | 0 | `count_data` |
| icobra | — |  | 0 | `count_data` |
| ideal | — |  | 0 | `deseqdataset` |
| idr2d | — |  | 0 | `count_data` |
| igc | — |  | 0 | `count_data` |
| iggeneusage | — |  | 0 | `count_data` |
| igvr | — |  | 0 | `count_data` |
| ihw | — |  | 0 | `count_data` |
| illuminaio | — |  | 0 | `count_data` |
| iloreg | — |  | 0 | `count_data` |
| imas | — |  | 0 | `count_data` |
| imcrtools | — |  | 0 | `count_data` |
| imman | — |  | 0 | `count_data` |
| immune_deconvolution | `counts_matrix`, `signature_matrix` |  | 7 |  |
| immunoclust | — |  | 0 | `count_data` |
| immunogenviewer | — |  | 0 | `count_data` |
| immunotation | — |  | 0 | `count_data` |
| indeed | — |  | 0 | `count_data` |
| inetgrate | — |  | 0 | `count_data` |
| infinityflow | — |  | 0 | `count_data` |
| inpas | — |  | 0 | `count_data` |
| inpower | — |  | 0 | `count_data` |
| inspect | — |  | 0 | `deseqresults` |
| intact | — |  | 0 | `count_data` |
| intad | — |  | 0 | `count_data` |
| intansv | — |  | 0 | `count_data` |
| interaccircos | — |  | 0 | `count_data` |
| interactionset | — |  | 0 | `granges` |
| interactivecomplexheatmap | — |  | 0 | `count_data` |
| intercellar | — |  | 0 | `count_data` |
| interest | — |  | 0 | `count_data` |
| ioniser | — |  | 0 | `count_data` |
| ipath | — |  | 0 | `count_data` |
| ipddb | — |  | 0 | `plot_object` |
| ipo | — |  | 0 | `count_data` |
| isanalytics | — |  | 0 | `count_data` |
| isee | — |  | 0 | `count_data` |
| iseede | — |  | 0 | `count_data` |
| iseefier | — |  | 0 | `singlecellexperiment` |
| iseehex | — |  | 0 | `seurat_object` |
| iseehub | — |  | 0 | `count_data` |
| iseeindex | — |  | 0 | `count_data` |
| iseepathways | — |  | 0 | `numeric` |
| iseetree | — |  | 0 | `count_data` |
| iseeu | — |  | 0 | `count_data` |
| iseq | — |  | 0 | `count_data` |
| isobar | — |  | 0 | `count_data` |
| isobayes | — |  | 0 | `count_data` |
| isocorrector | — |  | 0 | `count_data` |
| isocorrectorgui | — |  | 0 | `count_data` |
| isoformswitchanalyzer | — |  | 0 | `count_data` |
| isomirs | — |  | 0 | `count_data` |
| italics | — |  | 0 | `count_data` |
| iterativebma | — |  | 0 | `count_data` |
| iterativebmasurv | — |  | 0 | `count_data` |
| ivas | — |  | 0 | `count_data` |
| ivygapse | — |  | 0 | `count_data` |
| iwtomics | — |  | 0 | `count_data` |
| karyoploter | — |  | 0 | `count_data` |
| katdetectr | — |  | 0 | `count_data` |
| kcsmart | — |  | 0 | `count_data` |
| kebabs | — |  | 0 | `count_data` |
| kegggraph | — |  | 0 | `count_data` |
| kegglincs | — |  | 0 | `count_data` |
| keggorthology | — |  | 0 | `count_data` |
| keggrest | — |  | 0 | `count_data` |
| kissde | — |  | 0 | `count_data` |
| kmcut | — |  | 0 | `count_data` |
| knowseq | — |  | 0 | `count_data` |
| knowyourcg | — |  | 0 | `count_data` |
| koinar | — |  | 0 | `count_data` |
| lapmix | — |  | 0 | `count_data` |
| lbe | — |  | 0 | `h5ad` |
| ldblock | — |  | 0 | `count_data` |
| lea | — |  | 0 | `fasta`, `database` |
| ledpred | — |  | 0 | `count_data` |
| lefser | — |  | 0 | `count_data` |
| lemur | — |  | 0 | `count_data` |
| les | — |  | 0 |  |
| lfa | — |  | 0 | `count_data` |
| limma | — |  | 0 | `count_data` |
| limmagui | — |  | 0 | `count_data` |
| limpca | — |  | 0 | `count_data` |
| linnorm | — |  | 0 | `count_data` |
| lintind | — |  | 0 | `count_data` |
| lionessr | — |  | 0 | `count_data` |
| lipidr | — |  | 0 | `count_data` |
| liquidassociation | — |  | 0 | `input_file` |
| lisaclust | — |  | 0 | `count_data` |
| loci2path | — |  | 0 | `count_data` |
| logicfs | — |  | 0 | `count_data` |
| lola | — |  | 0 | `count_data` |
| loomexperiment | — |  | 0 | `singlecellexperiment` |
| lpe | — |  | 0 | `count_data` |
| lpnet | — |  | 0 | `count_data` |
| lpsymphony | — |  | 0 | `count_data` |
| lrbasedbi | — |  | 0 | `count_data` |
| lrcell | — |  | 0 | `count_data` |
| lute | — |  | 0 | `count_data` |
| lymphoseq | — |  | 0 | `count_data` |
| m3c | — |  | 0 | `count_data` |
| m3drop | — |  | 0 | `input_file` |
| m6aboost | — |  | 0 | `count_data` |
| macorrplot | — |  | 0 | `count_data` |
| macsr | — |  | 0 | `count_data` |
| made4 | — |  | 0 | `count_data` |
| madseq | — |  | 0 | `count_data` |
| magar | — |  | 0 | `count_data` |
| mageckflute | — |  | 0 | `count_data` |
| magrene | — |  | 0 | `count_data` |
| mai | — |  | 0 | `fastq`, `samplesheet` |
| mait | — |  | 0 | `count_data` |
| makecdfenv | — |  | 0 | `count_data` |
| mantelcorr | — |  | 0 | `count_data` |
| mapfx | — |  | 0 | `count_data` |
| mapredictdsc | — |  | 0 | `count_data` |
| mariner | — |  | 0 | `count_data` |
| marr | — |  | 0 | `count_data` |
| marray | — |  | 0 | `count_data` |
| martini | — |  | 0 | `count_data` |
| maskbad | — |  | 0 | `count_data` |
| massarray | — |  | 0 | `count_data` |
| massir | — |  | 0 | `count_data` |
| massspecwavelet | — |  | 0 | `count_data` |
| mast | — |  | 0 | `count_data` |
| mastr | — |  | 0 | `count_data` |
| matchbox | — |  | 0 | `count_data` |
| matrixqcvis | — |  | 0 | `count_data` |
| matrixrider | — |  | 0 | `count_data` |
| matter | — |  | 0 | `count_data` |
| mbamethyl | — |  | 0 | `plot_object` |
| mbased | — |  | 0 | `count_data` |
| mbcb | — |  | 0 | `count_data` |
| mbecs | — |  | 0 | `count_data` |
| mbkmeans | — |  | 0 | `singlecellexperiment` |
| mbpcr | — |  | 0 | `count_data` |
| mbqn | — |  | 0 | `count_data` |
| mbttest | — |  | 0 | `count_data` |
| mcbiclust | — |  | 0 | `count_data` |
| mcsea | — |  | 0 | `count_data` |
| mdp | — |  | 0 | `count_data` |
| mdqc | — |  | 0 | `count_data` |
| meal | — |  | 0 | `count_data` |
| measurementerror_cor | — |  | 0 | `count_data` |
| meat | — |  | 0 | `count_data` |
| meb | — |  | 0 | `count_data` |
| medips | — |  | 0 | `count_data` |
| medme | — |  | 0 | `count_data` |
| megadepth | — |  | 0 | `count_data` |
| meigor | — |  | 0 | `count_data` |
| melissa | — |  | 0 | `count_data` |
| mergeomics | — |  | 0 | `count_data` |
| meshes | — |  | 0 | `count_data` |
| meskit | — |  | 0 | `count_data` |
| messina | — |  | 0 | `count_data` |
| metabcombiner | — |  | 0 | `count_data` |
| metaboannotation | — |  | 0 | `count_data` |
| metabocoreutils | — |  | 0 | `count_data` |
| metabolomicsworkbenchr | — |  | 0 | `count_data` |
| metabomxtr | — |  | 0 | `count_data` |
| metacca | — |  | 0 | `count_data` |
| metagene2 | — |  | 0 | `count_data` |
| metagenomeseq | — |  | 0 | `count_data` |
| metahdep | — |  | 0 | `count_data` |
| metams | — |  | 0 | `count_data` |
| metaphor | — |  | 0 | `count_data` |
| metapod | — |  | 0 | `count_data` |
| metapone | — |  | 0 | `count_data` |
| metaseq | — |  | 0 | `count_data` |
| metaseqr2 | — |  | 0 | `count_data` |
| metcirc | — |  | 0 | `count_data` |
| methimpute | — |  | 0 | `count_data` |
| methinheritsim | — |  | 0 | `count_data` |
| methodical | — |  | 0 | `count_data` |
| methped | — |  | 0 | `count_data` |
| methreg | — |  | 0 | `count_data` |
| methrix | — |  | 0 | `count_data` |
| methtargetedngs | — |  | 0 | `count_data` |
| methylaid | — |  | 0 | `count_data` |
| methylcc | — |  | 0 | `count_data` |
| methylclock | — |  | 0 | `count_data` |
| methylgsa | — |  | 0 | `count_data` |
| methylimp2 | — |  | 0 | `count_data` |
| methylinheritance | — |  | 0 | `count_data` |
| methylkit | — |  | 0 | `count_data` |
| methylpipe | — |  | 0 | `count_data` |
| methylseekr | — |  | 0 | `count_data` |
| methylsig | — |  | 0 | `count_data` |
| metid | — |  | 0 | `count_data` |
| metmashr | — |  | 0 | `count_data` |
| metnet | — |  | 0 | `count_data` |
| mfa | — |  | 0 | `count_data` |
| mfuzz | — |  | 0 | `count_data` |
| mgfm | — |  | 0 | `count_data` |
| mgfr | — |  | 0 | `count_data` |
| mgnifyr | — |  | 0 | `count_data` |
| mgsa | — |  | 0 | `count_data` |
| mia | — |  | 0 | `count_data` |
| miasim | — |  | 0 | `count_data` |
| miaviz | — |  | 0 | `count_data` |
| michip | — |  | 0 | `count_data` |
| microbiome | — |  | 0 | `count_data` |
| microbiomedasim | — |  | 0 | `count_data` |
| microbiomemarker | — |  | 0 | `count_data` |
| microstasis | — |  | 0 | `count_data` |
| micsqtl | — |  | 0 | `count_data` |
| midashla | — |  | 0 | `count_data` |
| milor | — |  | 0 | `seurat_object` |
| mimager | — |  | 0 | `count_data` |
| mina | — |  | 0 | `ch_fasta_reads` |
| mineica | — |  | 0 | `count_data` |
| minfi | — |  | 0 | `count_data` |
| minimumdistance | — |  | 0 | `count_data` |
| miqc | — |  | 0 | `count_data` |
| mirage | — |  | 0 | `count_data` |
| mirbaseconverter | — |  | 0 | `count_data` |
| mircomp | — |  | 0 | `count_data` |
| mirintegrator | — |  | 0 | `count_data` |
| mirit | — |  | 0 | `ggplot_object` |
| mirlab | — |  | 0 | `count_data` |
| mirnapath | — |  | 0 | `count_data` |
| mirnatap | — |  | 0 | `count_data` |
| mirtarrnaseq | — |  | 0 | `count_data` |
| missmethyl | — |  | 0 | `count_data` |
| missrows | — |  | 0 | `count_data` |
| mitch | — |  | 0 | `count_data` |
| mitoclone2 | — |  | 0 | `count_data` |
| mixomics | — |  | 0 | `count_data` |
| mlinterfaces | — |  | 0 | `count_data` |
| mlp | — |  | 0 | `count_data` |
| mlseq | — |  | 0 | `count_data` |
| mmdiff2 | — |  | 0 | `count_data` |
| mmuphin | — |  | 0 | `count_data` |
| mnem | — |  | 0 | `count_data` |
| moanin | — |  | 0 | `count_data` |
| mobilerna | — |  | 0 | `count_data` |
| mofa2 | — |  | 0 | `count_data` |
| mogamun | — |  | 0 | `count_data` |
| mogsa | — |  | 0 | `count_data` |
| moleculeexperiment | — |  | 0 | `count_data` |
| moma | — |  | 0 | `count_data` |
| monalisa | — |  | 0 | `count_data` |
| monocle | — |  | 0 | `count_data` |
| moonlight2r | — |  | 0 | `count_data` |
| mosaics | — |  | 0 | `count_data` |
| mosbi | — |  | 0 | `count_data` |
| mosclip | — |  | 0 | `count_data` |
| mosdef | — |  | 0 | `count_data` |
| mosim | — |  | 0 | `count_data` |
| motifbreakr | — |  | 0 | `count_data` |
| motifcounter | — |  | 0 | `count_data` |
| motifdb | — |  | 0 | `count_data` |
| motifmatchr | — |  | 0 | `count_data` |
| motifstack | — |  | 0 | `count_data` |
| motiftestr | — |  | 0 | `count_data` |
| mousefm | — |  | 0 | `count_data` |
| mpac | — |  | 0 | `count_data` |
| mpfe | — |  | 0 | `count_data` |
| mpra | — |  | 0 | `count_data` |
| mpranalyze | — |  | 0 | `count_data` |
| msa | — |  | 0 | `count_data` |
| msa2dist | — |  | 0 | `count_data` |
| msbackendmassbank | — |  | 0 | `count_data` |
| msbackendmetabolights | — |  | 0 | `count_data` |
| msbackendmgf | — |  | 0 | `count_data` |
| msbackendmsp | — |  | 0 | `count_data` |
| msbackendrawfilereader | — |  | 0 | `count_data` |
| msbackendsql | — |  | 0 | `count_data` |
| mscoreutils | — |  | 0 | `count_data` |
| msdatahub | — |  | 0 | `count_data` |
| msexperiment | — |  | 0 | `count_data` |
| msfeatures | — |  | 0 | `summarizedexperiment` |
| msgbsr | — |  | 0 | `count_data` |
| msimpute | — |  | 0 | `count_data` |
| mslp | — |  | 0 | `count_data` |
| msmseda | — |  | 0 | `count_data` |
| msmstests | — |  | 0 | `plot_object` |
| msnbase | — |  | 0 | `count_data` |
| msnid | — |  | 0 | `count_data` |
| msprep | — |  | 0 | `count_data` |
| mspurity | — |  | 0 | `count_data` |
| msqrob2 | — |  | 0 | `count_data` |
| msquality | — |  | 0 | `count_data` |
| msstatsconvert | — |  | 0 | `count_data` |
| msstatslip | — |  | 0 | `count_data` |
| msstatsptm | — |  | 0 | `count_data` |
| msstatstmt | — |  | 0 | `plot_object` |
| mudata | — |  | 0 | `count_data` |
| multiassayexperiment | — |  | 0 | `count_data` |
| multibac | — |  | 0 | `count_data` |
| multidataset | — |  | 0 | `count_data` |
| multigsea | — |  | 0 | `count_data` |
| multimed | — |  | 0 | `count_data` |
| multimir | — |  | 0 | `count_data` |
| multirnaflow | — |  | 0 | `count_data` |
| multiscan | — |  | 0 | `count_data` |
| multistateqtl | — |  | 0 | `ggplot_object` |
| multiwgcna | — |  | 0 | `count_data` |
| mumosa | — |  | 0 | `seurat_object` |
| mungesumstats | — |  | 0 | `count_data` |
| muscat | — |  | 0 | `count_data` |
| muscle | — |  | 0 | `count_data` |
| musicatk | — |  | 0 | `vcf_object` |
| mutationalpatterns | — |  | 0 | `count_data` |
| mygene | — |  | 0 | `count_data` |
| myvariant | — |  | 0 | `count_data` |
| mzid | — |  | 0 | `count_data` |
| mzr | — |  | 0 | `count_data` |
| nadfinder | — |  | 0 | `count_data` |
| nanomethviz | — |  | 0 | `count_data` |
| nanostringdiff | — |  | 0 | `count_data` |
| nanostringnctools | — |  | 0 | `count_data` |
| nanotube | — |  | 0 | `count_data` |
| nbamseq | — |  | 0 | `count_data` |
| ncdfflow | — |  | 0 | `count_data` |
| ncigraph | — |  | 0 | `count_data` |
| ndexr | — |  | 0 | `count_data` |
| nearbynding | — |  | 0 | `count_data` |
| nebulosa | — |  | 0 | `count_data` |
| nempi | — |  | 0 | `count_data` |
| netactivity | — |  | 0 | `count_data` |
| netboost | — |  | 0 | `count_data` |
| netpathminer | — |  | 0 | `count_data` |
| netresponse | — |  | 0 | `count_data` |
| netsam | — |  | 0 | `count_data` |
| netzoor | — |  | 0 | `count_data` |
| newwave | — |  | 0 | `count_data` |
| ngsreports | — |  | 0 | `count_data` |
| nipalsmcia | — |  | 0 | `count_data` |
| nnnorm | — |  | 0 | `count_data` |
| nnsvg | — |  | 0 | `count_data` |
| noiseq | — |  | 0 | `count_data` |
| norce | — |  | 0 | `count_data` |
| normalyzerde | — |  | 0 | `count_data` |
| normqpcr | — |  | 0 | `plot_object` |
| normr | — |  | 0 | `count_data` |
| nparc | — |  | 0 | `count_data` |
| npgsea | — |  | 0 | `count_data` |
| ntw | — |  | 0 | `count_data` |
| nucleosim | — |  | 0 | `count_data` |
| nucler | — |  | 0 | `count_data` |
| nucpos | — |  | 0 | `count_data` |
| nullranges | — |  | 0 | `count_data` |
| occugene | — |  | 0 | `plot_object` |
| ocplus | — |  | 0 | `count_data` |
| odseq | — |  | 0 | `count_data` |
| ogre | — |  | 0 | `count_data` |
| olin | — |  | 0 | `matrix` |
| olingui | — |  | 0 | `count_data` |
| omada | — |  | 0 | `count_data` |
| omicade4 | — |  | 0 | `count_data` |
| omiccircos | — |  | 0 | `count_data` |
| omicrexposome | — |  | 0 | `count_data` |
| omicsmlrepor | — |  | 0 | `count_data` |
| omicspca | — |  | 0 | `count_data` |
| omicsprint | — |  | 0 | `count_data` |
| omicsviewer | — |  | 0 | `count_data` |
| omixer | — |  | 0 | `count_data` |
| omnipathr | — |  | 0 | `count_data` |
| ompbam | — |  | 0 | `count_data` |
| omxplore | — |  | 0 | `count_data` |
| oncomix | — |  | 0 | `count_data` |
| oncoscanr | — |  | 0 | `count_data` |
| oncosimulr | — |  | 0 | `count_data` |
| onlinefdr | — |  | 0 | `count_data` |
| ontoproc | — |  | 0 | `count_data` |
| opencyto | — |  | 0 | `count_data` |
| openprimer | — |  | 0 | `count_data` |
| openstats | — |  | 0 | `count_data` |
| opossom | — |  | 0 | `count_data` |
| oppar | — |  | 0 | `count_data` |
| optimalflow | — |  | 0 | `count_data` |
| opweight | — |  | 0 | `deseqdataset` |
| orderedlist | — |  | 0 | `count_data` |
| orfhunter | — |  | 0 | `count_data` |
| organism_dplyr | — |  | 0 | `count_data` |
| organismdbi | — |  | 0 | `count_data` |
| osat | — |  | 0 | `count_data` |
| oscope | — |  | 0 | `count_data` |
| otubase | — |  | 0 | `count_data` |
| outrider | — |  | 0 | `count_data` |
| paa | — |  | 0 | `count_data` |
| packfinder | — |  | 0 | `count_data` |
| padma | — |  | 0 | `count_data` |
| padog | — |  | 0 | `count_data` |
| pagerank | — |  | 0 | `count_data` |
| paircompviz | — |  | 0 | `count_data` |
| pairedgsea | — |  | 0 | `count_data` |
| pairkat | — |  | 0 | `count_data` |
| pandar | — |  | 0 | `count_data` |
| panelcn_mops | — |  | 0 | `count_data` |
| panomir | — |  | 0 | `count_data` |
| panp | — |  | 0 | `count_data` |
| panr | — |  | 0 | `count_data` |
| parglms | — |  | 0 | `count_data` |
| parody | — |  | 0 | `count_data` |
| partcnv | — |  | 0 | `count_data` |
| past | — |  | 0 | `count_data` |
| path2ppi | — |  | 0 | `count_data` |
| pathifier | — |  | 0 | `count_data` |
| pathlinkr | — |  | 0 | `count_data` |
| pathnet | — |  | 0 | `count_data` |
| pathostat | — |  | 0 | `count_data` |
| pathrender | — |  | 0 | `count_data` |
| pathview | — |  | 0 | `count_data` |
| pathwaypca | — |  | 0 | `count_data` |
| pcaexplorer | — |  | 0 | `deseqdataset` |
| pcamethods | — |  | 0 | `count_data` |
| pcan | — |  | 0 | `count_data` |
| pcatools | — |  | 0 | `count_data` |
| pdinfobuilder | — |  | 0 | `count_data` |
| peakpanther | — |  | 0 | `count_data` |
| peca | — |  | 0 | `count_data` |
| peco | — |  | 0 | `count_data` |
| pedixplorer | — |  | 0 | `ggplot_object` |
| pengls | — |  | 0 | `count_data` |
| pepsnmr | — |  | 0 | `count_data` |
| pepstat | — |  | 0 | `phyloseq` |
| pepxmltab | — |  | 0 | `plot_object` |
| pfamanalyzer | — |  | 0 | `count_data` |
| pgca | — |  | 0 | `count_data` |
| pgxrpi | — |  | 0 | `count_data` |
| phantasuslite | — |  | 0 | `count_data` |
| pharmacogx | — |  | 0 | `count_data` |
| phenogeneranker | — |  | 0 | `count_data` |
| phenomis | — |  | 0 | `count_data` |
| phenopath | — |  | 0 | `count_data` |
| phenotest | — |  | 0 | `count_data` |
| phenstat | — |  | 0 | `count_data` |
| philr | — |  | 0 | `count_data` |
| phipdata | — |  | 0 | `count_data` |
| phosphonormalizer | — |  | 0 | `count_data` |
| phosr | — |  | 0 | `count_data` |
| phyloprofile | — |  | 0 | `count_data` |
| phyloseq | — |  | 0 | `count_data` |
| piano | — |  | 0 | `count_data` |
| pics | — |  | 0 | `count_data` |
| pigengene | — |  | 0 | `count_data` |
| pipecomp | — |  | 0 | `count_data` |
| pipeframe | — |  | 0 | `count_data` |
| pirat | — |  | 0 | `count_data` |
| piuma | — |  | 0 | `count_data` |
| planet | — |  | 0 | `count_data` |
| planttfhunter | — |  | 0 | `count_data` |
| plasmut | — |  | 0 | `count_data` |
| plgem | — |  | 0 | `count_data` |
| plotgardener | — |  | 0 | `count_data` |
| plotgrouper | — |  | 0 | `count_data` |
| plpe | — |  | 0 | `count_data` |
| plsdabatch | — |  | 0 | `count_data` |
| plyinteractions | — |  | 0 | `count_data` |
| plyranges | — |  | 0 | `count_data` |
| plyxp | — |  | 0 | `count_data` |
| pmm | — |  | 0 | `count_data` |
| pmp | — |  | 0 | `count_data` |
| podcall | — |  | 0 | `count_data` |
| podkat | — |  | 0 | `count_data` |
| pogos | — |  | 0 | `count_data` |
| polystest | — |  | 0 | `count_data` |
| powertcr | — |  | 0 | `count_data` |
| powsc | — |  | 0 | `count_data` |
| ppcseq | — |  | 0 | `count_data` |
| ppinfer | — |  | 0 | `count_data` |
| pqsfinder | — |  | 0 | `count_data` |
| pram | — |  | 0 | `count_data` |
| prebs | — |  | 0 | `count_data` |
| precisetad | — |  | 0 | `count_data` |
| preda | — |  | 0 | `count_data` |
| prince | — |  | 0 | `count_data` |
| proactiv | — |  | 0 | `count_data` |
| probamr | — |  | 0 | `count_data` |
| process | — |  | 0 | `fastq` |
| procoil | — |  | 0 | `count_data` |
| proda | — |  | 0 | `count_data` |
| profileplyr | — |  | 0 | `count_data` |
| profilescoredist | — |  | 0 | `count_data` |
| progeny | — |  | 0 | `count_data` |
| projectr | — |  | 0 | `count_data` |
| proloc | — |  | 0 | `count_data` |
| prolocgui | — |  | 0 | `count_data` |
| promise | — |  | 0 | `count_data` |
| prone | — |  | 0 | `count_data` |
| proteinprofiles | — |  | 0 | `count_data` |
| proteodisco | — |  | 0 | `count_data` |
| proteomm | — |  | 0 | `count_data` |
| protgear | — |  | 0 | `count_data` |
| psmatch | — |  | 0 | `count_data` |
| ptairms | — |  | 0 | `count_data` |
| puma | — |  | 0 | `count_data` |
| purecn | — |  | 0 | `count_data` |
| pvac | — |  | 0 | `count_data` |
| pvca | — |  | 0 | `count_data` |
| pviz | — |  | 0 | `count_data` |
| pwmenrich | — |  | 0 | `count_data` |
| qckitfastq | — |  | 0 | `count_data` |
| qcmetrics | — |  | 0 | `count_data` |
| qdnaseq | — |  | 0 | `input_file` |
| qfeatures | — |  | 0 | `count_data` |
| qmtools | — |  | 0 | `summarizedexperiment` |
| qpcrnorm | — |  | 0 | `count_data` |
| qpgraph | — |  | 0 | `count_data` |
| qplexanalyzer | — |  | 0 | `count_data` |
| qsea | — |  | 0 | `count_data` |
| qsmooth | — |  | 0 | `count_data` |
| qsutils | — |  | 0 | `count_data` |
| qsvar | — |  | 0 | `count_data` |
| qtlexperiment | — |  | 0 | `count_data` |
| qtlizer | — |  | 0 | `count_data` |
| quantiseqr | — |  | 0 | `ggplot_object` |
| quantro | — |  | 0 | `count_data` |
| quantsmooth | — |  | 0 | `count_data` |
| quasr | — |  | 0 | `count_data` |
| qubic | — |  | 0 | `deseqresults` |
| qusage | — |  | 0 | `count_data` |
| qvalue | — |  | 0 | `count_data` |
| r3cpet | — |  | 0 | `count_data` |
| r3cseq | — |  | 0 | `count_data` |
| r453plus1toolbox | — |  | 0 | `count_data` |
| r4rna | — |  | 0 | `count_data` |
| radiogx | — |  | 0 | `count_data` |
| raer | — |  | 0 | `count_data` |
| raggedexperiment | — |  | 0 | `count_data` |
| raids | — |  | 0 | `count_data` |
| rain | — |  | 0 | `dwi_file_path`, `b_values`, `output_path`, `mask_file_path` |
| ramwas | — |  | 0 | `count_data` |
| randpack | — |  | 0 | `count_data` |
| randrotation | — |  | 0 | `count_data` |
| rankprod | — |  | 0 | `count_data` |
| raresim | — |  | 0 | `count_data` |
| rarevariantvis | — |  | 0 | `count_data` |
| rarr | — |  | 0 | `count_data` |
| rawdiag | — |  | 0 | `count_data` |
| rawrr | — |  | 0 | `count_data` |
| rbcbook1 | — |  | 0 | `count_data` |
| rbec | — |  | 0 | `count_data` |
| rbioformats | — |  | 0 | `count_data` |
| rbioinf | — |  | 0 | `count_data` |
| rbiopaxparser | — |  | 0 | `count_data` |
| rblast | — |  | 0 | `xstringset` |
| rbm | — |  | 0 | `count_data` |
| rbowtie | — |  | 0 | `count_data` |
| rbowtie2 | — |  | 0 | `count_data` |
| rbsurv | — |  | 0 | `count_data` |
| rbwa | — |  | 0 | `count_data` |
| rcas | — |  | 0 | `count_data` |
| rcaspar | — |  | 0 | `count_data` |
| rcellminer | — |  | 0 | `count_data` |
| rcgh | — |  | 0 | `count_data` |
| rcistarget | — |  | 0 | `count_data` |
| rcm | — |  | 0 | `count_data` |
| rcollectl | — |  | 0 | `count_data` |
| rcsl | — |  | 0 | `count_data` |
| rcx | — |  | 0 | `count_data` |
| rcy3 | — |  | 0 | `count_data` |
| rcyjs | — |  | 0 | `count_data` |
| rdrtoolbox | — |  | 0 | `count_data` |
| reactomepa | — |  | 0 | `count_data` |
| readqpcr | — |  | 0 | `plot_object` |
| rebet | — |  | 0 | `count_data` |
| rebook | — |  | 0 | `count_data` |
| receptloss | — |  | 0 | `count_data` |
| reconsi | — |  | 0 | `count_data` |
| recount | — |  | 0 | `count_data` |
| recount3 | — |  | 0 | `count_data` |
| recountmethylation | — |  | 0 | `count_data` |
| reder | — |  | 0 | `count_data` |
| redisparam | — |  | 0 | `count_data` |
| redseq | — |  | 0 | `count_data` |
| regenrich | — |  | 0 | `count_data` |
| regionalpcs | — |  | 0 | `count_data` |
| regionalst | — |  | 0 | `count_data` |
| regioner | — |  | 0 | `count_data` |
| regionereloaded | — |  | 0 | `count_data` |
| regionreport | — |  | 0 | `plot_object` |
| regsplice | — |  | 0 | `count_data` |
| regutools | — |  | 0 | `count_data` |
| remp | — |  | 0 | `count_data` |
| repitools | — |  | 0 | `count_data` |
| reportingtools | — |  | 0 | `count_data` |
| repviz | — |  | 0 | `count_data` |
| residualmatrix | — |  | 0 | `count_data` |
| retrofit | — |  | 0 | `count_data` |
| rexposome | — |  | 0 | `count_data` |
| rfastp | — |  | 0 | `count_data` |
| rfpred | — |  | 0 | `count_data` |
| rgadem | — |  | 0 | `count_data` |
| rgenometracks | — |  | 0 | `count_data` |
| rgntx | — |  | 0 | `count_data` |
| rgoslin | — |  | 0 | `count_data` |
| rgraph2js | — |  | 0 | `count_data` |
| rgsea | — |  | 0 | `count_data` |
| rgsepd | — |  | 0 | `count_data` |
| rhdf5client | — |  | 0 | `count_data` |
| rhinotyper | — |  | 0 | `count_data` |
| ribodipa | — |  | 0 | `count_data` |
| riboprofiling | — |  | 0 | `count_data` |
| ribor | — |  | 0 | `count_data` |
| riboseqr | — |  | 0 | `count_data` |
| ribosomeprofilingqc | — |  | 0 | `dgelist` |
| rifi | — |  | 0 | `plasmid_sequence`, `target_region`, `existing_primers`, `is_circular`, `coverage_length` |
| rificomparative | — |  | 0 | `count_data` |
| rimmport | — |  | 0 | `count_data` |
| ritan | — |  | 0 | `count_data` |
| river | — |  | 0 | `count_data` |
| rjmcmcnucleosomes | — |  | 0 | `count_data` |
| rlassocox | — |  | 0 | `count_data` |
| rlmm | — |  | 0 | `count_data` |
| rmagpie | — |  | 0 | `count_data` |
| rmassbank | — |  | 0 | `count_data` |
| rmmquant | — |  | 0 | `deseqdataset` |
| rmspc | — |  | 0 | `count_data` |
| rnaagecalc | — |  | 0 | `count_data` |
| rnadecay | — |  | 0 | `count_data` |
| rnaeditr | — |  | 0 | `count_data` |
| rnamodr | — |  | 0 | `count_data` |
| rnamodr_alkanilineseq | — |  | 0 | `count_data` |
| rnamodr_ml | — |  | 0 | `count_data` |
| rnamodr_ribomethseq | — |  | 0 | `count_data` |
| rnasense | — |  | 0 | `count_data` |
| rnaseqcomp | — |  | 0 | `count_data` |
| rnaseqpower | — |  | 0 | `plot_object` |
| rnaseqsamplesize | — |  | 0 | `count_data` |
| rnbeads | — |  | 0 | `count_data` |
| rnits | — |  | 0 | `count_data` |
| roar | — |  | 0 | `count_data` |
| rols | — |  | 0 | `count_data` |
| rontotools | — |  | 0 | `count_data` |
| ropls | — |  | 0 | `count_data` |
| roseq | — |  | 0 | `bam`, `fasta`, `zip` |
| rots | — |  | 0 | `count_data` |
| rprimer | — |  | 0 | `count_data` |
| rpx | — |  | 0 | `count_data` |
| rqc | — |  | 0 | `count_data` |
| rqubic | — |  | 0 | `count_data` |
| rrdp | — |  | 0 | `count_data` |
| rrho | — |  | 0 | `count_data` |
| rrvgo | — |  | 0 | `count_data` |
| rsamtools | — |  | 0 | `count_data` |
| rsbml | — |  | 0 | `count_data` |
| rscudo | — |  | 0 | `count_data` |
| rsemmed | — |  | 0 | `count_data` |
| rseqan | — |  | 0 | `count_data` |
| rsubread | — |  | 0 | `count_data` |
| rsvsim | — |  | 0 | `count_data` |
| rsweep | — |  | 0 | `count_data` |
| rtca | — |  | 0 | `count_data` |
| rtcgatoolbox | — |  | 0 | `count_data` |
| rtn | — |  | 0 | `count_data` |
| rtopper | — |  | 0 | `plot_object` |
| rtpca | — |  | 0 | `count_data` |
| rtracklayer | — |  | 0 | `marraylm` |
| rtreemix | — |  | 0 | `count_data` |
| rtrm | — |  | 0 | `count_data` |
| rtrmui | — |  | 0 | `count_data` |
| ruvcorr | — |  | 0 | `count_data` |
| ruvnormalize | — |  | 0 | `count_data` |
| ruvseq | — |  | 0 | `deseqdataset` |
| rvs | — |  | 0 | `count_data` |
| rwikipathways | — |  | 0 | `count_data` |
| safe | — |  | 0 | `drug_list`, `comparison_period`, `signal_threshold` |
| saigegds | — |  | 0 | `count_data` |
| sampleclassifier | — |  | 0 | `count_data` |
| samspectral | — |  | 0 | `count_data` |
| sangerseqr | — |  | 0 | `count_data` |
| santa | — |  | 0 | `count_data` |
| sarc | — |  | 0 | `count_data` |
| sarks | — |  | 0 | `count_data` |
| saser | — |  | 0 | `count_data` |
| saturn | — |  | 0 | `summarizedexperiment` |
| sbmlr | — |  | 0 | `count_data` |
| sc3 | — |  | 0 | `count_data` |
| scale4c | — |  | 0 | `count_data` |
| scan_upc | — |  | 0 | `count_data` |
| scanmir | — |  | 0 | `count_data` |
| scanmirapp | — |  | 0 | `count_data` |
| scannotatr | — |  | 0 | `count_data` |
| scanvis | — |  | 0 | `count_data` |
| scarray | — |  | 0 | `count_data` |
| scarray_sat | — |  | 0 | `count_data` |
| scater | — |  | 0 | `count_data` |
| scatterhatch | — |  | 0 | `count_data` |
| scbfa | — |  | 0 | `count_data` |
| scbn | — |  | 0 | `count_data` |
| scbubbletree | — |  | 0 | `seurat` |
| sccb2 | — |  | 0 | `count_data` |
| scclassify | — |  | 0 | `count_data` |
| sccomp | — |  | 0 | `count_data` |
| scdataviz | — |  | 0 | `singlecellexperiment` |
| scdblfinder | — |  | 0 | `seurat_object` |
| scdd | — |  | 0 | `count_data` |
| scddboost | — |  | 0 | `count_data` |
| scdesign3 | — |  | 0 | `count_data` |
| scdotplot | — |  | 0 | `seurat_object` |
| scds | — |  | 0 | `count_data` |
| scfa | — |  | 0 | `count_data` |
| scfeatures | — |  | 0 | `count_data` |
| scgps | — |  | 0 | `count_data` |
| schex | — |  | 0 | `seurat` |
| schot | — |  | 0 | `count_data` |
| scider | — |  | 0 | `count_data` |
| scifer | — |  | 0 | `count_data` |
| scmap | — |  | 0 | `seurat_object` |
| scmerge | — |  | 0 | `count_data` |
| scmet | — |  | 0 | `count_data` |
| scmeth | — |  | 0 | `count_data` |
| scmitomut | — |  | 0 | `count_data` |
| scmultisim | — |  | 0 | `count_data` |
| scone | — |  | 0 | `singlecellexperiment` |
| sconify | — |  | 0 | `count_data` |
| scoreinvhap | — |  | 0 | `count_data` |
| scp | — |  | 0 | `count_data` |
| scpca | — |  | 0 | `count_data` |
| scpipe | — |  | 0 | `count_data` |
| scran | — |  | 0 | `count_data` |
| scrapper | — |  | 0 | `count_data` |
| screclassify | — |  | 0 | `count_data` |
| screcover | — |  | 0 | `count_data` |
| screencounter | — |  | 0 | `count_data` |
| screenr | — |  | 0 | `count_data` |
| screpertoire | — |  | 0 | `count_data` |
| scrnaseqapp | — |  | 0 | `count_data` |
| scruff | — |  | 0 | `count_data` |
| scry | — |  | 0 | `input_file` |
| scshapes | — |  | 0 | `count_data` |
| sctensor | — |  | 0 | `count_data` |
| sctgif | — |  | 0 | `count_data` |
| scthi | — |  | 0 | `count_data` |
| scuttle | — |  | 0 | `seurat_object` |
| scvir | — |  | 0 | `count_data` |
| sdams | — |  | 0 | `count_data` |
| seahtrue | — |  | 0 | `count_data` |
| sechm | — |  | 0 | `count_data` |
| segmenter | — |  | 0 | `count_data` |
| segmentseq | — |  | 0 | `count_data` |
| selectksigs | — |  | 0 | `count_data` |
| selex | — |  | 0 | `count_data` |
| semdist | — |  | 0 | `count_data` |
| semisup | — |  | 0 | `count_data` |
| seq2pathway | — |  | 0 | `count_data` |
| seq_hotspot | — |  | 0 | `count_data` |
| seqarchr | — |  | 0 | `count_data` |
| seqarchrplus | — |  | 0 | `count_data` |
| seqarray | — |  | 0 | `count_data` |
| seqcat | — |  | 0 | `count_data` |
| seqgate | — |  | 0 | `count_data` |
| seqgsea | — |  | 0 | `count_data` |
| seqlogo | — |  | 0 | `count_data` |
| seqpattern | — |  | 0 | `count_data` |
| seqsetvis | — |  | 0 | `count_data` |
| seqsqc | — |  | 0 | `count_data` |
| seqtools | — |  | 0 | `count_data` |
| seqvartools | — |  | 0 | `count_data` |
| sesame | — |  | 0 | `count_data` |
| setools | — |  | 0 | `count_data` |
| sevenbridges | — |  | 0 | `count_data` |
| sevenc | — |  | 0 | `count_data` |
| sgcp | — |  | 0 | `count_data` |
| sgseq | — |  | 0 | `count_data` |
| sharedobject | — |  | 0 | `count_data` |
| shiny_gosling | — |  | 0 | `count_data` |
| shinymethyl | — |  | 0 | `count_data` |
| shortread | — |  | 0 | `ggplot_object` |
| siamcat | — |  | 0 | `count_data` |
| sictools | — |  | 0 | `count_data` |
| sigcheck | — |  | 0 | `count_data` |
| sigfeature | — |  | 0 | `count_data` |
| sigfuge | — |  | 0 | `count_data` |
| siggenes | — |  | 0 | `count_data` |
| sights | — |  | 0 | `count_data` |
| signaturesearch | — |  | 0 | `summarizedexperiment` |
| signer | — |  | 0 | `count_data` |
| sigsquared | — |  | 0 | `count_data` |
| sim | — |  | 0 | `initial_conditions`, `parameters`, `ode_function`, `time_span`, `time_points` |
| simat | — |  | 0 | `count_data` |
| simbu | — |  | 0 | `count_data` |
| simd | — |  | 0 | `count_data` |
| simffpe | — |  | 0 | `bamfile` |
| similarpeak | — |  | 0 | `count_data` |
| simpic | — |  | 0 | `count_data` |
| simpleseg | — |  | 0 | `count_data` |
| sincell | — |  | 0 | `count_data` |
| singlecellalleleexperiment | — |  | 0 | `count_data` |
| singlecellexperiment | — |  | 0 | `singlecellexperiment` |
| singlecelltk | — |  | 0 | `count_data` |
| singlemoleculefootprinting | — |  | 0 | `count_data` |
| singler | — |  | 0 | `count_data` |
| singscore | — |  | 0 | `count_data` |
| sipsic | — |  | 0 | `singlecellexperiment` |
| sitadela | — |  | 0 | `count_data` |
| sitepath | — |  | 0 | `count_data` |
| sizepower | — |  | 0 | `count_data` |
| sketchr | — |  | 0 | `plot_object` |
| skewr | — |  | 0 | `count_data` |
| slalom | — |  | 0 | `count_data` |
| slqpcr | — |  | 0 | `count_data` |
| smite | — |  | 0 | `count_data` |
| smoothclust | — |  | 0 | `plot_object` |
| snagee | — |  | 0 | `count_data` |
| snapcount | — |  | 0 | `count_data` |
| snifter | — |  | 0 | `count_data` |
| snm | — |  | 0 | `count_data` |
| snpediar | — |  | 0 | `count_data` |
| snprelate | — |  | 0 | `count_data` |
| snpstats | — |  | 0 | `count_data` |
| soggi | — |  | 0 | `count_data` |
| somaticsignatures | — |  | 0 | `count_data` |
| spacemarkers | — |  | 0 | `count_data` |
| spaniel | — |  | 0 | `count_data` |
| spanorm | — |  | 0 | `count_data` |
| sparrow | — |  | 0 | `count_data` |
| sparsenetgls | — |  | 0 | `count_data` |
| sparsesignatures | — |  | 0 | `count_data` |
| spasim | — |  | 0 | `count_data` |
| spatialcpie | — |  | 0 | `count_data` |
| spatialde | — |  | 0 | `count_data` |
| spatialdecon | — |  | 0 | `count_data` |
| spatialexperiment | — |  | 0 | `count_data` |
| spatialfeatureexperiment | — |  | 0 | `count_data` |
| spatialheatmap | — |  | 0 | `count_data` |
| spatialomicsoverlay | — |  | 0 | `count_data` |
| spatialsimgp | — |  | 0 | `plot_object` |
| speckle | — |  | 0 | `count_data` |
| specl | — |  | 0 | `count_data` |
| specond | — |  | 0 | `count_data` |
| spectraql | — |  | 0 | `count_data` |
| spem | — |  | 0 | `count_data` |
| spia | — |  | 0 | `count_data` |
| spicyr | — |  | 0 | `count_data` |
| spiky | — |  | 0 | `count_data` |
| spillr | — |  | 0 | `count_data` |
| spktools | — |  | 0 | `count_data` |
| splatter | — |  | 0 | `count_data` |
| splicewiz | — |  | 0 | `count_data` |
| splicingfactory | — |  | 0 | `count_data` |
| splicinggraphs | — |  | 0 | `count_data` |
| splinetimer | — |  | 0 | `count_data` |
| splinter | — |  | 0 | `input_file` |
| splots | — |  | 0 | `count_data` |
| sponge | — |  | 0 | `count_data` |
| spoon | — |  | 0 | `count_data` |
| spotclean | — |  | 0 | `count_data` |
| spotlight | — |  | 0 | `singlecellexperiment` |
| spotsweeper | — |  | 0 | `count_data` |
| spqn | — |  | 0 | `count_data` |
| spsimseq | — |  | 0 | `count_data` |
| squallms | — |  | 0 | `count_data` |
| sradb | — |  | 0 | `count_data` |
| sseq | — |  | 0 | `count_data` |
| ssize | — |  | 0 | `count_data` |
| ssnappy | — |  | 0 | `count_data` |
| sspaths | — |  | 0 | `count_data` |
| ssrch | — |  | 0 | `count_data` |
| ssviz | — |  | 0 | `count_data` |
| stabmap | — |  | 0 | `count_data` |
| stager | — |  | 0 | `count_data` |
| standr | — |  | 0 | `count_data` |
| stategra | — |  | 0 | `count_data` |
| statial | — |  | 0 | `count_data` |
| stjoincount | — |  | 0 | `count_data` |
| strandcheckr | — |  | 0 | `count_data` |
| streamer | — |  | 0 | `count_data` |
| stringdb | — |  | 0 | `count_data` |
| struct | — |  | 0 | `dot_bracket_structure`, `sequence` |
| structstrings | — |  | 0 | `count_data` |
| structtoolbox | — |  | 0 | `count_data` |
| structuralvariantannotation | — |  | 0 | `count_data` |
| subcellbarcode | — |  | 0 | `count_data` |
| subseq | — |  | 0 | `count_data` |
| suitor | — |  | 0 | `count_data` |
| summix | — |  | 0 | `count_data` |
| supersigs | — |  | 0 | `count_data` |
| surfr | — |  | 0 | `count_data` |
| survclust | — |  | 0 | `count_data` |
| survcomp | — |  | 0 | `count_data` |
| survival | — |  | 0 | `clinical_csv` |
| sva | — |  | 0 | `count_data` |
| svanumt | — |  | 0 | `count_data` |
| svaretro | — |  | 0 | `count_data` |
| swath2stats | — |  | 0 | `count_data` |
| swathxtend | — |  | 0 | `count_data` |
| swfdr | — |  | 0 | `count_data` |
| switchbox | — |  | 0 | `count_data` |
| switchde | — |  | 0 | `singlecellexperiment` |
| synapsis | — |  | 0 | `count_data` |
| synapter | — |  | 0 | `count_data` |
| synergyfinder | — |  | 0 | `count_data` |
| synextend | — |  | 0 | `count_data` |
| synlet | — |  | 0 | `count_data` |
| synmut | — |  | 0 | `count_data` |
| syntenet | — |  | 0 | `count_data` |
| systempiper | — |  | 0 | `count_data` |
| systempipeshiny | — |  | 0 | `count_data` |
| systempipetools | — |  | 0 | `count_data` |
| tadar | — |  | 0 | `count_data` |
| tanggle | — |  | 0 | `count_data` |
| tapseq | — |  | 0 | `count_data` |
| target | — |  | 0 |  |
| targetdecoy | — |  | 0 | `count_data` |
| targetscore | — |  | 0 | `count_data` |
| targetsearch | — |  | 0 | `count_data` |
| tcc | — |  | 0 | `model_object` |
| tcgautils | — |  | 0 | `count_data` |
| tcseq | — |  | 0 | `count_data` |
| tdbasedufe | — |  | 0 | `count_data` |
| tdbasedufeadv | — |  | 0 | `count_data` |
| tekrabber | — |  | 0 | `count_data` |
| tenxio | — |  | 0 | `count_data` |
| tenxplore | — |  | 0 | `count_data` |
| teqc | — |  | 0 | `count_data` |
| ternarynet | — |  | 0 | `count_data` |
| terratcgadata | — |  | 0 | `count_data` |
| tfarm | — |  | 0 | `count_data` |
| tfbstools | — |  | 0 | `count_data` |
| tfhaz | — |  | 0 | `count_data` |
| tfutils | — |  | 0 | `count_data` |
| tidybulk | — |  | 0 | `count_data` |
| tidycoverage | — |  | 0 | `count_data` |
| tidyflowcore | — |  | 0 | `count_data` |
| tidysbml | — |  | 0 | `count_data` |
| tidysinglecellexperiment | — |  | 0 | `count_data` |
| tidyspatialexperiment | — |  | 0 | `count_data` |
| tidysummarizedexperiment | — |  | 0 | `count_data` |
| tidytof | — |  | 0 | `count_data` |
| tigre | — |  | 0 | `count_data` |
| tiledbarray | — |  | 0 | `count_data` |
| tilingarray | — |  | 0 | `count_data` |
| timecourse | — |  | 0 | `count_data` |
| timeomics | — |  | 0 | `count_data` |
| tin | — |  | 0 | `guide_rna_sequences`, `target_genomic_loci`, `cell_tissue_type` |
| titancna | — |  | 0 | `count_data` |
| tkwidgets | — |  | 0 | `count_data` |
| tloh | — |  | 0 | `count_data` |
| tmixclust | — |  | 0 | `count_data` |
| tmsig | — |  | 0 | `count_data` |
| tnt | — |  | 0 | `question`, `sequence`, `device` |
| toast | — |  | 0 | `count_data` |
| tomoda | — |  | 0 | `count_data` |
| tomoseqr | — |  | 0 | `count_data` |
| top | — |  | 0 | `bam`, `fasta`, `gtf` |
| topconfects | — |  | 0 | `count_data` |
| topdownr | — |  | 0 | `count_data` |
| topgo | — |  | 0 | `count_data` |
| tpsvg | — |  | 0 | `singlecellexperiment` |
| tracktables | — |  | 0 | `count_data` |
| trackviewer | — |  | 0 | `count_data` |
| trajectorygeometry | — |  | 0 | `count_data` |
| trajectoryutils | — |  | 0 | `count_data` |
| transcriptr | — |  | 0 | `count_data` |
| transformgampoi | — |  | 0 | `singlecellexperiment` |
| translatome | — |  | 0 | `count_data` |
| transmogr | — |  | 0 | `count_data` |
| traser | — |  | 0 | `count_data` |
| treeclimbr | — |  | 0 | `count_data` |
| treeio | — |  | 0 | `count_data` |
| treekor | — |  | 0 | `count_data` |
| treesummarizedexperiment | — |  | 0 | `count_data` |
| treg | — |  | 0 | `count_data` |
| tricycle | — |  | 0 | `count_data` |
| trigger | — |  | 0 | `count_data` |
| trio | — |  | 0 | `count_data` |
| triplex | — |  | 0 | `count_data` |
| tripr | — |  | 0 | `count_data` |
| trna | — |  | 0 | `count_data` |
| trnadbimport | — |  | 0 | `count_data` |
| trnascanimport | — |  | 0 | `count_data` |
| tronco | — |  | 0 | `count_data` |
| tscan | — |  | 0 | `count_data` |
| ttmap | — |  | 0 | `count_data` |
| turbonorm | — |  | 0 | `count_data` |
| tvtb | — |  | 0 | `vcf` |
| tweedeseq | — |  | 0 | `count_data` |
| twilight | — |  | 0 | `count_data` |
| twoddpcr | — |  | 0 | `count_data` |
| txcutr | — |  | 0 | `count_data` |
| txdbmaker | — |  | 0 | `count_data` |
| tximeta | — |  | 0 | `count_data` |
| tximport | — |  | 0 | `count_data` |
| ucell | — |  | 0 | `count_data` |
| ucsc_utils | — |  | 0 | `count_data` |
| umi4cats | — |  | 0 | `count_data` |
| undo | — |  | 0 | `count_data` |
| unifiedwmwqpcr | — |  | 0 | `count_data` |
| uniprot_ws | — |  | 0 | `count_data` |
| updhmm | — |  | 0 | `count_data` |
| usort | — |  | 0 | `count_data` |
| vanillaice | — |  | 0 | `count_data` |
| variantannotation | — |  | 0 | `count_data` |
| variantexperiment | — |  | 0 | `count_data` |
| variantfiltering | — |  | 0 | `count_data` |
| varianttools | — |  | 0 | `vcf_object` |
| vasp | — |  | 0 | `count_data` |
| vbmp | — |  | 0 | `count_data` |
| vcfarray | — |  | 0 | `count_data` |
| vegamc | — |  | 0 | `count_data` |
| velociraptor | — |  | 0 | `count_data` |
| veloviz | — |  | 0 | `count_data` |
| venndetail | — |  | 0 | `count_data` |
| vidger | — |  | 0 | `count_data` |
| viper | — |  | 0 | `count_data` |
| visiumio | — |  | 0 | `count_data` |
| visse | — |  | 0 | `count_data` |
| voyager | — |  | 0 | `count_data` |
| vplotr | — |  | 0 | `plot_object` |
| vsclust | — |  | 0 | `count_data` |
| vsn | — |  | 0 | `count_data` |
| vtpnet | — |  | 0 | `count_data` |
| vulcan | — |  | 0 | `count_data` |
| watermelon | — |  | 0 | `count_data` |
| weaver | — |  | 0 | `count_data` |
| weitrix | — |  | 0 | `marraylm` |
| widgettools | — |  | 0 | `count_data` |
| wiggleplotr | — |  | 0 | `count_data` |
| wpm | — |  | 0 | `count_data` |
| wppi | — |  | 0 | `count_data` |
| xcms | — |  | 0 | `count_data` |
| xcore | — |  | 0 | `count_data` |
| xde | — |  | 0 | `count_data` |
| xenlite | — |  | 0 | `count_data` |
| xeva | — |  | 0 | `count_data` |
| xina | — |  | 0 | `count_data` |
| xmapbridge | — |  | 0 | `count_data` |
| yamss | — |  | 0 | `count_data` |
| yapsa | — |  | 0 | `count_data` |
| yarn | — |  | 0 | `count_data` |
| zellkonverter | — |  | 0 | `count_data` |
| zenith | — |  | 0 | `count_data` |
| zfpkm | — |  | 0 | `summarizedexperiment` |
| zinbwave | — |  | 0 | `dgelist` |
| zitools | — |  | 0 | `count_data` |
| zygositypredictor | — |  | 0 | `count_data` |

## bioengineering

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| analyze_calcium_imaging_data | — |  | 3 |  |
| analyze_cell_migration_metrics | — |  | 6 |  |
| analyze_in_vitro_drug_release_kinetics | — |  | 6 |  |
| analyze_myofiber_morphology | — |  | 6 |  |
| decode_behavior_from_neural_trajectories | — |  | 5 |  |
| default_whole_cell_model | — |  | 4 |  |
| exp_decay | — |  | 4 |  |
| first_order | — |  | 5 |  |
| higuchi | — |  | 3 |  |
| korsmeyer_peppas | — |  | 4 |  |
| perform_crispr_cas9_genome_editing | — |  | 4 |  |
| simulate_whole_cell_ode_model | — |  | 7 |  |
| zero_order | — |  | 3 |  |

## bioimaging

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| batch_register_images | — |  | 12 |  |
| calculate_similarity_metrics | — |  | 3 |  |
| check_model_files_exist | — |  | 3 |  |
| command_iteration | — |  | 1 |  |
| create_affine_transform | — |  | 4 |  |
| create_deformable_transform | — |  | 4 |  |
| create_rigid_transform | — |  | 4 |  |
| create_segmentation_visualization | — |  | 4 |  |
| load_image | — |  | 2 |  |
| patched_torch_load | — |  | 1 |  |
| prepare_input_for_nnunet | — |  | 4 |  |
| preprocess_image | — |  | 5 |  |
| quick_affine_registration | — |  | 11 |  |
| quick_deformable_registration | — |  | 12 |  |
| quick_rigid_registration | — |  | 11 |  |
| register_images | — |  | 5 | `fixed_image_path`, `moving_images_dir`, `output_dir`, `transform_type`, `metric` |
| save_image | — |  | 3 |  |
| segment_with_nn_unet | — |  | 12 |  |
| setup_nnunet_environment | — |  | 4 |  |
| setup_registration_method | — |  | 7 |  |
| split_modalities | — |  | 4 |  |
| verify_nifti_input | — |  | 2 |  |

## biophysics

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| analyze_cell_morphology_and_cytoskeleton | — |  | 4 |  |
| analyze_tissue_deformation_flow | — |  | 4 |  |

## cancer_biology

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| analyze_cell_senescence_and_apoptosis | — |  | 2 |  |
| analyze_copy_number_purity_ploidy_and_focal_events | — |  | 11 |  |
| analyze_ddr_network_in_cancer | — |  | 4 |  |
| detect_and_annotate_somatic_mutations | — |  | 6 |  |
| detect_and_characterize_structural_variations | — |  | 6 |  |
| norm_chr | — |  | 3 |  |
| perform_gene_expression_nmf_analysis | — |  | 6 |  |

## cell_biology

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| analyze_flow_cytometry_immunophenotyping | — |  | 5 |  |
| analyze_mitochondrial_morphology_and_potential | — |  | 4 |  |
| perform_facs_cell_sorting | — |  | 6 |  |
| quantify_and_cluster_cell_motility | — |  | 4 |  |
| quantify_cell_cycle_phases_from_microscopy | — |  | 3 |  |

## cryo_em

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| 3d_variability_analysis | — |  | 7 |  |
| 3d_variability_pipeline | — |  | 9 |  |
| cryosparc_standard_spa | — | ✓ | 46 | `micrograph_movies`, `gain_reference` |
| filament_tracer | — |  | 6 |  |
| focused_refinement_pipeline | — |  | 8 |  |
| global_ctf_refinement | — |  | 6 |  |
| helical_refinement | — |  | 7 |  |
| helical_spa_pipeline | — |  | 15 | `micrograph_movies` |
| import_micrographs | — |  | 7 |  |
| import_particles | — |  | 8 |  |
| local_refinement | — |  | 6 |  |
| particle_subtraction | — |  | 4 |  |
| symmetry_expansion | — |  | 4 |  |
| topaz_extract | — |  | 4 |  |
| topaz_train | — |  | 6 |  |

## cryo_et

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| et_full_pipeline | — |  | 22 | `tilt_series` |
| import_tiltseries | — |  | 10 |  |
| subtomogram_averaging | — |  | 6 |  |
| tilt_alignment | — |  | 4 |  |
| tomogram_reconstruction | — |  | 5 |  |

## database

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| blast_sequence | — |  | 4 |  |
| get_genes_near_ccre | — |  | 5 |  |
| get_hpo_names | — |  | 3 |  |
| reduce_tokens | — |  | 4 |  |
| region_to_ccre_screen | — |  | 5 |  |

## drug_discovery

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| ADMET_pred | — |  | 3 |  |
| adaptive_trial_design | — |  | 12 | `json` |
| aizynthfinder_retrosynthesis | `seed_smiles` |  | 10 | `mock_mode` |
| alphafold_db_search | `query_pdb` |  | 7 | `pdb`, `cif`, `fasta` |
| amber_pmemd_md | `receptor`, `ligand` |  | 17 | `pdb`, `mol2`, `sdf` |
| apply_vcog_grade | — |  | 5 |  |
| assay_ingestion_and_ranking | `assay_csv` |  | 9 | `compound_data` |
| bispecific_antibody_design | — |  | 14 |  |
| clinical_trial_simulation | — |  | 21 | `json` |
| covalent_warhead_design | — |  | 5 | `smiles` |
| cro_submission_export | `compound_csv` |  | 8 | `smiles`, `assay_data` |
| cyp_ddi_panel | `smiles` |  | 21 |  |
| docking_autodock_vina | — |  | 10 |  |
| drug_moa_rnaseq | `treated_counts`, `control_counts` |  | 8 | `mock_mode` |
| drugclip_virtual_screening | — |  | 7 | `pdb`, `smi` |
| fcrn_antibody_pk | — |  | 11 |  |
| gromacs_protein_md | `receptor`, `ligand` |  | 28 | `pdb`, `sdf`, `mol2` |
| hts_plate_qc_hit_calling | — |  | 6 | `json` |
| ich_s5_reproductive_tox | — |  | 14 |  |
| ich_s7a_safety_pharmacology | — |  | 8 |  |
| ivive_hepatic_clearance | — |  | 8 |  |
| lnp_formulation_optimization | — |  | 6 | `smiles` |
| moe_covalent_docking | `receptor`, `ligands` |  | 11 | `pdb`, `mol2`, `sdf`, `smi` |
| nca_pknca | `input_csv` |  | 7 | `mock_mode` |
| nonmem_poppk | — |  | 18 |  |
| openfe_rbfe | `receptor`, `ligand_a`, `ligand_b` |  | 21 |  |
| p0_docking_validation | — |  | 9 |  |
| p0_mrna_validation | — |  | 6 |  |
| p0_pharmacophore_validation | — |  | 3 |  |
| p0_pkpd_semaglutide | — |  | 18 |  |
| pbpk_pediatric | — |  | 11 | `json` |
| pbpk_simulation | — |  | 15 | `json` |
| pharmacophore_filtering | `reference_actives`, `compound_library` |  | 6 | `mock_mode` |
| pk_sim_pbpk | — |  | 19 |  |
| pocket_detection_druggability | `pdb_input` |  | 6 | `mock_mode` |
| predict_admet_properties | — |  | 3 |  |
| proteome_selectivity_profiling | — |  | 6 | `smiles` |
| reinvent4_lead_design | `seed_smiles`, `receptor`, `custom_toml` |  | 22 | `smiles` |
| scaffold_hopping | — |  | 6 | `mock_mode` |
| scfv_antibody_design | — |  | 7 | `pdb` |
| schrodinger_glide_docking | `receptor`, `ligands` |  | 17 | `pdb`, `mol2`, `sdf`, `smi` |
| simcyp_pbpk | — |  | 19 |  |
| sirna_offtarget_analysis | — |  | 11 |  |
| structure_prediction_docking | — |  | 13 | `mock_mode`, `prediction_tool`, `boltz2_api_key`, `boltz2_mode`, `boltz2_model_dir` |
| survival_analysis_km | — |  | 16 |  |
| syncraft_synthesizability | — |  | 7 | `smiles`, `smi` |
| target_engagement_kinetics | — |  | 10 | `smiles` |
| target_tractability_scorer | — |  | 10 | `json` |
| transporter_ddi_pgp_bcrp | — |  | 20 |  |

## genetics

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| analyze_cas9_mutation_outcomes | — |  | 5 |  |
| analyze_crispr_genome_editing | — |  | 5 |  |
| analyze_protein_phylogeny | — |  | 5 |  |
| bayesian_finemapping_with_deep_vi | — |  | 7 |  |
| elbo_loss | — |  | 4 |  |
| fit_genomic_prediction_model | — |  | 6 |  |
| forward | — |  | 5 |  |
| identify_transcription_factor_binding_sites | — |  | 5 |  |
| liftover_coordinates | — |  | 6 |  |
| perform_pcr_and_gel_electrophoresis | — |  | 10 |  |
| simulate_demographic_history | — |  | 11 |  |

## genomics

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| alphagenome_track_prediction | — |  | 9 |  |
| analyze_chromatin_interactions | — |  | 5 |  |
| analyze_comparative_genomics_and_haplotypes | — |  | 4 |  |
| analyze_genomic_region_overlap | — |  | 3 |  |
| annotate_celltype_scRNA | — |  | 8 |  |
| annotate_celltype_with_panhumanpy | — |  | 6 |  |
| check_ensembl_patterns | — |  | 3 |  |
| conda_env_exists | — |  | 2 |  |
| create_harmony_embeddings_scRNA | — |  | 4 |  |
| create_panhumanpy_env | — |  | 3 |  |
| create_scvi_embeddings_scRNA | — |  | 5 |  |
| crispr_screen_mageck | — |  | 12 |  |
| custom_mode | — |  | 3 |  |
| evo2_variant_effect | — |  | 8 |  |
| find_enriched_motifs_with_homer | — |  | 8 |  |
| gene_set_enrichment_analysis | — |  | 6 |  |
| generate_embeddings_with_state | — |  | 9 |  |
| generate_gene_embeddings_with_ESM_models | — |  | 7 |  |
| generate_transcriptformer_embeddings | — |  | 19 |  |
| geo_data_connector | — |  | 3 | `mock_mode` |
| get_gene_set_enrichment_analysis_supported_database_list | — |  | 1 |  |
| get_matrix | — |  | 6 |  |
| get_rna_seq_archs4 | — |  | 3 |  |
| get_uce_embeddings_scRNA | — |  | 5 |  |
| haplotypecaller_simple | — |  | 5 |  |
| interspecies_gene_conversion | — |  | 4 |  |
| is_model_downloaded | — |  | 3 |  |
| mafft_alignment | — |  | 3 |  |
| map_to_ima_interpret_scRNA | — |  | 4 |  |
| perform_chipseq_peak_calling_with_macs2 | — |  | 6 |  |
| perturb_seq_analysis | — |  | 9 | `mock_mode` |
| phykit_metrics | — |  | 3 |  |
| trajectory_inference | `adata_h5ad` |  | 5 | `mock_mode` |
| transcriptomic_biomarker | `expression_matrix`, `metadata` |  | 13 | `mock_mode` |
| unsupervised_celltype_transfer_between_scRNA_datasets | — |  | 19 |  |
| wgs_germline_gatk | `reads`, `reference`, `known_sites` |  | 20 | `mock_mode` |

## glycoengineering

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| find_n_glycosylation_motifs | — |  | 3 |  |
| list_glycoengineering_resources | — |  | 1 |  |
| predict_o_glycosylation_hotspots | — |  | 5 |  |

## immunology

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| analyze_atac_seq_differential_accessibility | — |  | 7 |  |
| analyze_bacterial_growth_curve | — |  | 5 |  |
| analyze_cfse_cell_proliferation | — |  | 4 |  |
| analyze_cns_lesion_histology | — |  | 4 |  |
| analyze_cytokine_production_in_cd4_tcells | — |  | 3 |  |
| analyze_ebv_antibody_titers | — |  | 5 |  |
| analyze_immunohistochemistry_image | — |  | 4 |  |
| estimate_cell_cycle_phase_durations | — |  | 3 |  |
| isolate_purify_immune_cells | — |  | 6 |  |
| logistic_growth | — |  | 4 |  |
| objective_function | — |  | 4 |  |
| simulate_cell_population | — |  | 5 |  |
| track_immune_cells_under_flow | — |  | 6 |  |

## lab_automation

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| get_pylabrobot_documentation_liquid | — |  | 1 |  |
| get_pylabrobot_documentation_material | — |  | 1 |  |
| html_output_test | — |  | 2 |  |
| pick_first | — |  | 2 |  |
| run_async | — |  | 1 |  |
| target | — |  | 1 |  |
| test_pylabrobot_script | — |  | 6 |  |

## literature

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| advanced_web_search_claude | — |  | 3 |  |
| extract_pdf_content | — |  | 2 |  |
| extract_url_content | — |  | 2 |  |
| fetch_supplementary_info_from_doi | — |  | 3 |  |

## microbiology

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| analyze_arsenic_speciation_hplc_icpms | — |  | 4 |  |
| annotate_bacterial_genome | — |  | 7 |  |
| bacterial_dynamics | — |  | 5 |  |
| count_bacterial_colonies | — |  | 5 |  |
| enumerate_bacterial_cfu_by_serial_dilution | — |  | 7 |  |
| glv_equations | — |  | 4 |  |
| methane_yield_model | — |  | 4 |  |
| model_bacterial_growth_dynamics | — |  | 7 |  |
| optimize_anaerobic_digestion_process | — |  | 5 |  |
| predict_rna_secondary_structure | — |  | 3 |  |
| quantify_biofilm_biomass_crystal_violet | — |  | 5 |  |
| segment_and_analyze_microbial_cells | — |  | 4 |  |
| segment_cells_with_deep_learning | — |  | 5 |  |
| simulate_generalized_lotka_volterra_dynamics | — |  | 6 |  |
| simulate_microbial_population_dynamics | — |  | 8 |  |
| vfa_production_model | — |  | 4 |  |

## molecular_biology

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| align_sequences | — |  | 3 |  |
| annotate_open_reading_frames | — |  | 5 |  |
| annotate_plasmid | — |  | 3 |  |
| design_golden_gate_oligos | — |  | 5 |  |
| design_knockout_sgrna | — |  | 5 |  |
| design_primer | — |  | 9 |  |
| design_verification_primers | — |  | 11 |  |
| digest_sequence | — |  | 4 |  |
| find_orfs_in_frame | — |  | 5 |  |
| find_restriction_enzymes | — |  | 3 |  |
| find_restriction_sites | — |  | 4 |  |
| find_sequence_mutations | — |  | 4 |  |
| get_bacterial_transformation_protocol | — |  | 3 |  |
| get_coding_sequences | — |  | 4 |  |
| get_gene_coding_sequence | — |  | 4 |  |
| get_golden_gate_assembly_protocol | — |  | 7 |  |
| get_oligo_annealing_protocol | — |  | 1 |  |
| get_plasmid_sequence | — |  | 3 |  |
| get_refseq_id | — |  | 4 |  |
| golden_gate_assembly | — |  | 5 | `num_inserts`, `vector_length`, `vector_amount_ng`, `insert_lengths`, `is_library_prep` |
| is_position_covered | — |  | 4 |  |
| is_region_fully_covered | — |  | 5 |  |
| merge_overlapping_regions | — |  | 2 |  |
| pcr_simple | — |  | 5 |  |
| reverse_complement | — |  | 2 |  |
| search_gene | — |  | 4 |  |

## multi_omics

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| lc_ms_proteomics_metabolomics | — |  | 13 |  |

## pathology

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| analyze_aortic_diameter_and_geometry | — |  | 3 |  |
| analyze_atp_luminescence_assay | — |  | 5 |  |
| analyze_bone_microct_morphometry | — |  | 4 |  |
| analyze_intracellular_calcium_with_rhod2 | — |  | 5 |  |
| analyze_thrombus_histology | — |  | 3 |  |
| quantify_corneal_nerve_fibers | — |  | 5 |  |
| segment_and_quantify_cells_in_multiplexed_images | — |  | 5 |  |

## pharmacology

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| ADMET_pred | — |  | 3 |  |
| allometric_scaling | — |  | 6 | `json` |
| analyze_accelerated_stability_of_pharmaceutical_formulations | — |  | 4 |  |
| analyze_fda_safety_signals | — |  | 4 |  |
| analyze_interaction_mechanisms | — |  | 4 |  |
| analyze_radiolabeled_antibody_biodistribution | — |  | 3 |  |
| analyze_western_blot | — |  | 6 |  |
| analyze_xenograft_tumor_growth_inhibition | — |  | 7 |  |
| antibody_developability | — |  | 11 | `json` |
| apply_vcog_grade | — |  | 5 |  |
| bi_exp_model | — |  | 6 |  |
| biomarker_patient_enrichment | — |  | 6 | `json` |
| calculate_physicochemical_properties | — |  | 2 |  |
| check_drug_combination_safety | — |  | 5 |  |
| check_fda_drug_recalls | — |  | 4 |  |
| cns_penetration_prediction | — |  | 6 | `smiles` |
| dart_toxicity_prediction | — |  | 4 | `smiles` |
| docking_autodock_vina | — |  | 10 |  |
| estimate_alpha_particle_radiotherapy_dosimetry | — |  | 4 |  |
| exposure_response_modeling | `patient_data_csv` |  | 7 | `csv` |
| exposure_response_modelling | — |  | 7 | `json` |
| find_alternative_drugs_ddinter | — |  | 5 |  |
| genotoxicity_ames_prediction | — |  | 2 | `smiles` |
| get_fda_drug_label_info | — |  | 3 |  |
| grade_adverse_events_using_vcog_ctcae | — |  | 2 |  |
| herg_cardiac_safety_qsar | — |  | 6 | `smiles` |
| ivive_hepatic_clearance | — |  | 8 |  |
| membrane_permeability_prediction | — |  | 5 | `smiles` |
| metabolite_prediction_biotransformer | — |  | 5 | `smiles`, `json` |
| nanoparticle_pk_biodistribution | — |  | 9 | `json` |
| nlmixr2_population_pk | `pk_data_csv` |  | 7 |  |
| oral_absorption_bcs_model | — |  | 8 | `smiles` |
| pbpk_disease_state | — |  | 10 | `json` |
| pbpk_pediatric_pregnancy | — |  | 10 | `json` |
| perform_mwas_cyp2c19_metabolizer_status | — |  | 6 |  |
| pharmacogenomics_pgx_report | — |  | 4 | `json` |
| phase2_dose_justification | — |  | 11 | `json` |
| polymorph_stability_screening | — |  | 5 |  |
| predict_admet_properties | — |  | 3 |  |
| predict_binding_affinity_protein_1d_sequence | — |  | 4 |  |
| qsar_rf_model | `input_csv` |  | 7 |  |
| repeated_dose_tox_prediction | — |  | 6 | `smiles` |
| retrieve_topk_repurposing_drugs_from_disease_txgnn | — |  | 4 |  |
| run_3d_chondrogenic_aggregate_assay | — |  | 5 |  |
| run_autosite | — |  | 4 |  |
| run_diffdock_with_smiles | — |  | 6 |  |
| sigmoid | — |  | 2 |  |
| transporter_ddi_prediction | — |  | 4 | `smiles` |

## physiology

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| analyze_abr_waveform_p1_metrics | — |  | 3 |  |
| analyze_ciliary_beat_frequency | — |  | 6 |  |
| analyze_endolysosomal_calcium_dynamics | — |  | 7 |  |
| analyze_fatty_acid_composition_by_gc | — |  | 5 |  |
| analyze_hemodynamic_data | — |  | 4 |  |
| analyze_protein_colocalization | — |  | 5 |  |
| calculate_brain_adc_map | — |  | 5 |  |
| cosinor_model | — |  | 6 |  |
| mono_exp_model | — |  | 4 |  |
| perform_cosinor_analysis | — |  | 4 |  |
| pk_ode_system | — |  | 5 |  |
| quantify_amyloid_beta_plaques | — |  | 6 |  |
| reconstruct_3d_face_from_mri | — |  | 5 |  |
| simulate_thyroid_hormone_pharmacokinetics | — |  | 5 |  |

## proteomics

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| chemoproteomics_pulldown | `input_file` |  | 6 |  |
| profam_fitness_prediction | — |  | 6 | `fasta`, `csv` |
| protrek_protein_search | — |  | 8 | `text`, `fasta`, `pdb` |

## single_cell

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| bd_rhapsody_scrna | — |  | 9 |  |
| cite_seq_preprocessing | — |  | 13 |  |
| merfish_spatial_analysis | — |  | 10 |  |
| multiome_rna_atac | — |  | 10 |  |
| parse_split_seq_scrna | — |  | 7 |  |
| scrna_doublet_qc | — |  | 9 |  |
| state_perturbation_prediction | — |  | 10 | `h5ad` |

## structural_biology

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| boltz_structure_prediction | — |  | 8 | `fasta`, `yaml` |
| chai1_structure_prediction | — |  | 6 | `fasta` |

## synthetic_biology

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| analyze_bacterial_growth_rate | — |  | 5 |  |
| analyze_barcode_sequencing_data | — |  | 7 |  |
| analyze_bifurcation_diagram | — |  | 5 |  |
| create_biochemical_network_sbml_model | — |  | 4 |  |
| engineer_bacterial_genome_for_therapeutic_delivery | — |  | 3 |  |
| gene_circuit_odes | — |  | 7 |  |
| gompertz_model | — |  | 5 |  |
| hamming_distance | — |  | 3 |  |
| optimize_codons_for_heterologous_expression | — |  | 3 |  |
| simulate_gene_circuit_with_growth_feedback | — |  | 6 |  |

## systems_biology

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| compare_protein_structures | — |  | 6 |  |
| dimerization_odes | — |  | 6 |  |
| hill_function | — |  | 4 |  |
| mass_action_kinetics | — |  | 3 |  |
| model_protein_dimerization_network | — |  | 4 |  |
| ode_system | — |  | 4 | `c`, `ka`, `ke`, `vd` |
| perform_flux_balance_analysis | — |  | 5 |  |
| query_chatnt | — |  | 4 |  |
| ras_ode_system | — |  | 5 |  |
| simulate_metabolic_network_perturbation | — |  | 6 |  |
| simulate_protein_signaling_network | — |  | 6 |  |
| simulate_renin_angiotensin_system_dynamics | — |  | 6 |  |

## virtual_cell

| Workflow | Required | mock? | declared | DB-only (hallucinated) |
|---|---|---|---|---|
| cipa_cardiac_safety_ode | — |  | 11 |  |
| cpa_drug_combination_synergy | — |  | 11 |  |
| cpa_synergy_gpu | — |  | 13 |  |
| gears_perturbation_gpu | — |  | 10 |  |
| gears_perturbation_prediction | — |  | 8 |  |
| metabolic_flux_fba | — |  | 12 |  |
| ode_signaling_simulation | — |  | 11 |  |
| physicell_tumor_tgi | — |  | 15 |  |
| transcriptformer_cell_state | — |  | 9 |  |
| transcriptformer_gpu | — |  | 10 |  |
| transcriptomic_moa_lincs | — |  | 9 |  |
| virtual_patient_cohort | — |  | 22 |  |
