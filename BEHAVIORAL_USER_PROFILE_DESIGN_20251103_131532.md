# Behavioral User Profile System
**Date**: November 3, 2025
**Purpose**: Learn from user behavior instead of asking self-reported preferences

---

## ❌ What We DON'T Store (Bad Assumptions)

**Old Approach** (self-reported, unreliable):
```sql
CREATE TABLE user_profiles (
    expertise_level TEXT,      -- ❌ User can't accurately self-assess
    research_domain TEXT,       -- ❌ User might work across domains
    default_data_type TEXT      -- ❌ User's data types vary
);
```

**Problems:**
- Users don't know how to classify their expertise
- Users work across multiple domains
- Static preferences don't capture changing needs
- No feedback loop for improvement

---

## ✅ What We DO Store (Behavioral Observation)

### 1. **Complete Interaction History**

Every action user takes is logged:

```sql
user_interactions (
    interaction_type,     -- 'search', 'tool_select', 'file_upload', 'workflow_run'
    query,                -- What they searched
    detected_context,     -- What we inferred (JSON)
    selected_tool_id,     -- What they chose
    selected_rank,        -- Was it 1st result or 10th?
    user_clicked,         -- Did they click it?
    user_kept,            -- Did they keep it in workflow?
    workflow_success,     -- Did workflow succeed?
    timestamp
)
```

**Use:**
- Build evidence base for patterns
- Track what works vs doesn't work
- Learn tool preferences
- Detect expertise level from behavior

**Example Interaction:**
```json
{
  "interaction_type": "search",
  "query": "differential expression proteomics",
  "detected_context": {
    "inferred_domain": "proteomics",
    "confidence": 0.85,
    "method": "query_keywords"
  },
  "selected_tool_id": "MSstats",
  "selected_rank": 1,
  "user_clicked": true,
  "user_kept": true,
  "workflow_success": true
}
```

---

### 2. **Inferred Patterns** (What We Learn)

From interactions, automatically infer patterns:

```sql
user_patterns (
    pattern_type,     -- 'domain_preference', 'tool_preference', 'complexity_level'
    pattern_data,     -- JSON with details
    confidence,       -- 0.0 to 1.0 based on evidence
    evidence_count,   -- How many interactions support this
    last_updated
)
```

**Pattern Types:**

#### A. **Domain Preference Pattern**
```json
{
  "pattern_type": "domain_preference",
  "pattern_data": {
    "domain": "proteomics",
    "frequency": 0.85,           // 85% of interactions
    "total_interactions": 23,
    "last_30_days": 17,
    "trend": "increasing"
  },
  "confidence": 0.85,
  "evidence_count": 23
}
```

**How to use:**
- If confidence > 0.7 → Suggest proteomics tools by default
- If trend is "decreasing" → User might be shifting domains
- Always allow override with domain detector

#### B. **Tool Preference Pattern**
```json
{
  "pattern_type": "tool_preference",
  "pattern_data": {
    "prefers_tool": "MSstats",
    "over": ["Limma", "DEqMS"],
    "for_task": "differential expression",
    "when_data_type": "DIA",
    "selection_rate": 0.92      // Chose MSstats 92% of time
  },
  "confidence": 0.92,
  "evidence_count": 12
}
```

**How to use:**
- Rank MSstats higher when user searches "differential expression" + has DIA data
- Don't force it - still show alternatives
- If user selects different tool → Learn why (update pattern)

#### C. **Complexity Preference Pattern**
```json
{
  "pattern_type": "complexity_level",
  "pattern_data": {
    "prefers": "simple_tools",
    "evidence": [
      "always_selects_top_result",
      "rarely_tweaks_parameters",
      "avoids_tools_with_many_options"
    ],
    "inferred_expertise": "beginner_to_intermediate"
  },
  "confidence": 0.70,
  "evidence_count": 15
}
```

**How to use:**
- Rank simpler tools higher
- Provide more explanations
- Suggest guided workflows
- **NOT** shown to user (they don't need to know we inferred this)

#### D. **Data Type Pattern**
```json
{
  "pattern_type": "data_type_pattern",
  "pattern_data": {
    "data_type": "DIA-LCMS",
    "file_patterns": ["*.mzML", "*.raw"],
    "cv_params_seen": ["MS:1003114", "MS:1000579"],
    "detection_success_rate": 0.95,
    "total_files": 18,
    "user_corrections": 1         // Only corrected us once
  },
  "confidence": 0.95,
  "evidence_count": 18
}
```

**How to use:**
- When user uploads .mzML with CV param MS:1003114 → High confidence it's DIA
- Auto-suggest "DIA data detected" (with option to correct)
- If user corrects → Learn from correction, adjust pattern

---

### 3. **Data Type Detection History**

Learn to accurately detect data types:

```sql
data_type_detections (
    file_name,
    detected_type,            -- What we guessed
    detection_confidence,     -- How confident
    detection_method,         -- How we detected
    user_confirmed_type,      -- What user said
    was_correct               -- Were we right?
)
```

**Learning Loop:**

```
Upload 1:
  File: experiment.mzML
  Detected: "DIA" (confidence: 0.6, method: 'extension_guess')
  Asked user: "Is this DIA or DDA data?"
  User confirmed: "DIA"
  Result: was_correct = 1

Upload 2:
  File: sample.mzML (similar CV params to Upload 1)
  Detected: "DIA" (confidence: 0.8, method: 'cv_params_match')
  Asked user: "DIA data? (detected from file)" [Yes] [No]
  User: Yes
  Result: was_correct = 1, confidence increases

Upload 10:
  File: new_experiment.mzML
  Detected: "DIA" (confidence: 0.95, method: 'cv_params + user_history')
  Auto-applied with notice: "DIA data detected ✓ Change?"
  User: Accepts
  Result: Detection getting more accurate!
```

---

### 4. **Context Inference Log**

Track how we infer context and learn what works:

```sql
context_inferences (
    query_text,
    uploaded_file_info,
    user_history_summary,

    inferred_domain,
    inferred_data_type,
    inferred_complexity_need,

    domain_confidence,
    data_type_confidence,

    inference_method,
    user_accepted           -- Did they use our suggestions?
)
```

**Example:**

```json
{
  "query_text": "find differentially expressed proteins",
  "uploaded_file_info": {
    "filename": "experiment.mzML",
    "detected_type": "DIA",
    "confidence": 0.95
  },
  "user_history_summary": {
    "primary_domain": "proteomics (85%)",
    "typical_data_type": "DIA-LCMS",
    "complexity_preference": "intermediate"
  },

  "inferred_domain": "proteomics",
  "inferred_data_type": "DIA",
  "inferred_complexity_need": "intermediate",

  "domain_confidence": 0.95,
  "data_type_confidence": 0.95,

  "inference_method": "combined(query_keywords=0.9, file_metadata=0.95, user_history=0.85)",

  "user_accepted": true  // User worked with our suggestions
}
```

**Learning:**
- If `user_accepted = true` → Our inference was good, reinforce this method
- If `user_accepted = false` → Learn what went wrong, adjust weights

---

## 🎯 How to Use This System

### Scenario 1: New User (No History)

**User uploads:** `experiment.mzML`

**System:**
1. Extract metadata from file
2. Check for CV params, scan patterns
3. Make educated guess: "Looks like DIA data"
4. **ASK USER:** "Is this DIA or DDA data?" [DIA] [DDA] [Other]
5. Log interaction → Start building history

**No assumptions, just learning!**

---

### Scenario 2: Returning User (Some History)

**User has uploaded 5 DIA files before**

**System:**
1. Extract metadata
2. Check pattern: `user_patterns.data_type_pattern` shows 100% DIA success rate
3. Make confident prediction: "DIA data detected (based on file + your history)"
4. **SUGGEST, DON'T ASSUME:** Show with [Confirm] [Change] buttons
5. Log whether user confirmed → Increase confidence

**Use history as prior, still allow corrections**

---

### Scenario 3: Experienced User (Rich History)

**User searches:** "differential expression"

**System inference:**
```python
# Check patterns
domain_pattern = get_pattern(user_id, 'domain_preference')
# Result: {"domain": "proteomics", "confidence": 0.95}

tool_pattern = get_pattern(user_id, 'tool_preference')
# Result: {"prefers": "MSstats", "for": "differential expression", "confidence": 0.90}

complexity_pattern = get_pattern(user_id, 'complexity_level')
# Result: {"level": "intermediate", "confidence": 0.75}

# Apply to search
enhanced_search_params = {
    "user_context": {
        "research_domain": "proteomics",     # From pattern (but allow override)
        "expertise_level": "intermediate",   # Inferred from behavior
        "preferred_tools": ["MSstats"]       # Boost in ranking
    }
}

# Run search with context
results = enhanced_search(query, enhanced_search_params)

# Log inference
log_context_inference(
    user_id=user_id,
    inferred_context=enhanced_search_params,
    confidence=0.90
)

# Monitor if user accepts suggestions
# If yes → Reinforce patterns
# If no → Learn what changed
```

---

### Scenario 4: User Switches Domains

**User (usually proteomics) searches:** "RNA-seq quality control"

**System detects domain shift:**
```python
# Check query keywords
query_domain = detect_domain_from_query("RNA-seq quality control")
# Result: "transcriptomics" (confidence: 0.95)

# Check user history
user_primary_domain = get_pattern(user_id, 'domain_preference')
# Result: {"domain": "proteomics", "confidence": 0.95}

# CONFLICT DETECTED!
if query_domain != user_primary_domain:
    # Use QUERY domain, not history domain
    context = {
        "research_domain": "transcriptomics",  # From query
        "note": "Domain shift detected from proteomics"
    }

    # Optionally ask: "Expanding to transcriptomics? [Yes, remember this] [No, one-time]"

    # Log as new interaction
    log_interaction(
        user_id=user_id,
        interaction_type="domain_shift",
        from_domain="proteomics",
        to_domain="transcriptomics"
    )
```

**System adapts in real-time, doesn't lock user into one domain!**

---

## 🧠 Pattern Confidence Calculations

### How confidence changes over time:

```python
def update_pattern_confidence(pattern_id, new_evidence, was_helpful):
    pattern = get_pattern(pattern_id)

    if was_helpful:
        # Bayesian update: increase confidence
        new_confidence = (
            pattern.confidence * pattern.evidence_count + 1.0
        ) / (pattern.evidence_count + 1)

        pattern.evidence_count += 1
        pattern.confidence = min(0.99, new_confidence)  # Cap at 0.99

    else:  # was NOT helpful
        # Decrease confidence
        new_confidence = (
            pattern.confidence * pattern.evidence_count + 0.0
        ) / (pattern.evidence_count + 1)

        pattern.evidence_count += 1
        pattern.confidence = new_confidence

        # If confidence drops below 0.3, remove pattern
        if new_confidence < 0.3:
            delete_pattern(pattern_id)
```

**Example:**

```
Pattern: "User prefers MSstats"
Initial: confidence=0.80, evidence=8

User selects MSstats (9th time):
  New confidence = (0.80 * 8 + 1.0) / 9 = 0.82 ✓ Increased

User selects Limma instead (unexpected):
  New confidence = (0.82 * 9 + 0.0) / 10 = 0.74 ✓ Decreased

  Learn: Maybe user's preference is changing, or task is different
  Create new pattern: "Prefers Limma for certain scenarios"
```

---

## 📊 Complete User Profile Example

After 30 interactions, user profile looks like:

```json
{
  "user_id": "user-001",
  "email": "researcher@university.edu",

  "inferred_patterns": [
    {
      "type": "domain_preference",
      "data": {"domain": "proteomics", "frequency": 0.87},
      "confidence": 0.87,
      "evidence": 26
    },
    {
      "type": "secondary_domain",
      "data": {"domain": "transcriptomics", "frequency": 0.13},
      "confidence": 0.60,
      "evidence": 4
    },
    {
      "type": "tool_preference",
      "data": {
        "tool": "MSstats",
        "for_task": "differential_expression",
        "when_data": "DIA"
      },
      "confidence": 0.92,
      "evidence": 12
    },
    {
      "type": "complexity_level",
      "data": {"inferred_level": "intermediate"},
      "confidence": 0.75,
      "evidence": 30
    },
    {
      "type": "data_type_pattern",
      "data": {
        "type": "DIA-LCMS",
        "detection_accuracy": 0.96
      },
      "confidence": 0.96,
      "evidence": 22
    }
  ],

  "interaction_summary": {
    "total_searches": 30,
    "total_workflows": 8,
    "success_rate": 0.87,
    "average_time_to_result": "4.2 minutes",
    "most_used_tools": ["MSstats", "DIA-NN", "MaxQuant"]
  }
}
```

**How to use:**
- Auto-suggest proteomics tools (87% confidence)
- Rank MSstats higher for differential expression
- Assume intermediate expertise (show moderate detail)
- Auto-detect DIA from files (96% accuracy)
- Still allow all overrides and changes!

---

## 🚀 Integration with Enhanced Search

**Before (static context):**
```python
# User has to specify everything each time
search(
    query="differential expression",
    user_context={
        "research_domain": "proteomics",  # User specifies
        "expertise_level": "intermediate"  # User specifies
    }
)
```

**After (behavioral inference):**
```python
# System automatically infers context from behavior
inferred_context = infer_user_context(user_id)
# Returns: {
#   "research_domain": "proteomics" (confidence: 0.87),
#   "expertise_level": "intermediate" (confidence: 0.75),
#   "preferred_tools": ["MSstats"]
# }

# Use inferred context (but allow override)
search(
    query="differential expression",
    user_context=inferred_context,  # Auto-applied
    allow_override=True  # User can still change
)
```

**User sees:**
- Better results automatically
- Relevant explanations for their level
- Preferred tools ranked higher
- **Can still change anything** - system adapts to changes!

---

## ✅ Benefits of This Approach

1. **No self-classification needed** - We observe, don't ask
2. **Adapts to changing needs** - User switches domains? We detect and adapt
3. **Learns from mistakes** - Wrong suggestion? Learn why and improve
4. **Confidence-based** - High confidence → Auto-apply, Low confidence → Ask
5. **Always allows override** - Never lock user into assumptions
6. **Gets better over time** - More interactions = better patterns
7. **Privacy-friendly** - Just behavior, not personal data

---

## 🎯 Summary

### What We Store:
- ✅ Complete interaction history
- ✅ Inferred patterns with confidence levels
- ✅ Data type detection success/failures
- ✅ Context inference logs

### What We DON'T Store:
- ❌ Self-reported expertise levels
- ❌ Fixed research domains
- ❌ Static preferences

### How It Works:
1. Track everything user does
2. Infer patterns from behavior
3. Use patterns to improve search
4. Monitor if patterns help
5. Update patterns based on feedback
6. **Repeat → Get smarter over time**

This is the foundation for **ACE learning** - the system that continuously improves from user behavior!
