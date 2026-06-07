---
name: bioconductor-msnbase
description: MSnbase provides infrastructure for manipulation, processing and visualisation of mass spectrometry and proteomics data, ranging from raw to quantitative and annotated data.
when_to_use: Use when: Read mzML/mzXML files into R for proteomics or metabolomics workflows; Process MS2 spectra: deisotoping, centroiding, filtering; TMT/iTRAQ isobaric quantification; Feature quantification from LC-MS data
user-invocable: false
---

# MSnbase — Comprehensive Skill Guide

> **Domain:** Proteomics / Mass spectrometry
> **Bioconductor:** [MSnbase](https://bioconductor.org/packages/release/bioc/html/MSnbase.html)
> **Paper:** Gatto L, Lilley KS (2012). Bioinformatics, 28(2):288-289.

Infrastructure for mass spectrometry data handling in R: reading mzML/mzXML/mzData files, spectral processing, quantification, and proteomics/metabolomics workflows.

## When to Use

- Read mzML/mzXML files into R for proteomics or metabolomics workflows
- Process MS2 spectra: deisotoping, centroiding, filtering
- TMT/iTRAQ isobaric quantification
- Feature quantification from LC-MS data

**Alternatives:** `Spectra (modern successor)`, `openms (Python/C++)`, `msqrob2 (DE protein)`

## Do NOT Use When

- Large-scale DIA proteomics — use PyProphet/OpenSWATH or Spectronaut.
- Metabolomics spectral matching — use Spectra + CompoundDb instead.
- New projects — consider Spectra as the modern successor.

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Input Format** | mzML, mzXML, mzData (open MS formats; convert with ProteoWizard) |
| **Notes** | Use mode='onDisk' for files > 1GB to avoid memory issues |

## Installation

```r
if (!require("BiocManager", quietly=TRUE))
    install.packages("BiocManager")
BiocManager::install("MSnbase")
library(MSnbase)
```

## Workflows

### Read and Process LC-MS Data for Proteomics
*Load mzML files, filter spectra, and perform isobaric quantification*

#### Read mzML files (on-disk mode)

```r
library(MSnbase)
# on-disk mode: memory-efficient; reads spectra lazily
msdata <- readMSData(files=c("sample1.mzML","sample2.mzML"),
                     mode="onDisk",
                     msLevel.=c(1L, 2L))
msdata
```

#### Basic filtering

```r
# Filter to MS2 spectra only
ms2 <- filterMsLevel(msdata, msLevel.=2L)

# Filter by retention time (RT in seconds)
ms2_rt <- filterRt(ms2, rt=c(600, 3600))

# Filter by m/z
ms2_mz <- filterMz(ms2, mz=c(400, 1400))
```

#### Centroiding profile data

```r
# Smooth then pick peaks
ms2_smooth <- smooth(ms2, method="SavitzkyGolay", halfWindowSize=3)
ms2_peaks  <- pickPeaks(ms2_smooth, snr=3, method="MAD")
```

#### iTRAQ/TMT quantification

```r
# Define reporter ions
reporters <- iTRAQ4  # or TMT6, TMT10, TMT11

# Quantify
msnset <- quantify(ms2_peaks,
                   method="trap",
                   reporters=reporters,
                   verbose=TRUE)
exprs(msnset)[1:5, ]  # reporter ion intensities
```

## Key Functions & Parameters

### `readMSData()()`

Read MS data files into an MSnExp object

| Parameter | Description |
|-----------|-------------|
| `files` | character vector of mzML/mzXML file paths |
| `mode` | 'onDisk' (memory-efficient, recommended) \| 'inMemory' |
| `msLevel.` | MS levels to load (e.g. 1L, 2L, c(1L,2L)) |
| `centroided.` | logical: is data already centroided |
| `verbose` | print progress |

### `filterMsLevel()()`

Keep only spectra of specified MS level

| Parameter | Description |
|-----------|-------------|
| `object` | MSnExp |
| `msLevel.` | integer MS level (1L or 2L) |

### `pickPeaks()()`

Peak picking (centroiding) raw profile spectra


### `smooth()()`

Smooth spectra with moving average or Savitzky-Golay

| Parameter | Description |
|-----------|-------------|
| `x` | MSnExp |
| `method` | 'SavitzkyGolay' \| 'MovingAverage' |
| `halfWindowSize` | window half-width (default 2) |

### `combineSpectra()()`

Aggregate spectra within a file/run


### `quantify()()`

Quantify isobaric tags (TMT/iTRAQ)

| Parameter | Description |
|-----------|-------------|
| `object` | MSnExp with MS2 spectra |
| `method` | 'trap' \| 'max' \| 'sum' \| 'reporter' |
| `reporters` | ReporterIons object (e.g. TMT10, iTRAQ4) |

## Scientific Assumptions

*The method assumes the following about your data and experiment:*

- Reporter ion intensities (TMT/iTRAQ) are proportional to protein abundance.
- Missing values in quantification are missing-at-random or missing-not-at-random — treat accordingly.

## Result Interpretation

- Reporter ion intensities: normalize across samples (median or total intensity normalization).
- MSnSet `exprs()`: rows = features (peptides/proteins), columns = samples; values = quantified intensities.
- Missing values: impute with `impute()` function (MSnbase::impute); choose method based on missingness pattern.

## Best Practices

- Always use `mode='onDisk'` for large files — it avoids loading all spectra into memory.
- Filter to required MS levels early: `filterMsLevel(msdata, 2L)`.
- For centroiding: `smooth()` then `pickPeaks()` in that order.
- Use `MSnbase` + `msqrob2` or `DEP` for statistical analysis after quantification.
- MSnbase is the older package; consider `Spectra` for new projects.

## When to Choose This vs Alternatives

| Alternative | Prefer **this tool** when | Prefer **alternative** when |
|-------------|--------------------------|-----------------------------|
| `Spectra` | New projects; you need pluggable backends for large data; metabolomics spectral matching. | You have existing MSnbase-based workflows or need MSnSet quantification. |

## Benchmark Evidence

*Key studies that have validated or benchmarked this tool:*

- **Gatto L, Lilley KS (2012). Bioinformatics 28:288.** [PMID:22113085](https://pubmed.ncbi.nlm.nih.gov/22113085)  
  MSnbase provides unified infrastructure for MS-based proteomics and metabolomics in R.

## Common Errors & Troubleshooting

### `Error reading mzML: corrupted or non-standard file`

**Cause:** Vendor format not fully converted to standard mzML

**Fix:** Re-convert with ProteoWizard/msconvert using standard parameters

## Additional Notes from Official Documentation

*Extracted from the MSnbase Bioconductor vignette(s)*

### 1 Introduction


In this vignette, we will document various timings and benchmarkings
of the MSnbase version 2, that focuses on on-disk data access (as opposed to in-memory ). More details about the new
implementation are documented in the respective classes manual pages
and in
MSnbase , efficient and elegant R-based processing and
visualisation of raw mass spectrometry data . Laurent Gatto,
Sebastian Gibb, Johannes Rainer. bioRxiv 2020.04.29.067868; doi: https://doi.org/10.1101/2020.04.29.067868
As a benchmarking dataset, we are going to use a subset of an TMT
6-plex experiment acquired on an LTQ Orbitrap Velos, that is
distributed with the msdata package
We need to load the MSnbase package and set the
session-wide verbosity flag to FALSE .

```r
library("msdata")
f <- msdata::proteomics(full.names = TRUE,
                        pattern = "TMT_Erwinia_1uLSike_Top10HCD_isol2_45stepped_60min_01.mzML.gz")
basename(f)
```

```r
## [1] "TMT_Erwinia_1uLSike_Top10HCD_isol2_45stepped_60min_01.mzML.gz"
```

### 2.1 Reading data


We first read the data using the original behaviour readMSData function by setting the mode argument to "inMemory" to generates
an in-memory representation of the MS2-level raw data and measure the
time needed for this operation.
Next, we use the readMSData function to generate an on-disk
representation of the same data by setting mode = "onDisk" .
Creating the on-disk experiment is considerable faster and scales to
much bigger, multi-file data, both in terms of object creation time,
but also in terms of object size (see next section). We must of course
make sure that these two datasets are equivalent:

```r
system.time(inmem <- readMSData(f, msLevel = 2,
                                mode = "inMemory",
                                centroided = TRUE))
```

```r
##    user  system elapsed 
##   5.867   0.370   6.246
```

### 2.2 Data size


To compare the size occupied in memory of these two objects, we are
going to use the object_size function from the pryr package, which accounts for the data (the spectra) in the assayData environment (as opposed to the object.size function from the utils package).
The difference is explained by the fact that for ondisk , the spectra
are not created and stored in memory; they are access on disk when
needed, such as for example for plotting:
Figure 1: Plotting in-memory and on-disk spectra

```r
library("pryr")
object_size(inmem)
```

```r
## 2.77 MB
```

### 2.3 Accessing spectra


The drawback of the on-disk representation is when the spectrum data
has to actually be accessed. To compare access time, we are going to
use the microbenchmark and repeat access 10 times to
compare access to all 451 and a single spectrum
in-memory (i.e.Â pre-loaded and constructed) and on-disk
(i.e.Â on-the-fly access).
While it takes order or magnitudes more time to access the data on-the-fly
rather than a pre-generated spectrum, accessing all spectra is only marginally
slower than accessing all spectra, as most of the time is spent preparing the
file for access, which is done only once.
On-disk access performance will depend on the read throughput of the
disk. A comparison of the data import of the above file from an
internal solid state drive and from an USB3 connected hard disk showe

```r
library("microbenchmark")
mb <- microbenchmark(spectra(inmem),
                     inmem[[200]],
                     spectra(ondisk),
                     ondisk[[200]],
                     times = 10)
mb
```

```r
## Unit: microseconds
##             expr        min         lq        mean      median         uq
##   spectra(inmem)     76.694     87.322   1312.3126    211.3235    270.330
##     inmem[[200]]     30.221     32.500     68.5462     80.4705     88.825
##  spectra(ondisk) 453102.954 456584.668 461123.4430 459971.6310 463125.542
##    ondisk[[200]] 261970.948 262110.568 269558.7601 262512.2775 267099.225
##         max neval cld
##   11023.685    10 a  
##      94.427    10 a  
##  473925.730    10  b 
##  318789.700    10   c
```

### 2.4 MS2 quantitation


Below, we perform TMT 6-plex reporter ions quantitation on the first
100 spectra and verify that the results are identical (ignoring
feature names).

```r
system.time(eim <- quantify(inmem[1:100], reporters = TMT6,
                            method = "max"))
```

```r
##    user  system elapsed 
##   0.160   0.175   1.340
```

### 3.1 MS levels


On-disk support multiple MS levels in one object, while in-memory only supports a single level. While support for multiple MS levels
could be added to the in-memory back-end, memory constrains make this
pretty-much useless and will most likely never happen.

### 3.2 Serialisation


In-memory objects can be save() ed and load() ed, while on-disk canât. As a workaround, the latter can be coerced to in-memory instances with as(, "MSnExp") . We would need mzML write support in mzR to be able to implement serialisation for on-disk data.

### 3.4 Validity


The on-disk validObject method doesnât verify the validity on the
spectra (as there arenât any to check). The validateOnDiskMSnExp function, on the other hand, instantiates all spectra and checks their
validity (in addition to calling validObject ).

## Resources

- **Bioconductor page:** https://bioconductor.org/packages/release/bioc/html/MSnbase.html
- **Vignette:** https://bioconductor.org/packages/release/bioc/html/MSnbase.html
- **GitHub:** 
- **Bioconductor support forum:** https://support.bioconductor.org/
- **Paper:** Gatto L, Lilley KS (2012). Bioinformatics, 28(2):288-289.

---
