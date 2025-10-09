# LC-MS Tool Installation Guide

## Overview

This guide explains how to install the top 20 LC-MS/Metabolomics tools for workflow testing, with parallel installation and resource monitoring.

---

## Prerequisites

### 1. Galaxy Must Be Running

```bash
# Start Galaxy in a separate terminal
cd /private/tmp/lcms-platform-galaxy
./run.sh
```

Wait for Galaxy to fully start (you should see "serving on http://127.0.0.1:8080")

### 2. Python Dependencies

```bash
# Install required Python packages
pip install psutil pyyaml
```

### 3. System Requirements

**Minimum:**
- CPU: 4 cores
- RAM: 8 GB
- Disk: 10 GB free space
- Network: Stable internet connection

**Recommended:**
- CPU: 8+ cores
- RAM: 16 GB
- Disk: 20 GB free space

---

## Tools to be Installed

### Top 20 LC-MS/Metabolomics Tools:

1. **bioconductor-msnbase centroid** - Peak centroiding
2. **bioconductor-msnbase smooth chromatogram** - Chromatogram smoothing
3. **bioconductor-msnbase smooth mz** - m/z smoothing
4. **CAMERA.annotate** - Metabolite annotation
5. **CAMERA.combinexsAnnos** - Combine annotations
6. **CAMERA.findAdducts** - Adduct detection
7. **CAMERA.findIsotopes** - Isotope detection
8. **CAMERA.groupCorr** - Correlation grouping
9. **CAMERA.groupFWHM** - FWHM grouping
10. **Metabolites Correlation Analysis** - Correlation analysis
11. **Batch_correction** - Batch effect correction
12. **Biosigner** - Biomarker discovery
13. **BioTransformer** - Metabolite transformation
14. **BEAMSpy** - Mass spectrometry data processing
15. **Analytic correlation filtration** - Correlation filtering
16. **Between-table Correlation** - Multi-table correlation
17. **Check Format** - Data format validation
18. **CFM-ID** - Metabolite identification
19. **ASCA** - ANOVA-SCA analysis
20. **2DNMRAnnotation** - 2D NMR annotation

---

## Installation Methods

### Option 1: Parallel Installation (Recommended - Fastest)

**Estimated Time:** 30-60 minutes for all 20 tools
**Workers:** 3 concurrent installations

```bash
cd /private/tmp/lcms-platform-galaxy
python3 scripts/install_top_20_tools_parallel.py
```

**Features:**
- ✅ Installs 3 tools simultaneously
- ✅ Real-time resource monitoring (CPU, memory, disk)
- ✅ Detailed timing statistics
- ✅ Progress tracking
- ✅ Generates installation report

**Output:**
- Console: Real-time installation progress
- File: `tool_installation_report.txt` with detailed metrics

### Option 2: Sequential Installation (Slower, More Stable)

**Estimated Time:** 2-3 hours for all 20 tools

```bash
cd /private/tmp/lcms-platform-galaxy
python3 scripts/install_top_20_tools.py
```

**Features:**
- ✅ One tool at a time
- ✅ More stable for slower systems
- ✅ Lower resource usage
- ✅ Simpler error handling

---

## Expected Resource Usage

### Parallel Installation (3 workers):

#### CPU Usage:
- **Average**: 60-80%
- **Peak**: 90-100% (during toolbox reload)
- **Idle**: 20-30% (between installations)

#### Memory Usage:
- **Average**: 4-6 GB
- **Peak**: 8-10 GB (during compilation)
- **Base**: 2-3 GB (Galaxy itself)

#### Disk Usage:
- **Per Tool**: 50-500 MB
- **Total**: ~3-5 GB for all 20 tools
- **Temporary**: 1-2 GB (cleaned up after)

#### Network Usage:
- **Per Tool**: 10-100 MB download
- **Total**: ~500 MB - 1 GB
- **Bandwidth**: 5-10 Mbps recommended

### Time Estimates:

| Tool Type | Installation Time | Resource Intensity |
|-----------|------------------|-------------------|
| Simple R Package | 2-5 minutes | Low (CPU 40%, RAM 2GB) |
| R Package with Dependencies | 5-15 minutes | Medium (CPU 70%, RAM 4GB) |
| Java/Conda Package | 10-30 minutes | High (CPU 90%, RAM 6GB) |

**Fastest Tool:** ~2 minutes (simple R package)
**Slowest Tool:** ~30 minutes (complex with many dependencies)
**Average:** ~10 minutes per tool

---

## Installation Process

### What Happens During Installation:

1. **Fetch Metadata** (5-10 seconds)
   - Download tool metadata from ToolShed
   - Verify repository information
   - Check dependencies

2. **Download Package** (10-60 seconds)
   - Download tool package from ToolShed
   - Extract files
   - Validate checksums

3. **Install Dependencies** (1-20 minutes)
   - Install Conda dependencies
   - Install R packages (if applicable)
   - Compile binary dependencies

4. **Configure Tool** (5-15 seconds)
   - Add to tool panel
   - Update tool configuration
   - Register with Galaxy

5. **Reload Toolbox** (10-30 seconds)
   - Reload Galaxy toolbox
   - Verify tool is accessible
   - Update tool index

---

## Monitoring Installation

### Real-Time Monitoring:

The parallel installation script provides:

```
2025-10-07 19:05:23 - [Thread-1  ] - INFO - Starting installation: CAMERA.annotate
2025-10-07 19:05:24 - [Thread-2  ] - INFO - Starting installation: Biosigner
2025-10-07 19:05:25 - [Thread-3  ] - INFO - Starting installation: BioTransformer
2025-10-07 19:08:15 - [Thread-1  ] - INFO - ✅ Installed CAMERA.annotate in 172.3s
2025-10-07 19:10:42 - [Thread-2  ] - INFO - ✅ Installed Biosigner in 318.5s
```

### Resource Metrics:

Every 5 seconds, the script captures:
- CPU usage percentage
- Memory usage (percent and GB)
- Disk free space
- Disk space used

---

## After Installation

### Verify Installation:

```bash
# Check installed tools in database
sqlite3 /private/tmp/lcms-platform-galaxy/database/tool_search_index.db \
  "SELECT COUNT(*) FROM tools WHERE is_installed = 1;"
```

Expected: 21 (20 new + 1 already installed)

### View Installation Report:

```bash
cat /private/tmp/lcms-platform-galaxy/tool_installation_report.txt
```

### Test Tool Access:

```bash
# Start Galaxy and check tool panel
# Go to http://localhost:8080
# Navigate to "LC-MS Metabolomics" section
# Verify all 20 tools are listed
```

---

## Example Installation Report

```
INSTALLATION SUMMARY
================================================================================

📊 Overall Statistics:
  Total tools: 20
  ✅ Successful: 19
  ❌ Failed: 1
  Success rate: 95.0%

⏱️  Installation Timing:
  Total time: 1847.3s (30.8 minutes)
  Average per tool: 97.2s
  Fastest: 122.5s (CAMERA.annotate)
  Slowest: 1654.8s (BioTransformer)

💻 Resource Usage:
  CPU Usage:
    Min: 45.2%
    Max: 94.8%
    Avg: 68.5%
  Memory Usage:
    Min: 32.1%
    Max: 72.4%
    Avg: 52.3%
  Memory (GB):
    Min: 5.12 GB
    Max: 11.58 GB
    Avg: 8.35 GB
  Disk Space:
    Used: 4.23 GB
    Free (start): 125.45 GB
    Free (end): 121.22 GB

🐌 Top 5 Slowest Installations:
  1. BioTransformer: 1654.8s (27.6 min)
  2. Biosigner: 892.3s (14.9 min)
  3. CFM-ID: 687.2s (11.5 min)
  4. BEAMSpy: 456.1s (7.6 min)
  5. CAMERA.findAdducts: 342.8s (5.7 min)

================================================================================
```

---

## Troubleshooting

### Installation Fails

**Problem:** Tool installation fails with dependency error

**Solution:**
```bash
# Install system dependencies (macOS)
brew install gcc gfortran

# Or (Ubuntu/Debian)
sudo apt-get install build-essential gfortran
```

### Out of Memory

**Problem:** Installation fails with "Out of memory" error

**Solution:**
- Reduce parallel workers: Edit script, change `max_workers=3` to `max_workers=1`
- Increase swap space
- Close other applications

### Network Timeout

**Problem:** Download times out

**Solution:**
```bash
# Increase timeout in installation script
# Edit: install_top_20_tools_parallel.py
# Add to install_single_tool method:
# timeout=600  # 10 minutes instead of default
```

### Galaxy Not Running

**Problem:** "Cannot connect to Galaxy" error

**Solution:**
```bash
# Check if Galaxy is running
ps aux | grep galaxy

# If not, start it
cd /private/tmp/lcms-platform-galaxy
./run.sh
```

---

## Cost Analysis

### Local Installation (One-Time):

- **Time Cost**: 30-60 minutes (parallel) or 2-3 hours (sequential)
- **Disk Cost**: 3-5 GB permanent storage
- **Bandwidth Cost**: 500 MB - 1 GB download
- **Compute Cost**: Free (local machine)

### Cloud Installation (AWS/GCP):

#### AWS EC2 (t3.xlarge: 4 vCPU, 16 GB RAM):
- **Instance**: $0.1664/hour
- **Storage**: $0.10/GB-month (EBS)
- **Transfer**: $0.09/GB (first 10TB)

**Total Cost for Installation:**
- Compute: ~$0.15 (1 hour)
- Storage: $0.50/month (5 GB)
- Transfer: ~$0.10 (1 GB)
- **Total**: $0.25 one-time + $0.50/month

---

## Next Steps

After successful installation:

1. **Test Workflows**
   - Create a test workflow using installed tools
   - Verify tools execute correctly
   - Check output files

2. **Update Tool Index**
   ```bash
   sqlite3 database/tool_search_index.db \
     "UPDATE tools SET is_installed = 1 WHERE tool_id IN (...);"
   ```

3. **Configure Auto-Installation**
   - Set up auto-installation for remaining tools
   - Test with GalaxyChat workflow generation

4. **Backup Installation**
   ```bash
   tar -czf lcms_tools_backup.tar.gz \
     shed_tools/ \
     database/tool_search_index.db
   ```

---

## Configuration Files

- **Tool List**: `config/top_20_lcms_tools.yml`
- **Installation Script (Parallel)**: `scripts/install_top_20_tools_parallel.py`
- **Installation Script (Sequential)**: `scripts/install_top_20_tools.py`
- **Tool Database**: `database/tool_search_index.db`

---

## Support

For issues or questions:
1. Check Galaxy logs: `tail -f galaxy.log`
2. Check ToolShed status: https://toolshed.g2.bx.psu.edu
3. Review installation report: `tool_installation_report.txt`

---

**Last Updated**: October 7, 2025
