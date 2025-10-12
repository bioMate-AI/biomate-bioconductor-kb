# LC-MS Tools Galaxy Integration Plan

**Date**: 2025-10-12
**Author**: BioMate Analysis System
**Purpose**: Prioritized implementation plan for integrating nf-core LC-MS/proteomics modules into Galaxy

---

## Executive Summary

This document outlines a comprehensive plan to integrate 13 nf-core LC-MS and proteomics modules into the Galaxy platform, with priority given to tools that enhance existing capabilities and enable complete open-source LC-MS workflows.

### Current State
- **Galaxy**: 65+ existing LC-MS/metabolomics tools (XCMS, DIA-NN, Skyline utilities)
- **nf-core**: 13 LC-MS/proteomics modules identified
- **BioMni**: 2 LC-MS tools (PyMassSpec, cobra)

### Strategic Goals
1. Enhance existing Galaxy DIA-NN with spectral library generation
2. Build complete vendor-format-to-results pipeline (no proprietary software required)
3. Integrate modern tools (Sage, OpenMS suite)
4. Enable both DIA and DDA workflows
5. Maintain compatibility with existing Galaxy LC-MS ecosystem

---

## nf-core LC-MS Module Inventory

### Complete List (13 modules)

**DIA-NN** (1 module)
- `diann/insilicolibrarygeneration` - Generate in silico spectral libraries for DIA

**SageProteomics** (1 module)
- `sageproteomics/sage` - Fast peptide search engine (Rust-based)

**MaxQuant** (1 module)
- `maxquant/lfq` - Label-free quantification

**ThermoRawFileParser** (1 module)
- `thermorawfileparser` - Convert Thermo .RAW files to open formats (mzML/mzXML)

**OpenMS** (9 modules)
- `openms/decoydatabase` - Generate decoy sequences for FDR control
- `openms/filefilter` - Filter and preprocess MS data files
- `openms/idfilter` - Filter identification results
- `openms/idmassaccuracy` - Mass accuracy calibration
- `openms/idmerger` - Merge identification results from multiple runs
- `openms/idripper` - Split identification files
- `openms/idscoreswitcher` - Switch between scoring schemes
- `openms/peakpickerhires` - High-resolution peak detection
- `openms/peptideindexer` - Index peptides in protein databases

---

## Tool Status Assessment

### DIA-NN
- **nf-core**: `diann/insilicolibrarygeneration` (1 module)
- **Galaxy**: DIA-NN base tool EXISTS (1 tool)
- **Gap**: Spectral library generation not available in Galaxy
- **Priority**: **HIGHEST** - Directly enhances existing tool

### Skyline
- **nf-core**: Not available (Windows desktop application)
- **Galaxy**: 2 utility tools:
  - "matchms export skyline transition list"
  - "Skyline2Isocor: converting skyline outputs into IsoCor inputs"
- **Status**: Adequate Galaxy coverage for data exchange

### OpenMS
- **nf-core**: 9 specialized modules
- **Galaxy**: OpenMS tools exist but may lack specific nf-core implementations
- **Priority**: **HIGH** - Comprehensive suite for complete workflows

### Format Conversion
- **nf-core**: ThermoRawFileParser
- **Galaxy**: Multiple converters exist, but ThermoRawFileParser is industry standard
- **Priority**: **HIGH** - Critical infrastructure component

---

## Implementation Plan

### Tier 0: DIA-NN Enhancement (Weeks 1-2)
**Goal**: Enhance existing Galaxy DIA-NN with library generation

**Module**: `diann/insilicolibrarygeneration`

**Rationale**:
- Galaxy already has DIA-NN installed
- Users need spectral library generation for complete DIA workflows
- Quick win - builds on existing infrastructure
- High user demand for DIA capabilities

**Tasks**:
1. Extract nf-core module configuration
2. Create Galaxy tool wrapper XML
3. Test with standard FASTA databases
4. Validate library output format compatibility
5. Document integration with existing DIA-NN tool
6. Create example workflow: FASTA → spectral library → DIA-NN analysis

**Success Metrics**:
- Generate in silico libraries from FASTA files
- Compatible with existing Galaxy DIA-NN tool
- Processing time <5 minutes for standard human proteome

---

### Tier 1: Core LC-MS Pipeline (Weeks 3-5)
**Goal**: Enable vendor-format-to-results workflow without proprietary software

#### Module 1: `thermorawfileparser`

**Rationale**:
- Thermo .RAW is most common vendor format
- Open-source alternative to MSConvert
- Enables full open-source pipeline

**Tasks**:
1. Create Galaxy wrapper for ThermoRawFileParser
2. Support multiple output formats (mzML, mzXML, MGF)
3. Test with various Thermo instrument types (Orbitrap, Q-Exactive)
4. Benchmark conversion speed vs existing tools
5. Add batch processing capability

**Success Metrics**:
- Convert .RAW files to mzML in <10% time overhead vs MSConvert
- Support for DDA and DIA acquisition modes
- Memory usage <4GB for standard files

#### Module 2: `sageproteomics/sage`

**Rationale**:
- Modern, fast peptide search (10-100x faster than traditional tools)
- Written in Rust (performance + memory safety)
- Growing community adoption
- Complements existing search engines

**Tasks**:
1. Create Galaxy wrapper for Sage
2. Configure for both DDA and DIA searches
3. Integrate with Galaxy parameter handling
4. Benchmark against existing search engines (Comet, X!Tandem)
5. Create validation datasets

**Success Metrics**:
- Process standard LC-MS runs in <5 minutes
- Match or exceed sensitivity of existing search engines
- Memory efficient (<8GB for large searches)

**Workflow Integration**:
```
.RAW file → ThermoRawFileParser → mzML → Sage → peptide IDs → downstream analysis
```

---

### Tier 2: OpenMS Ecosystem (Weeks 6-10)
**Goal**: Build comprehensive OpenMS-based analysis pipeline

#### Priority Order:

**Week 6: Peak Processing**
1. `openms/peakpickerhires` - Foundation for all downstream analysis
   - High-resolution peak detection
   - Critical for accurate quantification
   - Test with Orbitrap and TOF data

**Week 7: Database Preparation**
2. `openms/peptideindexer` - Index protein databases for fast searching
3. `openms/decoydatabase` - Generate decoy sequences for FDR control
   - Essential for statistical validation
   - Standard target-decoy approach

**Week 8: Data Preprocessing**
4. `openms/filefilter` - Filter and preprocess MS data
   - Remove noise, select MS levels
   - Optimize file sizes for processing

**Week 9: Results Processing**
5. `openms/idfilter` - Filter identification results
6. `openms/idmerger` - Merge results from multiple runs
   - Multi-run experiments
   - Batch processing support

**Week 10: Advanced Processing**
7. `openms/idscoreswitcher` - Switch scoring schemes
8. `openms/idripper` - Split identification files
9. `openms/idmassaccuracy` - Calibration and mass accuracy assessment

**Rationale**:
- OpenMS is the most comprehensive open-source MS toolkit
- Modular design allows flexible workflows
- Strong community support
- Well-documented formats (mzML, idXML, featureXML)

**Integration Strategy**:
- Build on existing Galaxy OpenMS tools
- Ensure consistency in parameter naming
- Create standard workflows for common use cases
- Provide example pipelines

**Success Metrics**:
- Complete pipeline from raw data to validated peptide IDs
- Processing time competitive with proprietary software
- FDR control at 1% peptide level
- Batch processing of 50+ files

---

### Tier 3: Advanced Quantification (Weeks 11-12)
**Goal**: Enable label-free quantification workflows

#### Module: `maxquant/lfq`

**Rationale**:
- MaxQuant is gold standard for LFQ in proteomics
- Widely cited in literature (>15,000 citations)
- Complex but high-impact functionality
- Fills gap in Galaxy quantification capabilities

**Challenges**:
- Complex tool with many parameters
- Long processing times (hours for large datasets)
- Memory intensive
- Requires careful parameter tuning

**Tasks**:
1. Create comprehensive Galaxy wrapper
2. Implement parameter profiles for common use cases:
   - Standard LFQ
   - Phosphoproteomics
   - SILAC (if supported)
3. Add progress monitoring
4. Optimize for Galaxy cluster execution
5. Create thorough documentation

**Success Metrics**:
- Successfully process standard benchmark datasets
- Reproduce published MaxQuant results
- Quantification CV <20% for technical replicates
- Handle datasets with 1000+ proteins

**Integration**:
- Compatible with upstream tools (ThermoRawFileParser, OpenMS)
- Output compatible with downstream stats (MSstats, Perseus)

---

### Tier 4: BioMni Integration (Week 13+)
**Goal**: Integrate BioMni LC-MS tools into unified ecosystem

#### BioMni Tools:
1. **PyMassSpec** - Python library for mass spectrometry data analysis
2. **cobra** - Constraint-based reconstruction and analysis (metabolomics)

**Rationale**:
- Leverage existing BioMni capabilities
- Create bridges between Galaxy and BioMni
- Enable Python-based custom analysis
- Support metabolomics workflows

**Tasks**:
1. Assess PyMassSpec capabilities vs existing Galaxy tools
2. Identify unique functionalities to expose
3. Create Galaxy wrappers for key PyMassSpec functions
4. Integrate cobra for metabolic modeling
5. Create example workflows combining Galaxy and BioMni tools

**Use Cases**:
- Custom mass spectrum processing
- Metabolic pathway analysis
- Integration with flux balance analysis
- Custom visualization and reporting

---

## Implementation Strategy

### Phase 1: Setup (Week 1)
- Clone nf-core modules repository
- Set up Galaxy tool development environment
- Create testing framework
- Prepare benchmark datasets

### Phase 2: Core Development (Weeks 2-12)
- Implement tools according to tier priorities
- Continuous testing with real datasets
- Documentation as we build
- Community feedback incorporation

### Phase 3: Integration (Week 13+)
- Build complete workflows
- Create tutorials and training materials
- Performance optimization
- BioMni integration

### Phase 4: Deployment & Maintenance (Ongoing)
- Deploy to production Galaxy instance
- Monitor usage and performance
- Bug fixes and updates
- Version updates from nf-core

---

## Technical Requirements

### Development Environment
- Galaxy tool development framework
- nf-core modules (cloned from GitHub)
- Container support (Docker/Singularity)
- Test data repositories

### Testing Framework
- Unit tests for each tool wrapper
- Integration tests for workflows
- Performance benchmarks
- Validation datasets

### Infrastructure
- Galaxy instance with adequate compute resources
- Storage for LC-MS data (large files, 100MB-10GB each)
- Job scheduling system for long-running jobs
- Container registry access

---

## Success Metrics

### Technical Metrics
- **Tool Availability**: All 13 nf-core modules integrated
- **Performance**: Processing time within 20% of native nf-core execution
- **Reliability**: >95% successful job completion rate
- **Coverage**: Support for DIA, DDA, targeted, and metabolomics workflows

### Scientific Metrics
- **Reproducibility**: Match published results on benchmark datasets
- **Sensitivity**: Comparable peptide/protein identification rates
- **Quantification**: CV <20% for technical replicates
- **FDR Control**: Maintain 1% FDR at peptide/protein level

### User Metrics
- **Adoption**: Track tool usage after deployment
- **Documentation**: Complete tutorials for all major workflows
- **Training**: Conduct workshops demonstrating capabilities
- **Feedback**: Collect user feedback for continuous improvement

---

## Risk Assessment

### Technical Risks
1. **Container compatibility issues**
   - Mitigation: Test extensively with Galaxy's container system

2. **Parameter mapping complexity**
   - Mitigation: Start with default parameters, gradually expose advanced options

3. **File format incompatibilities**
   - Mitigation: Use standard formats (mzML, mzXML, FASTA)

4. **Performance bottlenecks**
   - Mitigation: Profile and optimize, leverage Galaxy's job system

### Scientific Risks
1. **Results not matching nf-core outputs**
   - Mitigation: Extensive validation with benchmark datasets

2. **User confusion with parameter choices**
   - Mitigation: Provide parameter profiles and detailed documentation

---

## Timeline Summary

| Tier | Tools | Duration | Priority |
|------|-------|----------|----------|
| 0 | DIA-NN library generation | 2 weeks | Highest |
| 1 | ThermoRawFileParser + Sage | 3 weeks | High |
| 2 | OpenMS suite (9 modules) | 5 weeks | High |
| 3 | MaxQuant LFQ | 2 weeks | Medium |
| 4 | BioMni integration | 2+ weeks | Medium |

**Total Initial Implementation**: 12 weeks (Tiers 0-3)
**Extended Implementation**: 14+ weeks (including BioMni)

---

## Deliverables

### Week 2
- DIA-NN spectral library generation tool
- Example workflow: FASTA → library → DIA analysis

### Week 5
- ThermoRawFileParser tool
- Sage peptide search tool
- Complete DDA workflow: .RAW → mzML → peptide IDs

### Week 10
- Complete OpenMS suite (9 tools)
- Comprehensive processing pipeline
- Validation report on benchmark datasets

### Week 12
- MaxQuant LFQ integration
- Complete quantification workflow
- Performance benchmarking report

### Week 14+
- BioMni tool integration
- Complete documentation
- Training materials
- Deployment to production

---

## Resource Requirements

### Personnel
- 1 FTE Galaxy tool developer (primary)
- 0.5 FTE proteomics domain expert (consultation)
- 0.25 FTE system administrator (infrastructure)

### Compute
- Development Galaxy instance (8-16 cores, 64GB RAM)
- Testing compute nodes (multiple jobs in parallel)
- Storage: 1TB for test datasets and results

### Software
- Galaxy framework (open source)
- nf-core modules (open source)
- Container runtime (Docker/Singularity)
- Version control (Git)

---

## Conclusion

This plan prioritizes nf-core LC-MS tools to create a comprehensive, open-source LC-MS analysis platform in Galaxy. By starting with DIA-NN enhancement and building through format conversion, peptide search, and quantification, we'll enable complete LC-MS workflows without proprietary software dependencies.

The phased approach allows for early wins (DIA-NN enhancement in 2 weeks) while building toward comprehensive capabilities (complete pipeline in 12 weeks). Integration with Galaxy's existing 65+ LC-MS tools and eventual BioMni integration creates a unified ecosystem for metabolomics and proteomics research.

---

## Appendices

### Appendix A: Tool Comparison Matrix

| Tool | nf-core | Galaxy | Priority | Gap |
|------|---------|--------|----------|-----|
| DIA-NN core | ❌ | ✅ | N/A | Base tool exists |
| DIA-NN library gen | ✅ | ❌ | Highest | Missing in Galaxy |
| ThermoRawFileParser | ✅ | ⚠️ | High | May exist, nf-core version preferred |
| Sage search | ✅ | ❌ | High | New modern tool |
| OpenMS suite | ✅ (9) | ⚠️ | High | Some exist, missing specific modules |
| MaxQuant LFQ | ✅ | ⚠️ | Medium | Complex integration needed |
| Skyline | ❌ | ✅ (utilities) | N/A | Adequate coverage |

### Appendix B: Workflow Examples

**Workflow 1: DIA Analysis**
```
1. ThermoRawFileParser (.RAW → mzML)
2. DIA-NN in silico library generation (FASTA → .speclib)
3. Galaxy DIA-NN (mzML + library → peptide IDs)
4. Downstream stats/visualization
```

**Workflow 2: DDA Quantification**
```
1. ThermoRawFileParser (.RAW → mzML)
2. OpenMS PeakPickerHiRes (peak detection)
3. Sage peptide search (mzML → peptide IDs)
4. MaxQuant LFQ (quantification)
5. Statistical analysis
```

**Workflow 3: OpenMS Complete Pipeline**
```
1. ThermoRawFileParser (format conversion)
2. OpenMS FileFilter (preprocessing)
3. OpenMS PeakPickerHiRes (peak detection)
4. OpenMS DecoyDatabase (prepare database)
5. OpenMS PeptideIndexer (index peptides)
6. Search engine (multiple options)
7. OpenMS IDFilter (filter results)
8. OpenMS IDMerger (merge runs)
9. Quantification + stats
```

### Appendix C: References

- nf-core modules: https://github.com/nf-core/modules
- Galaxy Tool Shed: https://toolshed.g2.bx.psu.edu/
- OpenMS documentation: https://openms.de/
- DIA-NN: https://github.com/vdemichev/DiaNN
- SageProteomics: https://github.com/lazear/sage
- MaxQuant: https://www.maxquant.org/

---

**Document Version**: 1.0
**Last Updated**: 2025-10-12
**Next Review**: Upon completion of Tier 0 (Week 2)
