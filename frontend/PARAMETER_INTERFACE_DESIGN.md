# Parameter Interface Design for GalaxyChat

## The Problem with Current Approaches

### DIA-NN (Image 1):
- ✅ Grouped parameters (good organization)
- ❌ Everything visible at once (overwhelming)
- ❌ No guidance on what's important

### Nextflow/Seqera (Images 2-5):
- ✅ Multiple view modes (form vs config)
- ❌ Linear list of 50-100 parameters
- ❌ No hierarchy or importance indicators
- ❌ Mixing critical and optional parameters

### Galaxy:
- ✅ Per-node parameters (contextual)
- ❌ Must click each node separately
- ❌ No global overview

---

## My Proposed Solution: "Smart Progressive Parameters"

### Core Design Principles

1. **80/20 Rule**: 80% of users need only 20% of parameters
2. **Progressive Disclosure**: Show essential first, details on demand
3. **Context-Aware**: Different parameters for different user expertise
4. **AI-Assisted**: Let chat suggest parameter values

---

## Three-Layer Parameter System

### Layer 1: Essential Parameters (Always Visible)
```yaml
Essential (3-5 parameters max):
  - Input Data: [Drop files here]
  - Output Location: ./results
  - Reference Genome: hg38 ▼
  [Run with Smart Defaults]
```

### Layer 2: Common Adjustments (One Click Away)
```yaml
⚙️ Common Settings (click to expand):
  Quality:
    - Min Quality Score: 30
    - Min Read Length: 50
  Performance:
    - Threads: 8
    - Memory: 16GB
```

### Layer 3: Advanced Parameters (Hidden by Default)
```yaml
🔬 Advanced Settings (rarely needed):
  - All 100+ parameters
  - Grouped by module
  - With search/filter
```

---

## Implementation Design

### 1. Unified Parameter Panel with Smart Modes

```javascript
// Progressive Parameter Interface
const ParameterPanel = {
  modes: {
    'quick': {     // New users, quick runs
      shows: ['input', 'output', 'genome'],
      preset: 'balanced_defaults'
    },
    'standard': {  // Regular users
      shows: ['essential', 'quality', 'performance'],
      preset: 'optimized_defaults'
    },
    'expert': {    // Power users
      shows: ['all_parameters'],
      preset: 'custom'
    }
  }
}
```

### 2. Visual Mockup

```
┌─────────────────────────────────────────────────────┐
│ Workflow Parameters                          [Expert Mode ▼] │
├─────────────────────────────────────────────────────┤
│                                                      │
│ 📁 Input & Output ────────────────────────          │
│ Data Files: [3 files selected]            [Browse]  │
│ Output Folder: ./results/run_2024         [Change]  │
│                                                      │
│ 🧬 Reference ─────────────────────────────          │
│ Genome: Human (hg38) ▼                              │
│                                                      │
│ ⚡ Quick Settings ─────────────────────────  [▼]    │
│ Quality Filter: Standard ▼                          │
│ Speed: Balanced ▼                                   │
│                                                      │
│ ┌──────────────────────────────────────────┐        │
│ │ 💡 AI Suggestion:                        │        │
│ │ "Based on your 50 samples, I recommend:  │        │
│ │  • Enable batch correction               │        │
│ │  • Use 16 threads for optimal speed"     │        │
│ │ [Apply Suggestions]                       │        │
│ └──────────────────────────────────────────┘        │
│                                                      │
│ [Show Advanced Parameters]                          │
│                                                      │
│ [Run Analysis] [Save Configuration]                 │
└─────────────────────────────────────────────────────┘
```

### 3. Chat-Integrated Parameter Assistance

```javascript
// Chat can modify parameters naturally
User: "Use stricter quality filtering"
Bot: "I've increased the quality threshold to Q35 and min read length to 75bp"
[Parameters update in real-time]

User: "Optimize for speed"
Bot: "Settings adjusted: 
      - Threads: 32 (max available)
      - Skip optional QC steps
      - Use fast alignment mode"
[Visual feedback in parameter panel]
```

### 4. Smart Parameter Groups (Collapsible)

```yaml
For RNA-seq workflow:

📊 Data Input (Essential)
  └─ Files, Format, Paired/Single

🔍 Quality Control 
  ├─ Quick Mode: [Minimal|Standard|Strict] (dropdown)
  └─ Details ▼ (expandable)
      ├─ FastQC Parameters
      ├─ Trimming Settings  
      └─ Filtering Criteria

🧮 Alignment
  ├─ Quick Mode: [Fast|Balanced|Sensitive]
  └─ Details ▼
      ├─ Aligner: STAR/HISAT2/Salmon
      ├─ Index Settings
      └─ Mismatch Tolerance

📈 Quantification
  ├─ Quick Mode: [Gene|Transcript|Both]
  └─ Details ▼
      ├─ Counting Method
      ├─ Normalization
      └─ Statistical Model

⚙️ System Resources
  ├─ Auto-detect ✓
  └─ Manual ▼
      ├─ CPUs: [slider]
      ├─ Memory: [slider]
      └─ Temp Space: [path]
```

### 5. Parameter Search & Filter

```
🔍 Search parameters: [quality score    ]

Filtered Results:
✓ Min Quality Score (FastQC) .............. 30
✓ Base Quality Filtering (Trimmomatic) .... 20  
✓ Mapping Quality (STAR) .................. 10
```

### 6. Visual Parameter Validation

```javascript
// Real-time validation with visual feedback
const validateParameter = (param, value) => {
  if (param === 'threads' && value > availableCPUs) {
    return {
      status: 'warning',
      message: `Only ${availableCPUs} CPUs available`,
      suggestion: availableCPUs
    };
  }
  
  if (param === 'quality_score' && value > 40) {
    return {
      status: 'info',
      message: 'Very strict filtering may reduce data significantly'
    };
  }
  
  return { status: 'valid' };
};
```

---

## Interaction Patterns

### 1. New User Flow
```
1. Drops files → Auto-detect type
2. Shows 3 essential parameters
3. One button: [Run with Recommendations]
4. Chat explains what's happening
```

### 2. Intermediate User Flow  
```
1. Drops files → Shows standard panel
2. Adjusts 5-10 common parameters
3. Chat suggests optimizations
4. Runs with confidence
```

### 3. Expert User Flow
```
1. Loads saved configuration
2. Switches to Expert Mode
3. Fine-tunes specific parameters
4. Uses search to find obscure settings
5. Saves as template
```

---

## Smart Features

### 1. Parameter Templates
```yaml
Templates:
  - "Publication Ready": Strict QC, full reporting
  - "Quick Exploration": Fast settings, basic QC
  - "Large Dataset": Optimized for 100+ samples
  - "Single Cell": Specific for scRNA-seq
  [Load Template ▼]
```

### 2. Conflict Detection
```javascript
// AI detects parameter conflicts
if (params.aligner === 'STAR' && params.genome === 'bacterial') {
  showWarning('STAR is optimized for splice-aware alignment. 
               Consider BWA for bacterial genomes.');
}
```

### 3. History & Comparison
```
Recent Runs:
┌─────────────────────────────────────┐
│ Run_2024_01: Standard quality, 50 samples │
│ Run_2024_02: Strict quality, 50 samples   │
│ [Compare Parameters]                      │
└─────────────────────────────────────┘
```

---

## Benefits Over Current Approaches

| Feature | DIA-NN | Nextflow | Galaxy | Our Design |
|---------|---------|----------|---------|------------|
| Progressive Disclosure | ❌ | ❌ | ❌ | ✅ |
| AI Suggestions | ❌ | ❌ | ❌ | ✅ |
| Smart Defaults | ⚠️ | ⚠️ | ✅ | ✅ |
| Search/Filter | ❌ | ❌ | ❌ | ✅ |
| Visual Validation | ⚠️ | ❌ | ✅ | ✅ |
| Chat Integration | ❌ | ❌ | ❌ | ✅ |
| Templates | ✅ | ⚠️ | ✅ | ✅ |
| Complexity Modes | ❌ | ❌ | ❌ | ✅ |

---

## Implementation Priority

### Phase 1: Core Parameter System
1. Three-layer progressive disclosure
2. Essential parameters only
3. Smart defaults

### Phase 2: AI Integration
1. Chat-based parameter adjustment
2. Conflict detection
3. Suggestions based on data

### Phase 3: Advanced Features
1. Search and filter
2. Templates and presets
3. Parameter comparison

---

## Key Insight

**Don't show all parameters equally. Use context, user expertise, and AI to show only what's relevant when it's needed.**

The goal: **New users can run in 30 seconds, experts have full control when needed.**