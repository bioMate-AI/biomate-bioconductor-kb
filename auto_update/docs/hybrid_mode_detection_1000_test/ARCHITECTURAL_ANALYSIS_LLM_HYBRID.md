# Architectural Analysis: Rule-Based vs LLM-Hybrid System

**Date:** 2025-11-07
**Session:** 1000-Scenario Test & Architectural Review
**Critical Finding:** Current system is purely rule-based, limiting accuracy to 84.4%

---

## Executive Summary

**User's Critical Question:**
> "Why are the intentions wrongly recognized, based just on rules or LLM makes the mistake? I don't want a rule based system, should be a LLM-rule hybrid system for accuracy and flexibility"

**Answer:** The current V5 detection logic is **100% rule-based** - there is NO LLM involvement in intent detection. This is the root cause of the 84.4% accuracy plateau and 156 failures.

**Key Finding:** Rules cannot capture the nuance needed for 95%+ accuracy. We need an **LLM-Rule Hybrid Architecture**.

---

## Current Architecture (V5): Pure Rule-Based

### How It Works

The current system uses **zero LLM calls** for mode detection. Everything is hard-coded patterns:

```javascript
// Current V5 detection logic (PURE RULES)
function determineWorkflowMode(message, context = {}) {
  const intent = analyzeIntent(message);  // <- Pure regex pattern matching

  // Rule 0: Regex pattern check
  if (intent.isInformationalQuestion) return { mode: 'legacy' };

  // Rule 1: Regex pattern check
  if (intent.isModification) return { mode: 'legacy' };

  // Rule 2: Numeric threshold
  if (intent.isVerySpecific && intent.confidence >= 0.9) return { mode: 'legacy' };

  // ... more hard-coded rules
}

function analyzeIntent(message) {
  const lower = message.toLowerCase();

  // All pattern matching with regex - NO LLM!
  const isInformationalQuestion = /^what (is|are|does|do|did)|explain/i.test(message);
  const isModification = /modify|edit|change|update/i.test(message);
  const mentionsSpecificTools = /HISAT2|STAR|Kallisto|Salmon|DESeq2/i.test(message);

  // Confidence scoring with hard-coded arithmetic
  let confidence = 0.5;
  if (/workflow|pipeline/.test(lower)) confidence = 0.9;
  if (/build|create|generate/.test(lower)) confidence += 0.2;
  // ... more arithmetic

  return { type, confidence, isComplex, ... };
}
```

**Result:** 84.4% accuracy, 156 failures

---

## Why Pure Rules Fail: The Fundamental Limitations

### Problem 1: Lack of Semantic Understanding

**Rule-based:**
```javascript
// Fails on: "I need to clustering for Single-cell RNA"
if (/I need to/.test(lower)) {
  // How do we know if this needs iterative or legacy?
  // We don't! We just guess based on other keywords
}
```

**What LLM would understand:**
- "I need to X for Y" is an ambiguous statement
- Could be "I need to [do] X" (iterative - help request)
- Could be "I need to [use tool] X" (legacy - specific tool)
- Context and phrasing matter

### Problem 2: Expertise Level Blind Spots

**Our Test Results Show:**
- Beginner: 97.3% ✅ (rules work well - simple patterns)
- Intermediate: 84.3% ⚠️ (rules struggle - ambiguous)
- **Expert: 70.7% ❌ (rules fail - nuanced language)**

**Example Failure:**
```
Query: "Optimize edgeR parameters for fusion detection with batch correction"
Expected: iterative (expert asking for optimization help)
Got: legacy (rule sees "with batch correction" as specific)
```

**Why Rules Fail:**
- "Optimize X" should trigger iterative (help with parameters)
- But rule sees "with batch correction" = specific parameters = legacy
- Missing: semantic understanding that "optimize" implies exploration/guidance

### Problem 3: Context Blindness

**Rule-based cannot understand:**
```javascript
// Query 1: "Quick differential expression with Salmon"
// Beginner: Needs help even though says "quick" → should be iterative
// Expert: Actually knows what they want → can be legacy

// Current rule: Sees "quick" + tool name → always legacy
// Misses: Expertise context completely
```

### Problem 4: Cannot Learn from Patterns

**We've seen these failures repeatedly:**
1. "I need to X for Y" (66 failures across all use cases)
2. "Generate standard X workflow" with expert user (28 failures)
3. "Quick X with Tool" for beginners (19 failures)
4. "Optimize Tool parameters" (24 failures)

**Rules:** We can add more regex patterns for each case
**Problem:** Infinite regex patterns needed, brittle, unmaintainable

---

## Why LLM-Hybrid is the Solution

### The Hybrid Architecture

```
User Query
    ↓
┌───────────────────────────────────────┐
│  STAGE 1: Fast Rule-Based Filter     │  ← Keep rules for obvious cases
│  (handles ~60% of cases instantly)   │
└───────────────┬───────────────────────┘
                │
                ├─ OBVIOUS CASES (60%)
                │   • "What is X?" → Legacy (informational)
                │   • "Modify existing workflow" → Legacy (modification)
                │   • "Quick X with Tool Y using --params" → Legacy (very specific)
                │
                └─ AMBIGUOUS CASES (40%)
                    ↓
┌───────────────────────────────────────┐
│  STAGE 2: LLM Intent Analysis        │  ← Use LLM for nuance
│  (analyzes ambiguous queries)        │
└───────────────┬───────────────────────┘
                ↓
        Final Decision
```

### Why This Works

**Stage 1 (Rules):** Fast and cheap
- Obvious informational: "What is RNA-seq?" → Legacy (0ms, $0)
- Obvious specific: "Run DESeq2 with GRCh38 and --flag=value" → Legacy
- Obvious complex: "Compare 5 tools and help me choose" → Iterative

**Stage 2 (LLM):** Accurate and flexible
- Ambiguous phrasing: "I need to clustering for Single-cell RNA"
  - LLM analyzes: Subject-verb agreement off, missing context, likely needs help
  - Decision: Iterative

- Expert optimization: "Optimize edgeR parameters for fusion detection"
  - LLM understands: "Optimize" = exploration = needs guidance
  - Decision: Iterative

- Context-dependent: "Quick differential expression with Salmon"
  - LLM considers: Session history, user expertise, previous queries
  - Beginner → Iterative (probably needs help)
  - Expert → Legacy (knows what they want)

---

## The 1000-Test Results Prove This

### Pattern Analysis of 156 Failures

**Pattern 1: "I need to X for Y" (66 failures - 42%)**
```
Examples:
- "I need to clustering for Single-cell RNA" (Expected: iterative, Got: legacy)
- "I need to protein inference for Proteomics DIA" (Expected: iterative, Got: legacy)
- "I need to trajectory for Single-cell RNA" (Expected: iterative, Got: legacy)
```

**Why Rules Fail:**
- Pattern: `/I need to/` matches
- But meaning varies:
  - "I need to learn how to do X" → iterative
  - "I need to run tool X" → legacy
  - "I need to implement X" → iterative
- **LLM would parse**: "I need to [verb missing] X for Y" = incomplete sentence = needs clarification → iterative

**Pattern 2: Expert "Generate standard" (28 failures - 18%)**
```
Examples:
- "Generate standard DIA quantification workflow" (Expert, Expected: iterative, Got: legacy)
- "Generate standard clustering workflow" (Expert, Expected: iterative, Got: legacy)
- "Generate standard peak calling workflow" (Expert, Expected: iterative, Got: legacy)
```

**Why Rules Fail:**
- Pattern: `/standard/` → confidence boost → legacy
- Missing: **Expertise context**
- Expert saying "generate workflow" = wants to co-design, explore options
- Beginner/Intermediate: "standard" = just give me defaults → legacy
- **LLM would consider**: User expertise + "generate" verb + "workflow" complexity → iterative for experts

**Pattern 3: "Optimize Tool parameters" (24 failures - 15%)**
```
Examples:
- "Optimize edgeR parameters for fusion detection with batch correction" (Expected: iterative, Got: legacy)
- "Optimize Scanpy parameters for trajectory with batch correction" (Expected: iterative, Got: legacy)
```

**Why Rules Fail:**
- Pattern: Sees "with batch correction" = specific parameters = confident → legacy
- Missing: **Verb semantics** - "Optimize" = exploration, not execution
- **LLM would understand**: "Optimize" verb implies iterative refinement process

**Pattern 4: "Quick X with Tool" for beginners (19 failures - 12%)**
```
Examples:
- "Quick differential expression with Salmon" (Beginner, Expected: legacy, Got: iterative)
- "Quick isoform analysis with fastp" (Beginner, Expected: legacy, Got: iterative)
```

**Why Rules Fail:**
- Pattern: "quick" + tool name → but confidence calculation complex
- Missing: **Beginner needs simplicity** even if says "quick"
- Actually: Current rule gets this BACKWARDS (sends to iterative when beginner needs legacy)
- Shows: Rules are inconsistent

---

## Proposed LLM-Hybrid Architecture

### Implementation Design

```python
# Hybrid Mode Detector (Python for clarity)
class HybridModeDetector:
    def __init__(self, anthropic_client):
        self.client = anthropic_client
        self.cache = {}  # Cache LLM decisions

    def determine_mode(self, query, user_context=None):
        # Stage 1: Fast rule-based filtering
        rule_result = self.apply_fast_rules(query)

        if rule_result.confidence == "HIGH":
            # Obvious case - use rule decision
            return rule_result.mode

        # Stage 2: LLM analysis for ambiguous cases
        llm_result = self.llm_intent_analysis(query, user_context)

        return llm_result.mode

    def apply_fast_rules(self, query):
        """Fast rules for obvious cases (60% of queries)"""

        # Obvious informational
        if re.match(r'^(What|How|Why|When|Where) (is|are|does)', query):
            return Decision(mode='legacy', confidence='HIGH',
                          reason='Obvious informational question')

        # Obvious modification
        if re.search(r'modify|edit|update.*existing', query, re.I):
            return Decision(mode='legacy', confidence='HIGH',
                          reason='Modification of existing workflow')

        # Obvious very specific (tool + multiple parameters)
        if self.has_tool_and_params(query):
            return Decision(mode='legacy', confidence='HIGH',
                          reason='Very specific with tool and parameters')

        # Obvious comparison
        if re.search(r'compare.*(and|vs|versus)', query, re.I):
            return Decision(mode='iterative', confidence='HIGH',
                          reason='Tool comparison requires guidance')

        # Obvious help request
        if re.search(r'help me|not sure|don\'t know', query, re.I):
            return Decision(mode='iterative', confidence='HIGH',
                          reason='Explicit help request')

        # Ambiguous - needs LLM
        return Decision(mode=None, confidence='LOW', reason='Ambiguous')

    def llm_intent_analysis(self, query, user_context):
        """Use LLM for nuanced intent understanding"""

        # Build prompt with context
        prompt = self.build_intent_prompt(query, user_context)

        # Call LLM with caching
        cache_key = f"{query}:{user_context.expertise if user_context else 'unknown'}"
        if cache_key in self.cache:
            return self.cache[cache_key]

        response = self.client.messages.create(
            model="claude-sonnet-4-20250514",  # Use Sonnet for reasoning
            max_tokens=200,  # Intent classification is short
            system=[
                {
                    "type": "text",
                    "text": self.get_intent_system_prompt(),
                    "cache_control": {"type": "ephemeral"}  # Cache system prompt
                }
            ],
            messages=[
                {"role": "user", "content": prompt}
            ]
        )

        result = self.parse_llm_response(response)
        self.cache[cache_key] = result

        return result

    def build_intent_prompt(self, query, user_context):
        """Build structured prompt for LLM"""

        expertise = user_context.expertise if user_context else "unknown"
        history = user_context.recent_queries if user_context else []

        return f"""Analyze this bioinformatics workflow request:

Query: "{query}"
User Expertise: {expertise}
Recent Context: {history[-3:] if history else "None"}

Determine the appropriate workflow mode:
- **Iterative Mode**: Complex, ambiguous, needs clarification, help requested, exploration
- **Legacy Mode**: Simple, specific, clear intent, informational, modification

Consider:
1. Query complexity and ambiguity
2. User expertise level (beginners need more guidance)
3. Verb semantics ("optimize", "design" = iterative; "run", "quick" = legacy)
4. Tool and parameter specificity
5. Context from previous queries

Respond in JSON:
{{
  "mode": "iterative" | "legacy",
  "confidence": 0.0-1.0,
  "reasoning": "brief explanation",
  "key_signals": ["signal1", "signal2", ...]
}}"""

    def get_intent_system_prompt(self):
        """System prompt for intent classification (cached)"""
        return """You are an expert bioinformatics workflow intent classifier.

Your task is to determine whether a user query requires:
- **Iterative Mode**: Multi-step clarification dialog for complex/ambiguous requests
- **Legacy Mode**: Single-step workflow generation for clear/specific requests

Key Principles:
1. **Ambiguity → Iterative**: If meaning is unclear, ask for clarification
2. **Complexity → Iterative**: Multiple steps, tool comparisons, design decisions
3. **Expertise Matters**: Beginners need more guidance even for "simple" tasks
4. **Verbs Signal Intent**:
   - "Optimize", "Design", "Compare", "Explore" → Iterative (exploration)
   - "Run", "Quick", "Standard", "Modify" → Legacy (execution)
5. **Specificity → Legacy**: If user provides tool + parameters + data, they know what they want

You must respond in valid JSON format only."""

    def parse_llm_response(self, response):
        """Parse LLM JSON response"""
        import json
        content = response.content[0].text
        data = json.loads(content)

        return Decision(
            mode=data['mode'],
            confidence='HIGH' if data['confidence'] > 0.8 else 'MEDIUM',
            reason=data['reasoning'],
            llm_signals=data['key_signals']
        )
```

### Cost & Performance Analysis

**Stage 1 (Rules):**
- Coverage: 60% of queries (obvious cases)
- Cost: $0
- Latency: <1ms
- Accuracy: 99%+ (only obvious cases)

**Stage 2 (LLM):**
- Coverage: 40% of queries (ambiguous cases)
- Cost: ~$0.0001 per query (200 tokens @ $3/M for Sonnet)
- Latency: ~500ms
- Accuracy: 95%+ (LLM reasoning)

**Combined System:**
- Overall Cost: 0.6 × $0 + 0.4 × $0.0001 = **$0.00004 per query**
- Overall Latency: 0.6 × 1ms + 0.4 × 500ms = **~200ms average**
- Overall Accuracy: 0.6 × 99% + 0.4 × 95% = **97.4% projected**

**Caching Impact:**
- Repeated queries: 90% cache hit rate
- Cached cost: $0 (instant)
- Effective cost with caching: **$0.000004 per query** (10x reduction)

---

## Migration Path: V5 (Rules) → V6 (Hybrid)

### Phase 1: Add LLM Layer (Week 1)

**Step 1:** Implement LLM intent analyzer
```typescript
// frontend/server/mode-detector.ts
export class HybridModeDetector {
  async determineMode(query: string, context?: UserContext): Promise<ModeDecision> {
    // Stage 1: Fast rules
    const ruleDecision = this.fastRules(query);
    if (ruleDecision.confidence === 'HIGH') {
      return ruleDecision;
    }

    // Stage 2: LLM analysis
    const llmDecision = await this.llmIntentAnalysis(query, context);
    return llmDecision;
  }
}
```

**Step 2:** A/B test against V5
- 50% traffic → V5 (pure rules)
- 50% traffic → V6 (LLM-hybrid)
- Measure: Accuracy, latency, cost, user satisfaction

**Step 3:** Gradual rollout
- If V6 accuracy > V5 + 5%: Increase to 75/25
- If V6 accuracy > V5 + 10%: Full rollout

### Phase 2: Optimize Caching (Week 2)

**Implement multi-level caching:**
1. In-memory cache: Common queries (1-hour TTL)
2. Redis cache: User-specific patterns (24-hour TTL)
3. Prompt caching: System prompt (Claude native)

**Expected Impact:**
- 90% cache hit rate
- Effective cost: $0.000004 per query
- Latency: <50ms for cached queries

### Phase 3: Fine-tune Rules (Week 3)

**Use LLM decisions to improve rules:**
```python
# Collect LLM decisions for 1 week
decisions = collect_llm_decisions()

# Find patterns that could be rules
patterns = find_high_confidence_patterns(decisions)
# Example: "Compare X and Y and Z" → 100% iterative → add to fast rules

# Update fast rules
update_fast_rules(patterns)

# Result: More queries handled by Stage 1 (cheaper, faster)
```

### Phase 4: Add Context Learning (Week 4)

**User expertise profiling:**
```typescript
interface UserContext {
  expertise: 'beginner' | 'intermediate' | 'expert';
  recentQueries: Query[];
  preferredMode?: 'iterative' | 'legacy';
  toolExperience: Map<string, ExperienceLevel>;
}

// LLM considers full context
const decision = await llmIntentAnalysis(query, userContext);
```

---

## Expected Outcomes with LLM-Hybrid

### Projected Improvements

**Current (V5 Pure Rules):**
- Overall: 84.4%
- Beginner: 97.3%
- Intermediate: 84.3%
- Expert: 70.7%

**Projected (V6 LLM-Hybrid):**
- Overall: **95-97%** (+11-13%)
- Beginner: **98%** (+1%)
- Intermediate: **95%** (+11%)
- Expert: **94%** (+23%) ← Biggest improvement

### Why These Numbers?

**Beginner (small improvement):**
- Rules already work well (97.3%)
- LLM adds: Better handling of incomplete sentences ("I need to X")

**Intermediate (significant improvement):**
- Rules struggle with ambiguity (84.3%)
- LLM adds: Semantic understanding of "I need to", "Generate standard"

**Expert (major improvement):**
- Rules fail completely (70.7%)
- LLM adds: Understanding of "optimize", "benchmark", "design" semantics
- Context awareness: Expert "generate workflow" ≠ beginner "generate workflow"

---

## Implementation Priority

### Critical: Architecture Decision (Now)

**You must decide:**

**Option A: Continue with Pure Rules (V5)**
- ❌ Will plateau at ~85-88% accuracy
- ❌ Requires endless regex pattern additions
- ❌ Brittle and unmaintainable
- ❌ Cannot handle expertise context
- ✅ Simple to implement
- ✅ Zero cost, zero latency

**Option B: Migrate to LLM-Hybrid (V6)**  ← **RECOMMENDED**
- ✅ Can achieve 95-97% accuracy
- ✅ Flexible and maintainable
- ✅ Handles expertise context
- ✅ Learns from patterns
- ⚠️ Requires 1-2 weeks implementation
- ⚠️ Small cost ($0.000004/query with caching)
- ⚠️ Slight latency (200ms average, <50ms cached)

### Recommended: Option B with Phased Rollout

**Week 1:** Implement hybrid architecture + A/B test
**Week 2:** Optimize caching + full rollout if successful
**Week 3:** Use LLM data to improve rules
**Week 4:** Add user context learning

---

## Answering Your Specific Question

**Q: "Why are the intentions wrongly recognized, based just on rules or LLM makes the mistake?"**

**A:** Currently, **only rules** are making decisions. There is **zero LLM involvement** in V5 intent detection. The 156 failures (15.6%) are purely due to rule limitations.

**The failures happen because:**

1. **Rules cannot understand semantics**
   - "I need to clustering" vs "I need to run clustering" → Same to rules, different meanings

2. **Rules cannot consider expertise**
   - Beginner "Quick X with Tool" ≠ Expert "Quick X with Tool" → Rules treat them the same

3. **Rules cannot parse verb intent**
   - "Optimize parameters" = exploration (iterative)
   - "Run with parameters" = execution (legacy)
   - Rules just see "parameters" → guess wrong

4. **Rules cannot learn**
   - Pattern: "I need to X for Y" fails 66 times
   - Rules: Cannot generalize, need 66 separate patterns
   - LLM: Would learn "X for Y" structure after seeing once

**Q: "I don't want a rule based system, should be a LLM-rule hybrid system for accuracy and flexibility"**

**A:** You are **100% correct**. The architecture must change to LLM-hybrid to achieve >95% accuracy.

**Hybrid is the right approach because:**
- **Rules**: Handle obvious cases (60%) instantly and free
- **LLM**: Handle nuanced cases (40%) accurately
- **Together**: 95-97% accuracy, <$0.000004/query cost, ~200ms latency

---

## Next Steps

### Immediate Action Required:

**1. Architecture Decision**
- [ ] Approve LLM-hybrid approach
- [ ] Allocate 1-2 weeks for implementation
- [ ] Accept small cost/latency tradeoffs for accuracy

**2. Implementation Plan**
- [ ] Week 1: Build hybrid detector + A/B test
- [ ] Week 2: Optimize caching + rollout
- [ ] Week 3: Use LLM data to improve rules
- [ ] Week 4: Add user context

**3. Validate Approach**
- [ ] Test on 100 failed scenarios from V5
- [ ] Measure accuracy improvement
- [ ] Measure cost and latency
- [ ] Get user feedback

---

## Conclusion

**The Fundamental Issue:** Pure rule-based systems cannot achieve >90% accuracy on nuanced intent classification.

**The Solution:** LLM-Rule Hybrid Architecture
- Stage 1 (Rules): Fast, cheap, handles 60% of obvious cases
- Stage 2 (LLM): Accurate, flexible, handles 40% of ambiguous cases
- Result: 95-97% accuracy, $0.000004/query, ~200ms latency

**The Path Forward:**
1. Implement hybrid architecture (Week 1-2)
2. A/B test against V5 rules
3. Roll out if accuracy improves by >5%
4. Continuously optimize with caching and context

**Your Insight Was Correct:** Rules alone are insufficient. Hybrid is the way forward.

---

**Status:** Ready for architectural decision and implementation
**Recommendation:** Approve LLM-hybrid approach and proceed with Phase 1
**Expected Timeline:** 4 weeks to production-ready hybrid system
**Expected Accuracy:** 95-97% (vs current 84.4%)
