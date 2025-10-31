# Discussion Questions: Workflow Generation System Design
**Date**: October 30, 2025
**Context**: Improving BioMate workflow generation by applying Claude Code and iFlow CLI patterns

---

## Question 1: Iterative Generation vs One-Shot

**The Core Question**: Should workflows be generated step-by-step with user clarification at each stage, or all at once?

### Current Approach (One-Shot)
```
User: "I want to analyze DIA proteomics data"
        ↓
    [Claude generates entire workflow in one go]
        ↓
    Complete 5-step workflow presented
        ↓
    User discovers issues after generation
```

**Problems**:
- User can't provide input during generation
- Mistakes compound (wrong tool at step 1 → wrong chain for steps 2-5)
- No opportunity to clarify ambiguous requirements
- Hard to debug where generation went wrong

### Proposed Approach (Iterative - like iFlow's /init)
```
User: "I want to analyze DIA proteomics data"
        ↓
Claude: "I'll help you build this workflow step by step.
         First, let me understand your data:
         - What instrument generated your data? (Orbitrap/QTOF/TripleTOF)
         - Do you have a spectral library, or should we build one?
         - What statistical analysis do you want? (DEA/PCA/both)"
        ↓
User provides clarifications
        ↓
Claude: "Here's a DRAFT workflow:
         Step 1: DIA-NN (raw data → peptide identification)
         Step 2: MSstats (quantification)
         Step 3: DESeq2 (differential expression)

         Does this match your needs? Any adjustments?"
        ↓
User: "I also need GO enrichment analysis"
        ↓
Claude: "Added Step 4: ClusterProfiler. Here's the updated workflow..."
```

**Benefits**:
- Catches mistakes early (before full workflow generated)
- User feels in control
- Claude can ask clarifying questions
- Each step can be configured individually
- Similar to how iFlow's `/init` builds project context progressively

**Trade-offs**:
- Takes longer (multiple interactions vs one)
- Requires more UI design (showing draft states, allowing edits)
- Users might want "quick mode" for simple cases

**Discussion Point**: Which parts of workflow generation MUST be interactive vs can be automated?

---

## Question 2: Sub-Agents vs Single Claude

**The Core Question**: Should we use one general Claude instance for everything, or specialized "sub-agents" for different tasks?

### Current Approach (Single Claude)
```
One Claude instance handles:
✓ Understanding user intent
✓ Selecting tools
✓ Configuring parameters
✓ Validating workflow
✓ Explaining results
✓ Fixing errors
```

**Problem**: Jack of all trades, master of none. Claude must context-switch between very different tasks.

### Proposed Approach (Specialized Sub-Agents - like iFlow)
```
┌─────────────────────────────────────────┐
│         Main Orchestrator               │
│  (Understands user intent, coordinates) │
└─────────────────────────────────────────┘
            │
            ├──→ $tool-selector
            │    Specialized in: Proteomics tool catalog
            │    Knowledge: DDA vs DIA, MaxQuant vs DIA-NN
            │    Tools: [Read tool DB, Grep, Bash]
            │
            ├──→ $parameter-expert
            │    Specialized in: Tool parameter configuration
            │    Knowledge: FDR thresholds, charge states
            │    Tools: [Read tool XML, parameter validator]
            │
            ├──→ $workflow-validator
            │    Specialized in: Input/output compatibility
            │    Knowledge: Format conversions, tool chains
            │    Tools: [Read workflow JSON, format checker]
            │
            └──→ $results-explainer
                 Specialized in: Biological interpretation
                 Knowledge: Statistics, pathway analysis
                 Tools: [Read results, visualization]
```

**Example Scenario**:

**User**: "Analyze my DIA data with differential expression"

**Main Orchestrator**:
- Understands: User has DIA data, wants statistical analysis
- Delegates to: `$tool-selector`

**$tool-selector**:
- Thinks: "DIA data → Must use DIA-NN or Spectronaut (NOT MaxQuant)"
- Returns: ["DIA-NN", "MSstats", "DESeq2"]

**Main Orchestrator**:
- Delegates to: `$parameter-expert` for each tool

**$parameter-expert** (for DIA-NN):
- Thinks: "Default FDR 0.01, but user might want stricter"
- Asks user: "What FDR threshold? (default: 0.01, strict: 0.001)"

**Main Orchestrator**:
- Assembles final workflow
- Delegates to: `$workflow-validator`

**$workflow-validator**:
- Checks: DIA-NN output (mzML) → MSstats input (CSV) ✅
- Checks: MSstats output (quantMatrix) → DESeq2 input (matrix) ✅
- Returns: "Workflow is valid"

**Benefits**:
- Each sub-agent is expert in its domain
- Sub-agents have limited tool access (security)
- Can improve individual sub-agents without breaking others
- Like having a team of specialists vs one generalist

**Trade-offs**:
- More complex to implement (need orchestration logic)
- Slower (multiple Claude calls vs one)
- Need to define clear boundaries between sub-agents

**Discussion Point**: Which tasks would benefit MOST from specialized sub-agents?

---

## Question 3: Workflow Modes (Permission Levels)

**The Core Question**: How much autonomy should Claude have? Should it always ask permission, or can it act automatically?

### Inspired by iFlow/Claude Code Modes

**Mode 1: Plan Mode (Safest)**
```
User: "Generate a workflow for my data"
        ↓
Claude: "I propose this workflow:
         Step 1: Run DIA-NN with these parameters
         Step 2: Run MSstats for quantification
         Step 3: Run DESeq2 for statistics

         👤 Approve to proceed? (Y/N)"
        ↓
User must approve EACH step before execution
```

**Use Case**: Production environments, expensive computations, irreversible operations

**Mode 2: Auto-Accept (Balanced)**
```
User: "Generate a workflow for my data"
        ↓
Claude: "Generating workflow... (no approval needed)
         ✓ Selected tools: DIA-NN → MSstats → DESeq2
         ✓ Configured parameters
         ✓ Validated compatibility

         Workflow ready! Review or execute?"
        ↓
Workflow generated automatically, but user reviews before execution
```

**Use Case**: Most common scenarios, experienced users

**Mode 3: YOLO Mode (Risky)**
```
User: "Analyze my DIA data"
        ↓
Claude: "Analyzing... (generating AND executing workflow)
         Running DIA-NN... ⏳
         Running MSstats... ⏳
         Running DESeq2... ✓

         Results ready!"
        ↓
Everything happens automatically, user just sees final results
```

**Use Case**: Trusted workflows, quick iterations, non-critical data

### Visual Comparison

| Aspect | Plan Mode | Auto-Accept | YOLO Mode |
|--------|-----------|-------------|-----------|
| Approval needed? | Yes, each step | Yes, before execution | No |
| Speed | Slowest | Medium | Fastest |
| Safety | Safest | Balanced | Risky |
| User control | Maximum | High | Minimal |
| Best for | Production | Daily use | Quick tests |

**Implementation Detail**:
```typescript
// In frontend settings
interface WorkflowSettings {
  mode: 'plan' | 'auto-accept' | 'yolo';
  autoExecuteThreshold?: number; // Max cost/time for auto-execution
  requireApprovalFor?: string[]; // Specific tools that always need approval
}

// Example
const settings = {
  mode: 'auto-accept',
  requireApprovalFor: ['DESeq2', 'Proteomics-LFQ-Workflow'] // Always ask for statistical tools
};
```

**Discussion Point**:
- What should be the default mode?
- Should we allow per-tool permission settings? (e.g., always ask for DESeq2, never ask for simple format conversion)

---

## Question 4: Context Management - Auto-Compression

**The Core Question**: Long conversations lose context. How do we keep Claude's memory fresh?

### The Problem: Context Window Limits

**Scenario**:
```
Message 1:  User uploads DIA data, describes experiment setup (2000 tokens)
Message 5:  Claude generates workflow (3000 tokens)
Message 10: User asks to modify parameters (1000 tokens)
Message 15: Claude suggests improvements (2000 tokens)
Message 20: User reports error in results (1500 tokens)
Message 25: Claude debugs issue (2500 tokens)
Message 30: User asks: "What was my original experiment setup?"

            Claude: ❌ "I don't have that information in my current context"

Problem: Early messages exceeded context window, got truncated!
```

**Current Situation**:
- Claude Code has 200K token context window
- But long conversations still lose important details
- Old messages get dropped when window fills up
- Critical information (like experiment setup) is lost

### Solution: Auto-Compression (like iFlow's `/compress`)

**How It Works**:
```
┌─────────────────────────────────────────┐
│  BEFORE COMPRESSION (12,000 tokens)     │
├─────────────────────────────────────────┤
│ Msg 1:  User describes DIA experiment   │  2000 tokens
│         "I have 3 biological replicates │
│          from Orbitrap instrument,      │
│          comparing control vs treatment"│
│                                         │
│ Msg 2:  Claude asks clarification       │  500 tokens
│ Msg 3:  User provides sample details    │  1500 tokens
│ Msg 4:  Claude proposes tool selection  │  1000 tokens
│ Msg 5:  User approves                   │  100 tokens
│ Msg 6-25: Back and forth on parameters  │  7000 tokens
└─────────────────────────────────────────┘
        ↓
   [Compression Algorithm]
        ↓
┌─────────────────────────────────────────┐
│  AFTER COMPRESSION (3,000 tokens)       │
├─────────────────────────────────────────┤
│ 📌 EXPERIMENT CONTEXT:                  │
│    - Data: DIA, Orbitrap, 3 replicates │
│    - Comparison: Control vs Treatment   │
│    - Goal: Differential expression      │
│                                         │
│ 📌 TOOL DECISIONS:                      │
│    - Selected: DIA-NN → MSstats → DESeq2│
│    - Rejected: MaxQuant (DDA-only)      │
│    - User preference: FDR 0.01          │
│                                         │
│ 📌 CURRENT STATE:                       │
│    - Workflow generated                 │
│    - Parameters configured              │
│    - Ready for execution                │
│                                         │
│ [Recent 5 messages kept verbatim]       │
└─────────────────────────────────────────┘
```

**When to Compress**:
1. **Automatic**: When context reaches 80% of limit
2. **Manual**: User runs `/compress` command
3. **Smart**: Before tool-intensive operations (like workflow validation)

**What to Keep**:
- ✅ Core experiment details
- ✅ Key decisions and why they were made
- ✅ User preferences and constraints
- ✅ Recent conversation (last 5-10 messages)
- ❌ Redundant back-and-forth
- ❌ Superseded drafts
- ❌ Verbose explanations

**Implementation**:
```typescript
interface CompressionStrategy {
  // Core facts that must never be lost
  criticalContext: {
    dataType: string;        // "DIA proteomics"
    experiment: string;      // "Control vs Treatment"
    constraints: string[];   // ["Budget: $100", "Time: 2 hours"]
  };

  // Keep recent messages verbatim
  recentMessagesCount: number; // Default: 5

  // Summarize older messages
  summarizeOlderThan: number; // Messages older than this get summarized
}
```

**Discussion Point**:
- What information is CRITICAL and must never be compressed?
- Should compression be automatic or user-triggered?
- How do we handle cases where user says "remember X" explicitly?

---

## Question 5: Learning System Priority

**The Core Question**: Claude will make mistakes. Should we build a learning system to prevent repeated mistakes, or focus on better initial prompts?

### Two Approaches

**Approach A: Learning from Corrections (High effort)**
```
Iteration 1:
User: "Analyze DIA data"
Claude: Suggests MaxQuant ❌
User: "No! MaxQuant is for DDA, not DIA!"
         ↓
    [System records correction]
         ↓
    Rule learned: "Never use MaxQuant for DIA data"

Iteration 2:
User: "Analyze DIA data"
Claude: Suggests DIA-NN ✓ (learned from previous mistake)
```

**How it works**:
1. Detect when user corrects Claude
2. Extract the rule (MaxQuant → DIA = bad)
3. Store in correction database
4. Inject learned rules into future prompts

**Implementation**:
```typescript
// Correction database
interface Correction {
  trigger: string;      // "DIA data analysis"
  wrongAction: string;  // "Suggested MaxQuant"
  rightAction: string;  // "Should use DIA-NN"
  rule: string;        // "MaxQuant is DDA-only tool, incompatible with DIA"
  timestamp: Date;
  confidence: number;   // How many times this correction was seen
}

// Before each Claude call
const relevantRules = corrections.filter(c =>
  userQuery.includes(c.trigger)
);

const enhancedPrompt = `
${basePrompt}

LEARNED RULES (from previous corrections):
${relevantRules.map(r => r.rule).join('\n')}
`;
```

**Approach B: Better Domain Information (Lower effort)**
```
Instead of learning, just provide better metadata upfront:

Tool: MaxQuant
❌ Current metadata:
   "name": "MaxQuant",
   "description": "Proteomics quantification"

✅ Enhanced metadata:
   "name": "MaxQuant",
   "description": "Proteomics quantification",
   "data_types_supported": ["DDA"],
   "data_types_not_supported": ["DIA"],
   "common_mistakes": [
     "Users often try to use MaxQuant for DIA data, but it's DDA-only",
     "For DIA data, use DIA-NN or Spectronaut instead"
   ]
```

**Benefits of Enhanced Metadata**:
- Prevents mistakes BEFORE they happen
- No need for learning system infrastructure
- Rules are explicitly documented
- Easier to maintain and update

**Benefits of Learning System**:
- Adapts to user-specific corrections
- Can learn edge cases not in metadata
- Improves over time without manual updates
- Catches unexpected mistake patterns

### Timeline Comparison

**Learning System Implementation**:
- Week 1-2: Build correction detection
- Week 3-4: Build correction database
- Week 5-6: Build rule extraction algorithm
- Week 7-8: Integrate with prompt system
- Week 9+: Monitor and tune

**Enhanced Metadata Implementation**:
- Week 1-2: Audit existing tool database
- Week 3-4: Add missing metadata fields
- Week 5-6: Populate metadata for all tools
- Week 7-8: Validate and test

### Hybrid Approach?
```
Phase 1 (Weeks 1-8): Enhanced Metadata
  → Quick wins, immediate improvement
  → Covers 80% of common mistakes

Phase 2 (Weeks 9-16): Learning System
  → Catches the remaining 20%
  → Adapts to user-specific patterns
  → Continuous improvement
```

**Discussion Point**:
- Should we build the learning system at all, or is enhanced metadata enough?
- If we build it, what should it learn? (tool selection, parameters, workflow structure, all of above?)
- How do we prevent learning wrong lessons from bad user corrections?

---

## Summary: Priority Order?

Based on effort vs impact:

| Feature | Effort | Impact | Priority |
|---------|--------|--------|----------|
| Enhanced Tool Metadata | Low (2-3 weeks) | High (fixes 80% of issues) | 🔥 1 |
| Iterative Generation | Medium (4-6 weeks) | High (better UX) | 🔥 2 |
| Workflow Modes | Low (1-2 weeks) | Medium (UX improvement) | ⚡ 3 |
| Sub-Agents | High (6-8 weeks) | Medium (quality improvement) | 🔧 4 |
| Context Management | Medium (3-4 weeks) | Low (for short sessions) | 🔧 5 |
| Learning System | High (8+ weeks) | Low (diminishing returns) | 🤔 6 |

**Discussion Point**: Do you agree with this priority order? What would you change?

---

## Next Steps

1. **Decide on Priority**: Which of these features should we implement first?
2. **Define MVP**: What's the minimum viable version of each feature?
3. **Create Implementation Plan**: Detailed roadmap with milestones
4. **Assign Resources**: Who works on what?
5. **Set Success Metrics**: How do we measure improvement?

**Questions for Discussion**:
- Which of these patterns resonates most with your vision?
- Are there any patterns we should deprioritize or skip?
- What would you add to this list?
