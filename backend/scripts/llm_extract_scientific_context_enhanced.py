#!/usr/bin/env python3
"""
Enhanced scientific context extraction with web search and Claude's knowledge.
Allows LLM to search web via MCP and use its own knowledge when confident.
"""

import os
import sys
import sqlite3
import json
import anthropic
from pathlib import Path

# Enhanced extraction prompt that encourages web search and using Claude's knowledge
EXTRACTION_PROMPT = """You are a bioinformatics expert extracting scientific decision-making information about Galaxy tools.

CONTEXT ABOUT THE TOOL DATABASE:
The database already has these fields (DO NOT duplicate):
- description: Tool overview
- help_text: Full documentation
- parameters: Technical specs
- inputs/outputs: File formats
- citations: References

YOUR TASK:
Extract UNIQUE scientific context that helps researchers make informed decisions.
Focus on: when to use this tool, omics applicability, common pitfalls, parameter wisdom, and result interpretation.

INFORMATION SOURCES YOU CAN USE:
1. **Tool documentation** (provided below): Extract what you can
2. **Web search** (if needed): Search for scientific papers, tutorials, best practices about this tool
3. **Your own knowledge** (if confident): Use your training data about bioinformatics best practices

WHEN TO USE WEB SEARCH:
- Tool documentation is insufficient or unclear
- You need scientific validation or usage examples
- You want to find common pitfalls from community discussions
- You need alternative tool comparisons

WHEN TO USE YOUR OWN KNOWLEDGE:
- You have high confidence about bioinformatics concepts
- You know established best practices for this tool category
- You understand omics-specific requirements (e.g., proteomics needs minimum replicates)
- You know common scientific assumptions

OUTPUT SCHEMA:
{{
  "omics_applicability": {{
    "primary_omics": ["list of omics types"],
    "suitable_designs": ["specific experimental designs"],
    "not_suitable": ["contexts where not appropriate"],
    "data_scale": {{
      "min_samples": <number or null>,
      "min_replicates": <number or null>,
      "notes": "sample size requirements"
    }}
  }},

  "tool_selection": {{
    "best_for": ["specific scenarios where this excels"],
    "not_recommended_for": ["contexts favoring alternatives"],
    "alternatives": [
      {{
        "tool": "alternative name",
        "when_to_prefer_this": "conditions favoring current tool",
        "when_to_prefer_alternative": "conditions favoring alternative"
      }}
    ]
  }},

  "scientific_guidance": {{
    "common_pitfalls": [
      {{
        "mistake": "what users do wrong",
        "consequence": "what happens",
        "recommendation": "what to do instead"
      }}
    ],
    "key_parameters": [
      {{
        "parameter": "parameter name",
        "scientific_meaning": "what it controls scientifically",
        "typical_range": "common values",
        "context_specific": {{"scenario": "value"}}
      }}
    ],
    "result_interpretation": [
      "How to interpret outputs",
      "What to validate",
      "Key caveats"
    ]
  }},

  "scientific_assumptions": [
    "Biological/statistical assumptions",
    "When assumptions may be violated"
  ],

  "information_sources": {{
    "from_documentation": ["what came from tool docs"],
    "from_web_search": ["what came from web search with URLs"],
    "from_llm_knowledge": ["what came from your training data"],
    "confidence_level": "high/medium/low"
  }}
}}

RULES:
1. Be specific, avoid generic terms like "Alignment"
2. Use complete sentences, no truncation
3. If you search the web, cite sources in information_sources
4. Mark confidence level honestly
5. Empty fields are OK if no reliable info available

TOOL INFORMATION:
Name: {tool_name}
Category: {category}
Description: {description}
Help Text: {help_text}

Now extract the scientific context. Use web search or your knowledge as needed.
Return ONLY valid JSON, no markdown code blocks.
"""


def extract_with_tools(tool_data: dict, api_key: str, model: str = "claude-3-5-sonnet-20241022") -> dict:
    """Extract scientific context with web search and Claude's knowledge."""

    client = anthropic.Anthropic(api_key=api_key)

    # Prepare prompt
    prompt = EXTRACTION_PROMPT.format(
        tool_name=tool_data.get('name', 'Unknown'),
        category=tool_data.get('category', 'Unknown'),
        description=tool_data.get('description', 'No description')[:500],
        help_text=tool_data.get('help_text', 'No help text')[:3000]
    )

    # Define web search tool
    tools = [
        {
            "name": "web_search",
            "description": "Search the web for scientific information about bioinformatics tools, papers, tutorials, and best practices. Use this when you need additional context beyond the tool documentation.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "The search query. Be specific and include the tool name and scientific context."
                    }
                },
                "required": ["query"]
            }
        }
    ]

    messages = [{"role": "user", "content": prompt}]
    search_results_context = []

    # Iterative tool use loop
    max_iterations = 5
    for iteration in range(max_iterations):
        try:
            response = client.messages.create(
                model=model,
                max_tokens=4000,
                temperature=0,
                tools=tools,
                messages=messages
            )

            # Check if we got a final response
            if response.stop_reason == "end_turn":
                # Extract the text response
                for block in response.content:
                    if block.type == "text":
                        response_text = block.text.strip()

                        # Remove markdown if present
                        if response_text.startswith('```'):
                            lines = response_text.split('\n')
                            response_text = '\n'.join(lines[1:-1]) if len(lines) > 2 else response_text

                        context = json.loads(response_text)

                        # Add search context to info sources if any searches were done
                        if search_results_context and 'information_sources' in context:
                            if 'from_web_search' not in context['information_sources']:
                                context['information_sources']['from_web_search'] = []
                            context['information_sources']['from_web_search'].extend(search_results_context)

                        return context

            # Handle tool use
            if response.stop_reason == "tool_use":
                # Add assistant's response to messages
                messages.append({"role": "assistant", "content": response.content})

                # Process tool calls
                tool_results = []
                for block in response.content:
                    if block.type == "tool_use":
                        if block.name == "web_search":
                            query = block.input["query"]
                            print(f"    🔍 Searching: {query}")

                            # Perform actual web search
                            try:
                                from anthropic_tools import web_search_function
                                search_results = web_search_function(query)
                                search_result = {
                                    "query": query,
                                    "results": search_results
                                }
                                search_results_context.append(f"Searched: {query} (found {len(search_results)} results)")
                            except ImportError:
                                # Fallback: indicate search was requested but not performed
                                search_result = {
                                    "query": query,
                                    "note": "Web search requested - consider enabling MCP web search for better results",
                                    "suggestion": "Tool documentation may be insufficient. Manual research recommended."
                                }
                                search_results_context.append(f"Searched: {query} (search capability not available)")

                            tool_results.append({
                                "type": "tool_result",
                                "tool_use_id": block.id,
                                "content": json.dumps(search_result)
                            })

                # Add tool results to messages
                messages.append({"role": "user", "content": tool_results})
            else:
                break

        except Exception as e:
            print(f"    ⚠️  Error in iteration {iteration}: {e}")
            break

    # Fallback if we didn't get a valid response
    return {
        "omics_applicability": {},
        "tool_selection": {},
        "scientific_guidance": {},
        "scientific_assumptions": [],
        "information_sources": {
            "from_documentation": [],
            "from_web_search": [],
            "from_llm_knowledge": [],
            "confidence_level": "none",
            "error": str(e) if 'e' in locals() else "No valid response received"
        }
    }


def main():
    import argparse

    parser = argparse.ArgumentParser(description='Extract enhanced scientific context with web search')
    parser.add_argument('--db', required=True, help='Path to Galaxy tools database')
    parser.add_argument('--limit', type=int, default=10, help='Limit number of tools to process')
    parser.add_argument('--offset', type=int, default=0, help='Offset to start from')
    parser.add_argument('--category', help='Process only tools in this category')
    parser.add_argument('--output', help='Output JSON file with results')
    parser.add_argument('--update-db', action='store_true', help='Update database with new context')
    parser.add_argument('--model', default='claude-3-5-sonnet-20241022',
                       help='Claude model (use sonnet for tool use capability)')

    args = parser.parse_args()

    api_key = os.environ.get('ANTHROPIC_API_KEY')
    if not api_key:
        print("❌ Error: ANTHROPIC_API_KEY not set")
        return 1

    # Connect to database
    conn = sqlite3.connect(args.db)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Build query
    query = "SELECT id, name, category, description, help_text FROM tools"
    params = []

    if args.category:
        query += " WHERE category = ?"
        params.append(args.category)

    query += " LIMIT ? OFFSET ?"
    params.extend([args.limit, args.offset])

    cursor.execute(query, params)
    tools = cursor.fetchall()

    print("=" * 80)
    print("ENHANCED Scientific Context Extraction")
    print("=" * 80)
    print(f"Processing: {len(tools)} tools")
    print(f"Model: {args.model}")
    print(f"Features: Web search + LLM knowledge")
    print()

    results = []
    success_count = 0
    web_search_count = 0

    for i, tool in enumerate(tools, 1):
        print(f"\n{i}/{len(tools)}: {tool['name']} ({tool['category']})")

        tool_data = {
            'id': tool['id'],
            'name': tool['name'],
            'category': tool['category'],
            'description': tool['description'],
            'help_text': tool['help_text']
        }

        # Extract context
        context = extract_with_tools(tool_data, api_key, args.model)

        # Check quality
        info_sources = context.get('information_sources', {})
        confidence = info_sources.get('confidence_level', 'unknown')

        used_web = len(info_sources.get('from_web_search', [])) > 0
        used_llm = len(info_sources.get('from_llm_knowledge', [])) > 0

        if used_web:
            web_search_count += 1

        if confidence in ['high', 'medium']:
            success_count += 1
            sources = []
            if used_web:
                sources.append("🔍 web")
            if used_llm:
                sources.append("🧠 LLM")
            if not sources:
                sources.append("📄 docs")

            print(f"  ✅ {confidence.upper()} confidence ({', '.join(sources)})")
        else:
            print(f"  ⚠️  {confidence.upper()} confidence")

        result = {
            'tool_id': tool['id'],
            'tool_name': tool['name'],
            'category': tool['category'],
            'scientific_context': context
        }
        results.append(result)

        # Update database if requested
        if args.update_db:
            cursor.execute(
                "UPDATE tools SET scientific_context = ? WHERE id = ?",
                (json.dumps(context), tool['id'])
            )
            conn.commit()

    # Save results
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(results, f, indent=2)
        print(f"\n📁 Results saved to: {args.output}")

    # Summary
    print("\n" + "=" * 80)
    print("EXTRACTION SUMMARY")
    print("=" * 80)
    print(f"Total processed: {len(tools)}")
    print(f"High/medium confidence: {success_count} ({success_count/len(tools)*100:.1f}%)")
    print(f"Used web search: {web_search_count}")
    if args.update_db:
        print(f"Database updated: ✅")

    conn.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
