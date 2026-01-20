#!/usr/bin/env python3
"""
Extract and format LLM conversation logs from Claude Code JSONL transcripts.

Usage:
    python extract-llm-calls.py <jsonl_file> <output_dir>

Example:
    python extract-llm-calls.py session.jsonl ./audit/
"""

import json
import sys
import os
from datetime import datetime
from pathlib import Path


def extract_text_content(content):
    """Extract text from various content formats."""
    if isinstance(content, str):
        return content
    elif isinstance(content, list):
        texts = []
        for item in content:
            if isinstance(item, dict):
                if item.get('type') == 'text':
                    texts.append(item.get('text', ''))
                elif item.get('type') == 'tool_use':
                    tool_name = item.get('name', 'unknown')
                    tool_input = json.dumps(item.get('input', {}), indent=2)
                    texts.append(f"**[Tool Call: {tool_name}]**\n```json\n{tool_input}\n```")
                elif item.get('type') == 'tool_result':
                    content_text = item.get('content', '')
                    if isinstance(content_text, list):
                        content_text = '\n'.join(
                            str(c.get('text', c)) if isinstance(c, dict) else str(c)
                            for c in content_text
                        )
                    truncated = str(content_text)[:2000]
                    suffix = '...' if len(str(content_text)) > 2000 else ''
                    texts.append(f"**[Tool Result]**\n```\n{truncated}{suffix}\n```")
            elif isinstance(item, str):
                texts.append(item)
        return '\n\n'.join(texts)
    return str(content)


def extract_llm_calls(jsonl_file, output_dir):
    """Extract LLM calls from JSONL transcript and write formatted output."""
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    messages = []
    with open(jsonl_file, 'r') as f:
        for line in f:
            if line.strip():
                try:
                    messages.append(json.loads(line))
                except json.JSONDecodeError:
                    continue

    # Filter to actual conversation messages (user/assistant types)
    conversation_messages = [
        m for m in messages
        if m.get('type') in ('user', 'assistant', 'tool_result')
    ]

    # Count statistics
    user_count = sum(1 for m in conversation_messages if m.get('type') == 'user')
    assistant_count = sum(1 for m in conversation_messages if m.get('type') == 'assistant')
    tool_result_count = sum(1 for m in conversation_messages if m.get('type') == 'tool_result')

    tool_use_count = 0
    for m in conversation_messages:
        if m.get('type') == 'assistant':
            msg_content = m.get('message', {}).get('content', [])
            if isinstance(msg_content, list):
                tool_use_count += sum(
                    1 for item in msg_content
                    if isinstance(item, dict) and item.get('type') == 'tool_use'
                )

    # Write human-readable markdown format
    md_file = output_path / 'conversation.md'
    with open(md_file, 'w') as out:
        out.write("# LLM Conversation Log\n\n")
        out.write(f"**Source:** `{jsonl_file}`\n")
        out.write(f"**Extracted:** {datetime.now().isoformat()}\n")
        out.write(f"**Total Messages:** {len(conversation_messages)}\n")
        out.write(f"**User Messages:** {user_count}\n")
        out.write(f"**Assistant Messages:** {assistant_count}\n")
        out.write(f"**Tool Calls:** {tool_use_count}\n")
        out.write(f"**Tool Results:** {tool_result_count}\n\n")
        out.write("---\n\n")

        for i, msg in enumerate(conversation_messages):
            msg_type = msg.get('type', 'unknown')
            timestamp = msg.get('timestamp', '')

            # Extract the actual message content
            if msg_type == 'user':
                role = 'user'
                role_emoji = '👤'
                content = msg.get('message', {})
                if isinstance(content, dict):
                    content = content.get('content', '')
            elif msg_type == 'assistant':
                role = 'assistant'
                role_emoji = '🤖'
                content = msg.get('message', {}).get('content', [])
            elif msg_type == 'tool_result':
                role = 'tool_result'
                role_emoji = '🔧'
                content = msg.get('content', '')
            else:
                role = msg_type
                role_emoji = '❓'
                content = str(msg)

            out.write(f"## {role_emoji} Message {i+1} ({role})\n\n")

            if timestamp:
                out.write(f"*Timestamp: {timestamp}*\n\n")

            text_content = extract_text_content(content)

            # Truncate very long messages for readability
            if len(text_content) > 15000:
                text_content = text_content[:15000] + "\n\n... [truncated, see full JSONL for complete content] ..."

            out.write(f"{text_content}\n\n")
            out.write("---\n\n")

    # Write statistics
    stats_file = output_path / 'statistics.json'
    stats = {
        'source_file': str(jsonl_file),
        'extraction_time': datetime.now().isoformat(),
        'total_raw_entries': len(messages),
        'conversation_messages': len(conversation_messages),
        'user_messages': user_count,
        'assistant_messages': assistant_count,
        'tool_calls': tool_use_count,
        'tool_results': tool_result_count,
    }
    with open(stats_file, 'w') as f:
        json.dump(stats, f, indent=2)

    print(f"Extracted {len(conversation_messages)} conversation messages to {output_dir}")
    print(f"  - User messages: {user_count}")
    print(f"  - Assistant messages: {assistant_count}")
    print(f"  - Tool calls: {tool_use_count}")
    print(f"  - Tool results: {tool_result_count}")
    print(f"  - Markdown: {md_file}")
    print(f"  - Statistics: {stats_file}")
    return stats


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    jsonl_file = sys.argv[1]
    output_dir = sys.argv[2]

    if not os.path.exists(jsonl_file):
        print(f"Error: File not found: {jsonl_file}")
        sys.exit(1)

    extract_llm_calls(jsonl_file, output_dir)


if __name__ == "__main__":
    main()
