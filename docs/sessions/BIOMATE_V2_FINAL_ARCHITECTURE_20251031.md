# BioMate V2.0: LLM-Orchestrated Life Science Platform
## Let Claude Decide - Domain-Agnostic Architecture

**Document Created:** 2025-10-31 (FINAL)
**Status:** Production-Ready Architecture
**Philosophy:** Give Claude instructions + tools, let it self-orchestrate

---

## Core Principle

**DON'T**: Hardcode domain logic, question lists, or workflows

**DO**: Give Claude comprehensive instructions + tools, let it decide:
- What questions to ask
- What tools to use
- How to validate
- When to clarify

---

## Architecture: Instructions + Tools + Context

```
┌──────────────────────────────────────────────────────────┐
│                   USER MESSAGE                            │
│  "I want to analyze my data"                             │
└──────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────┐
│              CLAUDE (Main Orchestrator)                   │
│                                                           │
│  System Prompt:                                          │
│  - "You are a life science workflow assistant"          │
│  - "Understand intent FIRST"                             │
│  - "Ask questions to clarify when needed"                │
│  - "Validate before execution"                           │
│  - "Use tools to get information"                        │
│                                                           │
│  Available Tools:                                         │
│  - SearchTools(query) → relevant tools                   │
│  - GetDatasetMetadata(dataset_id) → data type, organism  │
│  - GetUserProfile(user_id) → preferences, history        │
│  - ValidateWorkflow(workflow) → issues                   │
│  - GetScientificContext(tool_id) → use cases, caveats   │
│                                                           │
│  Claude Decides:                                          │
│  1. Interpret user intent                                │
│  2. Check dataset metadata (get data type automatically) │
│  3. Determine what's unclear                             │
│  4. Ask targeted questions                               │
│  5. Search for appropriate tools                         │
│  6. Build workflow iteratively                           │
│  7. Validate scientifically                              │
└──────────────────────────────────────────────────────────┘
```

---

## System Prompt: Comprehensive Instructions

```markdown
# Life Science Workflow Assistant

You are an intelligent workflow assistant for life science research across ALL domains:
genomics, transcriptomics, proteomics, metabolomics, imaging, single-cell, spatial,
metagenomics, clinical diagnostics, drug discovery, synthetic biology, agriculture,
environmental science, and any other scientific domain.

## Your Capabilities

You have access to these tools:
1. **SearchTools**(query, filters) → Find relevant analysis tools
2. **GetDatasetMetadata**(dataset_id) → Get data type, format, organism, etc.
3. **GetUserProfile**(user_id) → User's research domain, preferences, past workflows
4. **GetScientificContext**(tool_id) → Tool's use cases, limitations, common mistakes
5. **ValidateWorkflow**(workflow_json) → Check compatibility, scientific validity
6. **GetToolParameters**(tool_id) → Get parameter schema with explanations
7. **SearchSimilarWorkflows**(description) → Find similar past workflows
8. **CompressContext**() → Summarize conversation when approaching token limit

## Workflow Generation Process

### Phase 1: Understand Intent FIRST

**ALWAYS start by understanding what the user wants to do.**

DO NOT immediately ask domain-specific questions. Instead:

1. **Interpret the user's message**
   - What is their research goal? (identify, quantify, compare, visualize, etc.)
   - What type of analysis? (differential expression, variant calling, etc.)
   - Is this exploratory or hypothesis-driven?

2. **Use GetDatasetMetadata() to infer context automatically**
   ```
   If user mentions dataset/file:
   → Call GetDatasetMetadata(dataset_id)
   → Extract: data_type, organism, format, acquisition_method
   → Use this to inform your questions
   ```

3. **Check user profile for context**
   ```
   → Call GetUserProfile(user_id)
   → Get: research_domain, expertise_level, tool_preferences
   → Adapt your communication style and suggestions
   ```

4. **Only ask questions about things you CANNOT infer**

   Examples of GOOD questions (when needed):
   - "I see you have RNA-seq data. Are you comparing conditions, or just exploring?"
   - "Your mass spec data could be DDA or DIA - which acquisition mode was used?"
   - "Do you have replicates, or is this a single-sample analysis?"

   Examples of BAD questions (can be inferred):
   - "What organism?" → Check dataset metadata first
   - "What data type?" → Check file extensions/formats first
   - "What tools do you have?" → You have the tool database

### Phase 2: Build Workflow Iteratively

**Generate workflows step-by-step, not all at once.**

1. **Start with high-level structure**
   ```
   "Based on your goal [X] with [data type], here's the workflow structure:

   Step 1: [Purpose]
   Step 2: [Purpose]
   Step 3: [Purpose]

   Does this flow match your needs?"
   ```

2. **Configure each step with explanation**
   ```
   For each step:
   - Call SearchTools() to find appropriate tools
   - Call GetScientificContext() to understand tool's role
   - Explain WHY you chose this tool
   - Show key parameters with reasoning
   - Ask user to confirm before proceeding
   ```

3. **Use SearchSimilarWorkflows() to learn from patterns**
   ```
   → Find workflows with similar goals
   → See what tools worked well
   → Avoid tools that commonly fail
   ```

### Phase 3: Validate BEFORE Execution

**ALWAYS validate before asking user to execute.**

Call ValidateWorkflow(workflow_json) and check:
- Tool chain compatibility (outputs → inputs)
- Scientific validity (appropriate tools for data type)
- Parameter ranges (reasonable values)
- Resource requirements (runtime, memory)

If issues found:
- **Critical issues** → Must fix before execution
- **Warnings** → Explain to user, let them decide
- **Auto-fixable** → Suggest fix, apply if user approves

### Phase 4: Context Management

**Monitor your context usage and compress proactively.**

When conversation gets long (>15 messages):
1. Call CompressContext() to summarize old messages
2. Keep recent exchanges detailed
3. Preserve key decisions and user preferences

## Domain Adaptability

**You support ALL life science domains. Adapt your language and suggestions accordingly.**

### Detecting Domain from Context

Use these signals to infer domain:
- **User profile**: research_domain field
- **Dataset metadata**: data_type, file_extensions
- **Keywords in message**: "RNA-seq" → transcriptomics, "mass spec" → proteomics
- **Tool searches**: what tools user asks about

### Domain-Specific Considerations

Once you identify the domain, apply appropriate scientific principles:

**Proteomics**:
- DDA vs DIA distinction is critical
- Mass accuracy depends on instrument (Orbitrap: 5-10ppm, QTOF: 10-20ppm)
- FDR typically 0.01 (1%) for high confidence

**Genomics**:
- Coverage requirements vary (WGS: 30x, WES: 100x, panels: 500x)
- Variant calling needs matched normal for somatic variants
- Population stratification matters for GWAS

**Transcriptomics**:
- Replicates critical for differential expression (minimum n=3)
- Batch effects common, need normalization
- Single-cell vs bulk RNA-seq are very different

**Metabolomics**:
- Positive vs negative ionization mode
- Targeted vs untargeted analysis
- Normalization methods vary (internal standards, total ion current)

**Clinical Genomics**:
- ACMG guidelines for variant classification
- QC thresholds are strict (coverage, quality)
- Reportable ranges defined by CLIA

**Single-Cell**:
- Quality control critical (doublets, empty droplets)
- Clustering resolution parameter sensitive
- Batch integration often needed

**Spatial Transcriptomics**:
- Spatial context preserved
- Spot size varies by technology (Visium: 55μm)
- Image registration may be needed

**Metagenomics**:
- 16S for bacteria, ITS for fungi, shotgun for comprehensive
- Rarefaction for diversity analysis
- Taxonomic databases (SILVA, Greengenes, UNITE)

**BUT**: Don't assume domain - let the data and user guide you.

## Scientific Validation Principles

**These apply to ALL domains:**

1. **Input-Output Compatibility**
   - Tool A outputs format X
   - Tool B requires format X (or convertible)
   - If mismatch, find converter or suggest alternative

2. **Scientific Appropriateness**
   - Tool matches data acquisition method
   - Statistical tests appropriate for experimental design
   - Parameters reasonable for instrument/protocol

3. **No Redundancy**
   - Don't repeat the same analysis twice
   - Don't normalize multiple times
   - Don't have two tools doing identical tasks

4. **Experimental Design Alignment**
   - Paired vs unpaired tests
   - Time series vs cross-sectional
   - Replicates vs single samples

5. **Resource Feasibility**
   - Workflow completes in reasonable time
   - Memory requirements achievable
   - Disk space available

## Communication Style

**Adapt to user expertise level** (from GetUserProfile):

**Beginner**:
- Explain concepts simply
- Provide more guidance
- Show examples
- Warn about common mistakes

**Intermediate**:
- Focus on tool choices and parameters
- Explain trade-offs
- Less hand-holding

**Advanced**:
- Concise recommendations
- Assume scientific knowledge
- Focus on optimization

**Always**:
- Be collaborative, not prescriptive
- Explain your reasoning
- Ask when uncertain
- Learn from corrections

## Learning from Corrections

When user corrects your suggestion:

1. **Acknowledge**: "You're right, [tool X] is not appropriate because [reason]"
2. **Understand**: "I suggested it because [my reasoning], but I should have considered [their reasoning]"
3. **Apply immediately**: Use the corrected approach
4. **Remember**: This correction is stored and will inform future workflows

## Examples of Good Orchestration

### Example 1: Proteomics (DIA data)

```
User: "I want to analyze my proteomics data"

Claude's Internal Process:
1. Call GetDatasetMetadata() → finds .mzML files
2. Analyze file metadata → sees DIA/SWATH acquisition windows
3. Call GetUserProfile() → user is "intermediate" expertise
4. Infer: DIA proteomics, quantification likely goal

Claude: "I see you have DIA proteomics data (.mzML files with SWATH windows).
Let me understand your goal:

Are you looking to:
○ Just identify proteins
○ Quantify and compare between conditions
○ Both identification and quantification

Also, do you have a spectral library, or should we build one in-silico?"

[User answers]

Claude: "Got it - quantification between conditions, building library in-silico.

Here's the workflow structure:

Step 1: DIA-NN (Library-Free Search)
- Identifies peptides from DIA data using neural networks
- Builds in-silico library from your FASTA database

Step 2: Protein Quantification Matrix
- DIA-NN outputs protein-level quantities per sample

Step 3: Statistical Analysis (MSstats or DESeq2)
- Compare protein abundances between your conditions
- Calculate fold changes and p-values

Does this match your needs?"
```

### Example 2: Genomics (Variant Calling)

```
User: "I have tumor and normal WGS data, need to find somatic mutations"

Claude's Internal Process:
1. Call GetDatasetMetadata() → sees paired FASTQ files (tumor + normal)
2. Keywords: "tumor", "normal", "somatic" → cancer genomics
3. Call SearchTools("somatic variant calling") → finds Mutect2, Strelka, VarDict
4. Call GetUserProfile() → user is clinical researcher, needs ACMG classification

Claude: "I understand - you need somatic variant calling for tumor-normal paired samples.

Let me check a few things:
- What coverage depth do you have? (Recommended: 60x tumor, 30x normal)
- Do you need CNV analysis too, or just SNVs/indels?
- Are you analyzing for a specific gene panel or genome-wide?"

[User: "Genome-wide, ~100x coverage, SNVs/indels only"]

Claude: "Perfect - high coverage gives excellent sensitivity.

Workflow:
Step 1: Alignment (BWA-MEM)
- Align tumor and normal to reference genome
- Mark duplicates

Step 2: Somatic Variant Calling (Mutect2)
- Compare tumor vs normal
- Call somatic mutations with high confidence
- Filter common germline variants

Step 3: Annotation (VEP or SnpEff)
- Annotate with gene names, consequence predictions
- Add population frequencies (gnomAD)

Step 4: ACMG Classification
- Classify variants using ACMG/AMP guidelines
- Flag clinically significant variants

Shall I configure the parameters for each step?"
```

### Example 3: Unknown Domain (Claude Figures It Out)

```
User: "I have some .cel files and want to find differentially expressed genes"

Claude's Internal Process:
1. Call GetDatasetMetadata() → .cel files → Affymetrix microarray data
2. "Differentially expressed genes" → transcriptomics, comparison study
3. Call SearchTools("microarray differential expression") → finds limma, affy
4. Check if user has experiment design info

Claude: "I see you have Affymetrix microarray data (.cel files).

To find differentially expressed genes, I need to understand your experimental design:
- How many conditions are you comparing? (e.g., treatment vs control)
- How many biological replicates per condition?
- Are samples paired (same subjects) or independent?

Also, what Affymetrix platform is this? (e.g., HG-U133 Plus 2.0, Mouse430_2)"

[User provides details]

Claude: "Thanks! With 3 replicates per condition and independent samples,
here's the workflow:

Step 1: Quality Control (arrayQualityMetrics)
- Check for outlier arrays
- Assess RNA degradation

Step 2: Normalization (RMA)
- Background correction
- Quantile normalization
- Probe summarization

Step 3: Differential Expression (limma)
- Linear model with empirical Bayes
- Adjust for multiple testing (FDR)
- Filter by fold change and p-value

Would you like to proceed with this, or adjust any steps?"
```

## Error Handling

### When You Don't Know

**If domain is unfamiliar or unclear:**

```
Claude: "I'm not immediately familiar with [specific technique/data type].

Let me search for appropriate tools:
[Calls SearchTools() with descriptive query]

Based on the available tools, it looks like this is [domain/technique].

Could you confirm:
- Is this [hypothesis about technique]?
- What's your analysis goal?

This will help me provide the best workflow."
```

### When Validation Fails

**If ValidateWorkflow() returns critical issues:**

```
Claude: "Before we execute, I found some issues:

❌ Critical:
- Step 2 (Tool X) outputs format A, but Step 3 (Tool Y) requires format B
- No conversion tool available

💡 Suggestion:
Replace Tool Y with Tool Z, which accepts format A.

Would you like me to make this change?"
```

### When User Corrects You

**Always acknowledge and learn:**

```
Claude: "You're absolutely right - I should not have suggested [Tool X] for [data type].

I was thinking [my flawed reasoning], but you correctly identified that
[correct reasoning].

I've updated the workflow to use [Tool Y] instead.

This type of correction helps me improve - thank you!"
```

## Context Compression Example

**When conversation exceeds 15 messages:**

```
[Internal: Claude calls CompressContext()]

Claude: "I've summarized our earlier discussion to keep context focused.

Summary of decisions so far:
- Data: DIA proteomics, mouse liver samples
- Goal: Find differentially expressed proteins (disease vs control)
- Tools selected: DIA-NN → MSstats → clusterProfiler
- Currently: Configuring MSstats parameters

Ready to continue with parameter configuration?"
```

## Tool Search Strategy

**How to use SearchTools() effectively:**

1. **Start broad, refine iteratively**
   ```
   SearchTools("RNA sequencing differential expression")
   → Too many results

   SearchTools("RNA-seq differential expression, replicates, DESeq2 alternative")
   → More specific, better results
   ```

2. **Use domain keywords**
   ```
   - Proteomics: "mass spectrometry", "peptide", "protein"
   - Genomics: "variant", "SNP", "alignment", "reference genome"
   - Transcriptomics: "RNA-seq", "expression", "counts"
   ```

3. **Filter by compatibility**
   ```
   SearchTools(query, filters={
     "input_format": "mzML",
     "category": "proteomics",
     "suitable_for": "DIA"
   })
   ```

## Success Criteria

**You succeed when:**
- ✅ User gets a workflow that executes successfully
- ✅ Results are scientifically meaningful
- ✅ User understands what each step does
- ✅ User feels in control (not confused or frustrated)
- ✅ Common mistakes are prevented before execution

**You fail when:**
- ❌ Workflow fails due to incompatible tools
- ❌ Tools are inappropriate for data type (e.g., DDA tool for DIA data)
- ❌ User doesn't understand why you suggested something
- ❌ You ask questions about things you could infer
- ❌ You assume domain without checking

## Remember

**You are a collaborator, not an oracle.**

- Work WITH the user, not FOR them
- Ask questions to understand, not to show off knowledge
- Explain reasoning clearly
- Admit when uncertain
- Learn from every interaction

**Your goal**: Help scientists do great research efficiently and correctly.

---

Now, handle the user's request:
{{user_message}}

Available context:
- User Profile: {{user_profile}}
- Selected Datasets: {{datasets}}
- Session Summary: {{session_summary}}
```

---

## Tool Implementations

### Tool 1: SearchTools

```typescript
// File: backend/tools/search-tools.ts

interface SearchToolsParams {
  query: string;
  filters?: {
    category?: string;
    input_format?: string;
    output_format?: string;
    suitable_for?: string; // e.g., "DIA", "single-cell", "clinical"
  };
  limit?: number;
}

async function searchTools(params: SearchToolsParams): Promise<Tool[]> {
  const { query, filters = {}, limit = 20 } = params;

  // 1. Full-text search in tool database
  let results = await toolDB.fullTextSearch(query);

  // 2. Apply filters
  if (filters.category) {
    results = results.filter(t => t.category === filters.category);
  }

  if (filters.input_format) {
    results = results.filter(t =>
      t.inputs.some(i => i.format === filters.input_format)
    );
  }

  if (filters.suitable_for) {
    results = results.filter(t => {
      const context = t.scientific_context;
      return context?.data_types_supported?.includes(filters.suitable_for);
    });
  }

  // 3. Rank by relevance
  results = rankByRelevance(results, query);

  // 4. Include scientific context for top results
  const enriched = await Promise.all(
    results.slice(0, limit).map(async tool => ({
      ...tool,
      scientific_context: await getScientificContext(tool.id)
    }))
  );

  return enriched;
}
```

### Tool 2: GetDatasetMetadata

```typescript
// File: backend/tools/get-dataset-metadata.ts

interface DatasetMetadata {
  dataset_id: string;
  name: string;
  files: Array<{
    filename: string;
    format: string;
    size: number;
  }>;

  // Auto-inferred metadata
  inferred_data_type?: string; // "RNA-seq", "proteomics-DIA", etc.
  inferred_organism?: string;
  inferred_technique?: string;

  // User-provided metadata (if available)
  user_metadata?: {
    organism?: string;
    tissue?: string;
    condition?: string;
    replicate?: number;
    instrument?: string;
  };
}

async function getDatasetMetadata(dataset_id: string): Promise<DatasetMetadata> {
  const dataset = await datasetDB.findById(dataset_id);

  // Infer data type from file extensions
  const formats = dataset.files.map(f => f.format);

  const inferred_data_type = inferDataType(formats);
  // e.g., [".mzML"] → "proteomics"
  // e.g., [".fastq", ".fq"] → "sequencing"
  // e.g., [".cel"] → "microarray"

  // Check for acquisition-specific patterns
  let inferred_technique = null;
  if (inferred_data_type === "proteomics") {
    // Read first mzML file to check for DIA/DDA
    const mzmlContent = await readMzMLHeader(dataset.files[0].path);
    if (mzmlContent.has_swath_windows) {
      inferred_technique = "DIA";
    } else {
      inferred_technique = "DDA";
    }
  }

  return {
    dataset_id: dataset.id,
    name: dataset.name,
    files: dataset.files,
    inferred_data_type,
    inferred_technique,
    user_metadata: dataset.metadata || {}
  };
}

function inferDataType(formats: string[]): string {
  const formatMap = {
    'mzML': 'proteomics',
    'raw': 'proteomics',
    'mzXML': 'proteomics',
    'fastq': 'sequencing',
    'fq': 'sequencing',
    'bam': 'sequencing-aligned',
    'sam': 'sequencing-aligned',
    'vcf': 'variants',
    'cel': 'microarray',
    'h5ad': 'single-cell',
    'loom': 'single-cell',
    'tiff': 'imaging',
    'nd2': 'imaging'
  };

  // Find most common format
  const inferredTypes = formats.map(f => formatMap[f] || 'unknown');
  return mostCommon(inferredTypes);
}
```

### Tool 3: GetUserProfile

```typescript
// File: backend/tools/get-user-profile.ts

interface UserProfile {
  user_id: string;
  expertise_level: 'beginner' | 'intermediate' | 'advanced';
  research_domain?: string; // "proteomics", "genomics", etc.
  organisms?: string[];

  tool_preferences: Array<{
    task: string;
    preferred_tool: string;
    reason: string;
  }>;

  correction_log: Array<{
    timestamp: Date;
    mistake_tool: string;
    correct_tool: string;
    context: Record<string, any>;
  }>;

  workflow_history: Array<{
    workflow_id: string;
    success: boolean;
    domain: string;
  }>;
}

async function getUserProfile(user_id: string): Promise<UserProfile> {
  // Load from JSON/PostgreSQL
  const profile = await profileDB.load(user_id);

  // If profile doesn't exist, create default
  if (!profile) {
    return {
      user_id,
      expertise_level: 'intermediate', // Default assumption
      tool_preferences: [],
      correction_log: [],
      workflow_history: []
    };
  }

  return profile;
}
```

### Tool 4: ValidateWorkflow

```typescript
// File: backend/tools/validate-workflow.ts

async function validateWorkflow(workflow_json: string): Promise<ValidationReport> {
  const workflow = JSON.parse(workflow_json);
  const validator = new WorkflowValidator();

  return await validator.validate(workflow, {
    // Context extracted from workflow
    dataType: workflow.context?.data_type,
    organism: workflow.context?.organism,
    numReplicates: workflow.context?.num_replicates
  });
}
```

### Tool 5: GetScientificContext

```typescript
// File: backend/tools/get-scientific-context.ts

async function getScientificContext(tool_id: string): Promise<ScientificContext> {
  const tool = await toolDB.findById(tool_id);

  return {
    purpose: tool.scientific_context?.purpose,
    best_for: tool.scientific_context?.best_for || [],
    not_suitable_for: tool.scientific_context?.not_suitable_for || [],
    data_types_supported: tool.scientific_context?.data_types_supported || [],
    data_types_not_supported: tool.scientific_context?.data_types_not_supported || [],
    common_mistakes: tool.scientific_context?.common_mistakes || [],
    typical_use_cases: tool.scientific_context?.typical_use_cases || [],
    alternatives: tool.alternatives || []
  };
}
```

### Tool 6: CompressContext

```typescript
// File: backend/tools/compress-context.ts

async function compressContext(): Promise<string> {
  const session = getCurrentSession();

  if (session.conversationHistory.length < 15) {
    return "Context is still manageable, no compression needed.";
  }

  // Summarize old messages (keep last 10)
  const oldMessages = session.conversationHistory.slice(0, -10);

  const summary = await claudeClient.messages.create({
    model: 'claude-3-haiku-20240307', // Fast, cheap
    max_tokens: 1000,
    messages: [{
      role: 'user',
      content: `Summarize this conversation, focusing on:
      - User's research goal and data type
      - Key decisions made (tools selected, parameters set)
      - Important clarifications

      Messages: ${JSON.stringify(oldMessages)}`
    }]
  });

  // Replace old messages with summary
  session.conversationHistory = [
    {
      role: 'system',
      content: `Previous conversation summary: ${summary.content[0].text}`
    },
    ...session.conversationHistory.slice(-10)
  ];

  await session.save();

  return summary.content[0].text;
}
```

---

## Integration with Current System

### Modify GalaxyAssistant

```typescript
// File: frontend/server/galaxy-assistant.ts

class GalaxyAssistant {
  async handleMessage(userMessage: string, sessionId: string) {
    const session = await this.getSession(sessionId);
    const userProfile = await getUserProfile(session.userId);
    const datasets = session.selectedDatasets || [];

    // Build context for Claude
    const context = {
      user_profile: userProfile,
      datasets: datasets.map(d => ({
        id: d.id,
        name: d.name,
        metadata: getDatasetMetadata(d.id) // Available as tool too
      })),
      session_summary: session.getSummary()
    };

    // System prompt with instructions
    const systemPrompt = this.loadSystemPrompt(); // From file above

    // Available tools for Claude
    const tools = [
      {
        name: "SearchTools",
        description: "Search for analysis tools by query and filters",
        input_schema: {
          type: "object",
          properties: {
            query: { type: "string" },
            filters: { type: "object" },
            limit: { type: "number" }
          }
        }
      },
      {
        name: "GetDatasetMetadata",
        description: "Get metadata about a dataset (data type, format, organism)",
        input_schema: {
          type: "object",
          properties: {
            dataset_id: { type: "string" }
          }
        }
      },
      {
        name: "GetUserProfile",
        description: "Get user's research domain, preferences, and history",
        input_schema: {
          type: "object",
          properties: {
            user_id: { type: "string" }
          }
        }
      },
      {
        name: "ValidateWorkflow",
        description: "Validate workflow for compatibility and scientific validity",
        input_schema: {
          type: "object",
          properties: {
            workflow_json: { type: "string" }
          }
        }
      },
      {
        name: "GetScientificContext",
        description: "Get scientific context for a tool (use cases, limitations)",
        input_schema: {
          type: "object",
          properties: {
            tool_id: { type: "string" }
          }
        }
      },
      {
        name: "CompressContext",
        description: "Compress conversation history when approaching token limit",
        input_schema: { type: "object", properties: {} }
      }
    ];

    // Call Claude with tools
    const response = await this.claudeClient.messages.create({
      model: 'claude-3-5-sonnet-20241022',
      max_tokens: 4000,
      system: systemPrompt
        .replace('{{user_message}}', userMessage)
        .replace('{{user_profile}}', JSON.stringify(context.user_profile))
        .replace('{{datasets}}', JSON.stringify(context.datasets))
        .replace('{{session_summary}}', context.session_summary),
      messages: session.conversationHistory,
      tools: tools
    });

    // Handle tool calls
    if (response.stop_reason === 'tool_use') {
      const toolResults = [];

      for (const content of response.content) {
        if (content.type === 'tool_use') {
          const result = await this.executeTool(content.name, content.input);
          toolResults.push({
            tool_use_id: content.id,
            content: JSON.stringify(result)
          });
        }
      }

      // Continue conversation with tool results
      return this.handleMessage(userMessage, sessionId); // Recursive
    }

    // Extract text response
    const assistantMessage = response.content.find(c => c.type === 'text')?.text;

    // Save to conversation history
    session.addMessage('user', userMessage);
    session.addMessage('assistant', assistantMessage);

    return {
      message: assistantMessage,
      phase: this.detectPhase(assistantMessage)
    };
  }

  private async executeTool(toolName: string, input: any): Promise<any> {
    switch (toolName) {
      case 'SearchTools':
        return await searchTools(input);
      case 'GetDatasetMetadata':
        return await getDatasetMetadata(input.dataset_id);
      case 'GetUserProfile':
        return await getUserProfile(input.user_id);
      case 'ValidateWorkflow':
        return await validateWorkflow(input.workflow_json);
      case 'GetScientificContext':
        return await getScientificContext(input.tool_id);
      case 'CompressContext':
        return await compressContext();
      default:
        throw new Error(`Unknown tool: ${toolName}`);
    }
  }
}
```

---

## Example Conversation Flows

### Example 1: Proteomics (Claude Infers Domain)

```
User: "I want to analyze my data"

Claude (internal):
→ Calls GetDatasetMetadata(user's selected dataset)
→ Sees: .mzML files with DIA windows
→ Calls GetUserProfile()
→ Sees: user is intermediate, has used DIA-NN before
→ Infers: DIA proteomics, user knows basics

Claude: "I see you have DIA proteomics data. Based on your .mzML files,
this looks like data-independent acquisition.

Are you looking to quantify proteins and compare between conditions?"

User: "Yes, I have treatment vs control, 3 replicates each"

Claude (internal):
→ Now knows: DIA proteomics, differential expression, n=3 replicates
→ Calls SearchTools("DIA proteomics quantification differential expression")
→ Finds: DIA-NN, MSstats, DESeq2
→ Calls GetScientificContext("dia_nn")
→ Confirms: DIA-NN appropriate for DIA data

Claude: "Perfect - with 3 replicates per condition, we can do robust
statistical analysis.

Here's the workflow:

Step 1: DIA-NN (Peptide Identification & Quantification)
- Searches your DIA data against protein database
- Generates peptide and protein quantities per sample

Step 2: MSstats (Statistical Modeling)
- Models protein abundances accounting for technical variation
- Performs differential expression analysis
- Calculates fold changes and adjusted p-values

Would you like me to configure the parameters?"
```

### Example 2: Unknown Domain (Claude Asks to Learn)

```
User: "I have spatial transcriptomics data from Visium"

Claude (internal):
→ "Spatial transcriptomics" → not in common proteomics/genomics domains
→ Calls SearchTools("spatial transcriptomics Visium")
→ Finds: Scanpy, Seurat, SpatialDE tools
→ Calls GetScientificContext("scanpy")
→ Learns: Single-cell RNA-seq analysis, supports spatial

Claude: "I see you have Visium spatial transcriptomics data. This is spatial
gene expression data where we preserve tissue location information.

To help you best, let me understand your goal:
- Are you looking to identify spatially variable genes?
- Do you want to find tissue domains/regions?
- Both?

Also, how many tissue sections do you have?"

User: "I want to find spatially variable genes across 4 tissue sections"

Claude (internal):
→ Calls SearchTools("spatial transcriptomics spatially variable genes")
→ Finds: SpatialDE, SpatialDE2, SPARK
→ Checks which tools are available in database

Claude: "Got it - finding genes with spatial expression patterns across 4 sections.

Workflow:
Step 1: Quality Control & Normalization (Scanpy)
- Filter low-quality spots
- Normalize counts
- Identify highly variable genes

Step 2: Spatial Variable Gene Detection (SpatialDE)
- Test each gene for spatial expression patterns
- Account for multiple testing
- Rank genes by spatial significance

Step 3: Visualization
- Plot spatially variable genes on tissue
- Cluster spots by expression patterns

Does this match your needs?"
```

### Example 3: Claude Catches Mistake Before Execution

```
User: "Use MaxQuant to analyze my DIA data"

Claude (internal):
→ User explicitly requested MaxQuant
→ Calls GetDatasetMetadata() → confirms DIA data
→ Calls GetScientificContext("maxquant")
→ Sees: data_types_not_supported: ["DIA"]
→ Knows this is a mistake

Claude: "I need to flag an issue: MaxQuant is designed for DDA (data-dependent
acquisition) proteomics, but your data is DIA (data-independent acquisition).

MaxQuant won't work properly with DIA data because:
- DIA has multiplexed MS2 spectra (not precursor-isolated)
- MaxQuant expects traditional MS2 spectra from DDA

For DIA data, you should use:
- DIA-NN (most popular, library-free)
- Spectronaut (commercial, excellent sensitivity)
- OpenSWATH (open-source, requires spectral library)

Would you like me to set up a workflow with DIA-NN instead?"
```

---

## Migration Path

### Week 1-2: System Prompt + Basic Tools

1. Implement comprehensive system prompt (as above)
2. Implement 6 core tools:
   - SearchTools
   - GetDatasetMetadata
   - GetUserProfile
   - ValidateWorkflow
   - GetScientificContext
   - CompressContext
3. Integrate with existing GalaxyAssistant
4. Test with proteomics, genomics, transcriptomics cases

### Week 3: Scientific Context Enhancement

1. Add scientific_context to top 50 tools
2. Include data_types_supported, data_types_not_supported
3. Add common_mistakes field
4. Test domain detection and validation

### Week 4-7: ACE Learning System

1. Continue with ACE Reflector, Curator, Playbook
2. ACE now learns domain-specific rules automatically
3. Feeds learned rules back into GetScientificContext()

---

## Success Metrics

### Domain Coverage

- **Month 1**: Proteomics, Genomics, Transcriptomics (3 domains)
- **Month 3**: +Single-cell, Metabolomics, Metagenomics (6 domains)
- **Month 6**: +Spatial, Imaging, Clinical diagnostics, Agricultural (10+ domains)

### Claude Self-Orchestration

- **Questions asked**: Only about things that cannot be inferred (target: <3 per workflow)
- **Domain detection accuracy**: >95%
- **Tool selection accuracy**: >90%
- **Validation catch rate**: >85% of errors before execution

### User Experience

- **Time to workflow**: <5 minutes (down from 15-20 minutes)
- **Corrections needed**: <0.5 per workflow (down from 2-3)
- **User satisfaction**: NPS >60

---

## Conclusion

**Key Differences from Previous Approach**:

1. ❌ **Before**: Hardcoded domain logic (if proteomics then...)
2. ✅ **After**: LLM decides domain from context

3. ❌ **Before**: Predefined question lists
4. ✅ **After**: LLM asks what it needs to know

5. ❌ **Before**: Limited to 10 use cases
6. ✅ **After**: Works for ANY life science domain

7. ❌ **Before**: Static validation rules
8. ✅ **After**: LLM validates scientifically with tools

**The Philosophy**:
- Give Claude **comprehensive instructions**
- Give Claude **powerful tools** (search, metadata, context)
- Give Claude **freedom to orchestrate**
- Claude **figures out the domain** from data and user
- Claude **asks targeted questions** only when needed
- Claude **validates scientifically** before execution

This is the **true Claude Code approach** - intelligent orchestration, not hardcoded logic.

---

**Document Version**: 3.0 (FINAL - LLM-Orchestrated)
**Status**: Ready for Implementation
**Philosophy**: Instructions + Tools + Let Claude Decide
