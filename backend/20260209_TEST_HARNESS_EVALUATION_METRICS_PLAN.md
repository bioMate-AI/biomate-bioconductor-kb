# Test Harness Evaluation Metrics & Benchmark Datasets Plan

**Date**: February 9, 2026
**Strategy**: Extend existing test harness (Option A)
**Purpose**: Parameter optimization with credible evaluation metrics

---

## Critical Requirements

### 1. Benchmark Datasets (for validation & comparison)
- Well-established datasets with authority
- Published with citations
- Ground truth annotations available
- Used by community for method comparison

### 2. Quality Metrics (for new user data)
- **No gold standard required** - works on any data
- Well-established in field
- Published evaluation standards
- Community consensus on interpretation

---

## Domain-Specific Evaluation Strategies

### GENOMICS

#### A. ChIP-seq

**Benchmark Datasets**:
1. **ENCODE Tier 1 Cell Lines**
   - **Source**: ENCODE Consortium
   - **Citation**: ENCODE Project Consortium (2012). Nature 489:57-74
   - **Data**: H3K27ac, H3K4me3, CTCF in GM12878, K562, H1-hESC
   - **Gold Standard**: Manual validation + replication concordance
   - **URL**: https://www.encodeproject.org/
   - **Use**: Validate peak calling parameters

2. **ChIP-seq Benchmark (Landt et al.)**
   - **Citation**: Landt et al. (2012). Genome Research 22:1813-1831
   - **Data**: Multiple TFs and histone marks
   - **Standards**: ENCODE ChIP-seq guidelines
   - **Metrics**: IDR (Irreproducible Discovery Rate)

**Quality Metrics (No Gold Standard Needed)**:
1. **NSC (Normalized Strand Cross-correlation)**
   - **Formula**: NSC = (max_cc - min_cc) / min_cc
   - **Citation**: Kharchenko et al. (2008). Nature Biotech 26:1351-1359
   - **Interpretation**:
     - NSC < 1.05: Very low quality
     - NSC 1.05-1.10: Acceptable
     - NSC > 1.10: Good quality
   - **Why**: Measures signal-to-noise, data-intrinsic

2. **RSC (Relative Strand Cross-correlation)**
   - **Formula**: RSC = (phantomPeak_cc - min_cc) / (fragLen_cc - min_cc)
   - **Citation**: Same as NSC
   - **Interpretation**:
     - RSC < 0.8: Very low quality
     - RSC 0.8-1.0: Acceptable
     - RSC > 1.0: Good quality
   - **Why**: Measures enrichment signal strength

3. **FRiP (Fraction of Reads in Peaks)**
   - **Citation**: ENCODE Guidelines
   - **Interpretation**:
     - FRiP < 1%: Poor enrichment
     - FRiP 1-5%: Acceptable for broad marks
     - FRiP > 5%: Good enrichment
   - **Why**: Direct measure of IP enrichment

4. **Library Complexity (PCR Bottleneck Coefficient)**
   - **Tool**: Picard MarkDuplicates
   - **Citation**: ENCODE Best Practices
   - **Interpretation**: PBC1 > 0.9 (good), PBC1 < 0.7 (concerning)

**Parameter Optimization Strategy**:
```python
# Optimize extsize for MACS2
search_space = [100, 150, 200, 250, 300, 350, 400]
for extsize in search_space:
    run_macs2(extsize=extsize)
    metrics = {
        "nsc": calculate_nsc(bam),
        "rsc": calculate_rsc(bam),
        "frip": calculate_frip(peaks, bam),
        "num_peaks": count_peaks(peaks)
    }
    score = weighted_score(metrics)  # NSC*0.3 + RSC*0.3 + FRiP*0.4

optimal_extsize = max(scores)
```

#### B. RNA-seq

**Benchmark Datasets**:
1. **SEQC/MAQC-III**
   - **Citation**: SEQC Consortium (2014). Nature Biotech 32:903-914
   - **Data**: Universal Human Reference RNA (UHRR) vs. Human Brain Reference (HBR)
   - **Gold Standard**: qRT-PCR validation of 1000 genes
   - **Use**: Validate quantification accuracy

2. **ERCC Spike-ins**
   - **Citation**: External RNA Controls Consortium (2005). BMC Genomics 6:150
   - **Data**: 92 synthetic transcripts with known concentrations
   - **Use**: Assess quantification linearity and accuracy

**Quality Metrics (No Gold Standard)**:
1. **Mapping Rate**
   - **Tool**: STAR, HISAT2 alignment logs
   - **Citation**: RNA-SeQC (DeLuca et al., 2012)
   - **Interpretation**:
     - Mapping rate < 70%: Poor quality
     - Mapping rate 70-85%: Acceptable
     - Mapping rate > 85%: Good quality

2. **Gene Body Coverage Uniformity**
   - **Tool**: RSeQC, RNA-SeQC
   - **Citation**: Wang et al. (2012). Bioinformatics 28:2184-2185
   - **Metric**: 5'/3' bias score
   - **Interpretation**: Ratio close to 1.0 = uniform coverage

3. **Exonic/Intronic/Intergenic Ratio**
   - **Expected**: ~80% exonic, ~15% intronic, ~5% intergenic
   - **Deviation indicates**: Genomic contamination or fragmentation issues

4. **Detected Genes**
   - **Typical**: 15,000-20,000 genes in human
   - **Too few**: Library complexity issues
   - **Too many**: Noise/contamination

#### C. Variant Calling (WGS/WES)

**Benchmark Datasets**:
1. **Genome in a Bottle (GIAB)**
   - **Citation**: Zook et al. (2014). Nature Biotech 32:246-251
   - **Data**: NA12878, HG002-HG007 with high-confidence calls
   - **Gold Standard**: Integration of multiple technologies
   - **URL**: https://www.nist.gov/programs-projects/genome-bottle
   - **Use**: Validate variant calling accuracy

2. **Platinum Genomes**
   - **Citation**: Eberle et al. (2017). Genome Biology 18:64
   - **Data**: 17-member pedigree with inheritance-based validation
   - **Use**: Validate Mendelian consistency

**Quality Metrics (No Gold Standard)**:
1. **Ti/Tv Ratio (Transition/Transversion)**
   - **Expected**:
     - WGS: 2.0-2.1
     - WES: 2.8-3.0
   - **Citation**: 1000 Genomes Project (2015)
   - **Why**: Fundamental property of mutation spectrum
   - **Deviation indicates**: Sequencing errors or poor filtering

2. **Het/Hom Ratio**
   - **Expected**: ~1.5-2.0 for human
   - **Deviation indicates**: Contamination or relatedness issues

3. **Singleton Ratio**
   - **Expected**: ~10-15% of variants
   - **Too high**: False positives
   - **Too low**: Over-filtering

---

### CRYO-EM

#### A. Single Particle Analysis (SPA)

**Benchmark Datasets**:
1. **EMPIAR Repository**
   - **Citation**: Iudin et al. (2016). Nature Methods 13:387-388
   - **Example**: EMPIAR-10028 (β-galactosidase, 2.2Å)
   - **Gold Standard**: Published high-resolution structures
   - **URL**: https://www.ebi.ac.uk/empiar/
   - **Use**: Validate reconstruction quality

2. **EMDB Validation Challenges**
   - **Citation**: Henderson et al. (2012). Structure 20:205-214
   - **Data**: Curated datasets with known structures
   - **Metrics**: FSC, map-model fit

**Quality Metrics (No Gold Standard)**:
1. **FSC (Fourier Shell Correlation) at 0.143**
   - **Citation**: Rosenthal & Henderson (2003). JMB 333:721-745
   - **Gold Standard Metric**: Community-wide standard
   - **Interpretation**:
     - Resolution at FSC=0.143
     - Better resolution = higher quality
   - **Why**: Intrinsic measure of map quality, no reference needed

2. **Angular Distribution Efficiency**
   - **Tool**: CryoSPARC, RELION
   - **Citation**: Naydenova & Russo (2017). Nature Comm 8:629
   - **Metric**: Efficiency factor (0-1)
   - **Interpretation**:
     - Efficiency < 0.7: Preferred orientation problem
     - Efficiency 0.7-0.8: Acceptable
     - Efficiency > 0.8: Good distribution
   - **Why**: Indicates data completeness

3. **B-factor (Sharpening)**
   - **Typical Range**: -50 to -150 Å²
   - **Why**: Indicates overall quality and resolution

4. **Particle Distribution Uniformity**
   - **Metric**: Coefficient of variation in particles per micrograph
   - **Why**: Indicates sample quality and ice thickness uniformity

**Parameter Optimization**:
```python
# Optimize ab initio classes
search_space = {"num_classes": [1, 2, 3, 4, 5]}
for n_classes in search_space["num_classes"]:
    result = run_ab_initio(num_classes=n_classes)
    best_class = max(result["classes"], key=lambda c: c["fsc_resolution"])

    score = evaluate({
        "resolution": best_class["fsc_resolution"],  # Lower is better
        "angular_efficiency": best_class["angular_efficiency"],
        "particles": best_class["num_particles"]
    })
```

#### B. Electron Tomography (ET)

**Benchmark Datasets**:
1. **ETDB (Electron Tomography Database)**
   - **Citation**: Bárcena & Koster (2009). JSB 168:1-8
   - **Data**: Curated tomograms with annotations
   - **Use**: Validate alignment and reconstruction

**Quality Metrics**:
1. **Tilt Series Alignment Quality**
   - **Metric**: Residual alignment error (pixels)
   - **Expected**: < 1 pixel
   - **Tool**: IMOD, AreTomo

2. **CTF Fitting Quality**
   - **Metric**: CTF fit resolution
   - **Expected**: Better than target resolution

---

### SINGLE-CELL RNA-SEQ

**Benchmark Datasets**:
1. **PBMC Datasets (10x Genomics)**
   - **Citation**: Zheng et al. (2017). Nature Comm 8:14049
   - **Data**: 68,000 PBMCs with cell type annotations
   - **Gold Standard**: FACS-sorted populations
   - **URL**: https://support.10xgenomics.com/single-cell-gene-expression/datasets
   - **Use**: Validate clustering and cell type annotation

2. **Tabula Muris**
   - **Citation**: Tabula Muris Consortium (2018). Nature 562:367-372
   - **Data**: 100,000 cells from 20 mouse organs
   - **Gold Standard**: Tissue-based cell type annotations

**Quality Metrics (No Gold Standard)**:
1. **Genes Detected per Cell**
   - **Expected**:
     - 3' scRNA-seq: 1,000-3,000 genes/cell
     - 5' scRNA-seq: 2,000-5,000 genes/cell
   - **Citation**: Seurat best practices (Hao et al., 2021)
   - **Why**: Indicates library quality

2. **Mitochondrial Read Percentage**
   - **Expected**: < 10% (healthy cells)
   - **High percentage**: Dying cells, low quality
   - **Citation**: Standard scRNA-seq QC (Ilicic et al., 2016)

3. **Doublet Score**
   - **Tools**: DoubletFinder, Scrublet
   - **Citation**: McGinnis et al. (2019). Cell Systems 8:329-337
   - **Expected**: < 5% doublets
   - **Why**: Technical artifact detection

4. **Batch Entropy**
   - **Formula**: Shannon entropy of batch distribution in neighborhoods
   - **Citation**: Korsunsky et al. (2019). Nature Methods 16:1289-1296
   - **Interpretation**: Higher entropy = better batch mixing

---

### BIOIMAGING / MEDICAL IMAGING

**Benchmark Datasets**:
1. **Medical Segmentation Decathlon**
   - **Citation**: Simpson et al. (2019). arXiv:1902.09063
   - **Data**: 10 datasets across imaging modalities
   - **Gold Standard**: Expert annotations
   - **Use**: Validate segmentation algorithms

2. **BraTS (Brain Tumor Segmentation)**
   - **Citation**: Menze et al. (2015). IEEE TMI 34:1993-2024
   - **Data**: MRI scans with tumor annotations
   - **Use**: Validate segmentation accuracy

**Quality Metrics (No Gold Standard)**:
1. **Image Registration Quality**
   - **Metric**: Mutual Information, Normalized Cross-Correlation
   - **Citation**: Mattes et al. (2003). Medical Imaging
   - **Why**: Intrinsic measure of alignment quality

2. **SNR (Signal-to-Noise Ratio)**
   - **Calculation**: Mean signal / SD of background
   - **Expected**: > 10 for good quality

3. **Contrast-to-Noise Ratio (CNR)**
   - **Formula**: (Signal_tissue1 - Signal_tissue2) / Noise
   - **Why**: Indicates tissue differentiation quality

---

### PHARMACOLOGY / DRUG DISCOVERY

**Benchmark Datasets**:
1. **PDBbind**
   - **Citation**: Wang et al. (2005). J. Med. Chem. 48:4111-4119
   - **Data**: Protein-ligand complexes with binding affinities
   - **Gold Standard**: Experimental IC50/Kd values
   - **Use**: Validate docking accuracy

2. **DUD-E (Directory of Useful Decoys - Enhanced)**
   - **Citation**: Mysinger et al. (2012). J. Med. Chem. 55:6582-6594
   - **Data**: Active compounds + decoys for 102 targets
   - **Use**: Validate virtual screening

**Quality Metrics (No Gold Standard)**:
1. **Lipinski's Rule of Five Compliance**
   - **Citation**: Lipinski et al. (1997). Adv. Drug Deliv. Rev. 23:3-25
   - **Metrics**: MW < 500, LogP < 5, HBD < 5, HBA < 10
   - **Why**: Drug-likeness assessment

2. **Docking Score Distribution**
   - **Expected**: Clear separation between actives and decoys
   - **Metric**: EF (Enrichment Factor) at 1%, 5%, 10%

3. **Binding Pose Clustering**
   - **Metric**: RMSD between top poses
   - **Expected**: Tight cluster (< 2Å RMSD) indicates reliable prediction

---

## Implementation Strategy

### Phase 1: Extend Existing Plugins (Week 1)

#### 1.1 Add Benchmark Dataset Support
```python
# Add to plugins/genomics/evaluator.py
class GenomicsEvaluatorPlugin(EvaluatorPlugin):
    BENCHMARK_DATASETS = {
        "chipseq_encode_gm12878": {
            "source": "ENCODE",
            "citation": "ENCODE Consortium (2012). Nature 489:57-74",
            "url": "https://www.encodeproject.org/...",
            "organism": "human",
            "cell_line": "GM12878",
            "assays": ["H3K27ac", "H3K4me3", "CTCF"],
            "gold_standard": "manual_validation"
        },
        "rnaseq_seqc": {
            "source": "SEQC/MAQC-III",
            "citation": "SEQC (2014). Nature Biotech 32:903-914",
            ...
        }
    }
```

#### 1.2 Add Quality Metrics (No Gold Standard)
```python
class GenomicsEvaluatorPlugin(EvaluatorPlugin):
    def calculate_intrinsic_quality(self, output_dir: Path) -> Dict[str, float]:
        """Calculate quality metrics that don't need gold standard."""
        metrics = {}

        # ChIP-seq metrics
        if self.is_chipseq(output_dir):
            metrics["nsc"] = self._calculate_nsc(output_dir / "alignment.bam")
            metrics["rsc"] = self._calculate_rsc(output_dir / "alignment.bam")
            metrics["frip"] = self._calculate_frip(
                output_dir / "peaks.bed",
                output_dir / "alignment.bam"
            )
            metrics["library_complexity"] = self._calculate_pbc(
                output_dir / "alignment.bam"
            )

        # RNA-seq metrics
        elif self.is_rnaseq(output_dir):
            metrics["mapping_rate"] = self._extract_mapping_rate(output_dir)
            metrics["gene_body_coverage"] = self._calculate_coverage_uniformity(
                output_dir / "alignment.bam"
            )
            metrics["exonic_rate"] = self._calculate_exonic_rate(output_dir)
            metrics["genes_detected"] = self._count_detected_genes(output_dir)

        return metrics

    def score_without_gold_standard(self, metrics: Dict[str, float]) -> float:
        """Score based on intrinsic quality metrics."""
        score = 0.0

        # ChIP-seq scoring
        if "nsc" in metrics:
            nsc = metrics["nsc"]
            if nsc >= 1.10:
                score += 30  # Good quality
            elif nsc >= 1.05:
                score += 20  # Acceptable
            else:
                score += 10  # Poor

            rsc = metrics["rsc"]
            if rsc >= 1.0:
                score += 30
            elif rsc >= 0.8:
                score += 20
            else:
                score += 10

            frip = metrics["frip"]
            if frip >= 0.05:
                score += 40
            elif frip >= 0.01:
                score += 25
            else:
                score += 10

        return score  # 0-100
```

#### 1.3 Add Parameter Search Spaces
```python
class GenomicsEvaluatorPlugin(EvaluatorPlugin):
    def get_parameter_search_spaces(self, tool_id: str) -> Dict[str, SearchSpace]:
        """Define parameter ranges for optimization."""
        if "macs2" in tool_id.lower():
            return {
                "extsize": SearchSpace(
                    type="discrete",
                    values=[100, 150, 200, 250, 300, 350, 400],
                    default=200,
                    priority=1  # High priority
                ),
                "qvalue": SearchSpace(
                    type="discrete",
                    values=[0.001, 0.01, 0.05, 0.1],
                    default=0.05,
                    priority=2  # Medium priority
                ),
                "broad_cutoff": SearchSpace(
                    type="discrete",
                    values=[0.05, 0.1, 0.15],
                    default=0.1,
                    priority=3,  # Low priority
                    condition="peak_type == 'broad'"  # Only for broad peaks
                )
            }
        elif "star" in tool_id.lower():
            return {
                "outFilterMismatchNmax": SearchSpace(
                    type="discrete",
                    values=[2, 5, 10, 15],
                    default=10
                ),
                "outFilterMultimapNmax": SearchSpace(
                    type="discrete",
                    values=[1, 10, 20, 50],
                    default=20
                )
            }
        return {}
```

### Phase 2: Implement Optimization Engine (Week 2)

```python
class ParameterOptimizer:
    """Optimize parameters using evaluation metrics."""

    def optimize(
        self,
        tool_id: str,
        domain_plugin: EvaluatorPlugin,
        input_data: Path,
        strategy: str = "grid_search"  # or "bayesian", "random"
    ) -> OptimizationResult:
        """
        Find optimal parameters through systematic search.
        """
        search_spaces = domain_plugin.get_parameter_search_spaces(tool_id)

        if strategy == "grid_search":
            return self._grid_search(tool_id, search_spaces, input_data, domain_plugin)
        elif strategy == "bayesian":
            return self._bayesian_optimization(...)
        else:
            return self._random_search(...)

    def _grid_search(self, tool_id, spaces, data, plugin):
        """Exhaustive grid search over parameter space."""
        results = []

        # Generate all combinations
        param_combinations = self._generate_combinations(spaces)

        for params in param_combinations:
            # Run tool with these parameters
            output = self._run_tool(tool_id, data, params)

            # Evaluate quality
            metrics = plugin.calculate_intrinsic_quality(output)
            score = plugin.score_without_gold_standard(metrics)

            results.append({
                "parameters": params,
                "metrics": metrics,
                "score": score
            })

        # Return best
        best = max(results, key=lambda r: r["score"])
        return OptimizationResult(
            optimal_parameters=best["parameters"],
            score=best["score"],
            all_results=results
        )
```

---

## Success Criteria

### For Benchmark Dataset Validation
- [ ] Can reproduce published results within 5%
- [ ] Metrics match community standards
- [ ] Citations provided for all benchmarks

### For User Data Evaluation
- [ ] Quality metrics work without gold standard
- [ ] Thresholds based on published guidelines
- [ ] Clear interpretation for users
- [ ] Warnings for poor quality data

### For Parameter Optimization
- [ ] Finds optimal parameters within search space
- [ ] Optimization completes in reasonable time (<1 hour for grid search)
- [ ] Results are reproducible
- [ ] Confidence intervals provided

---

## References to Collect

Need to compile comprehensive reference library:

1. **ENCODE Guidelines** - ChIP-seq, RNA-seq standards
2. **Cryo-EM Validation Standards** - Henderson et al., Rosenthal & Henderson
3. **Single-cell Best Practices** - Seurat, Scanpy documentation
4. **Genome in a Bottle** - NIST variant calling benchmarks
5. **PDBbind** - Docking benchmarks
6. **Medical Imaging Standards** - DICOM, NIFTI quality metrics

This will be compiled in: `lib/galaxy/ai/test_harness/benchmark_references.bib`

---

## Next Implementation Steps

1. **Create benchmark dataset registry** (benchmark_datasets.json)
2. **Extend existing GenomicsEvaluatorPlugin** with:
   - Intrinsic quality metrics (NSC, RSC, FRiP, mapping rate)
   - Benchmark dataset support
   - Parameter search spaces
3. **Extend existing CryoEMEvaluatorPlugin** with:
   - FSC-based quality metrics
   - Angular distribution metrics
   - Parameter search spaces (num_classes, box_size)
4. **Create ParameterOptimizer** class
5. **Add API endpoints** for optimization
6. **Create documentation** with metric interpretations

Estimated timeline: 2 weeks for complete implementation

---

**Status**: Ready to implement
**Decision**: Extend existing test_harness (Option A) ✅
**Next**: Implement intrinsic quality metrics for genomics and cryo-EM domains
