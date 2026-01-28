# Clawdbot Integration for Biomate

## Overview

Clawdbot is an open-source personal AI assistant system that enables multi-channel messaging integration. This document describes how Biomate is connected to Clawdbot to allow users to interact with the bioinformatics workflow assistant through various messaging platforms including Telegram and Slack.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Devices                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │ Telegram │  │  Slack   │  │ Discord  │  │ WhatsApp │        │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘        │
└───────┼─────────────┼─────────────┼─────────────┼───────────────┘
        │             │             │             │
        ▼             ▼             ▼             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Clawdbot Gateway                             │
│                  (localhost:18789)                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Channel Providers (Telegram, Slack, Discord, etc.)     │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Skills System (biomate skill)                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Agent (Claude Sonnet 4)                                │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
        │
        ▼ (future integration)
┌─────────────────────────────────────────────────────────────────┐
│                    Biomate Backend                              │
│                  (localhost:5000)                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  /api/biomate/chat - Chat API endpoint                  │   │
│  │  /api/biomate/health - Health check                     │   │
│  │  /api/biomate/status/:id - Workflow status              │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Installation

### Prerequisites

- Node.js 22+ (installed via fnm)
- Clawdbot CLI

### Install Node.js 22 via fnm

```bash
# Install fnm
curl -fsSL https://fnm.vercel.app/install | bash

# Install Node.js 22
fnm install 22
fnm use 22

# Verify
node --version  # Should show v22.x.x
```

### Install Clawdbot

```bash
npm install -g clawdbot
```

### Initialize Clawdbot

```bash
clawdbot init
```

This creates the configuration directory at `~/.clawdbot/`.

## Configuration

### Main Configuration File

Location: `~/.clawdbot/clawdbot.json`

```json
{
  "meta": {
    "lastTouchedVersion": "2026.1.24-3",
    "lastTouchedAt": "2026-01-28T06:35:52.022Z"
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-20250514",
        "fallbacks": []
      },
      "workspace": "/home/yzhang/clawd",
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      }
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "botToken": "<TELEGRAM_BOT_TOKEN>",
      "allowFrom": ["*"],
      "groupPolicy": "allowlist",
      "streamMode": "partial"
    },
    "slack": {
      "mode": "socket",
      "enabled": true,
      "botToken": "<SLACK_BOT_TOKEN>",
      "appToken": "<SLACK_APP_TOKEN>",
      "dm": {
        "policy": "open",
        "allowFrom": ["*"]
      },
      "groupPolicy": "open"
    }
  },
  "gateway": {
    "mode": "local"
  },
  "plugins": {
    "entries": {
      "telegram": {
        "enabled": true
      },
      "slack": {
        "enabled": true
      }
    }
  }
}
```

### Biomate Skill

Location: `~/clawd/skills/biomate/SKILL.md`

```markdown
# Biomate - Bioinformatics Workflow Assistant

## Description
Biomate enables natural language generation and execution of bioinformatics
workflows using Galaxy's 7000+ scientific tools. Use this skill when users
ask about genomics, proteomics, metabolomics, or any bioinformatics analysis.

## When to Use
- User asks about sequencing data analysis (RNA-seq, DNA-seq, ChIP-seq)
- User wants to run bioinformatics pipelines
- User asks about genomics, proteomics, or metabolomics
- User mentions tools like BLAST, BWA, STAR, DESeq2, etc.
- User has scientific data files (FASTQ, BAM, VCF, etc.)

## Tools

### biomate_query
Query Biomate for workflow suggestions, tool recommendations, or scientific guidance.

**Usage:**
biomate_query(message: "I need to align RNA-seq reads to the human genome")

**Parameters:**
- `message` (required): The user's bioinformatics question or request

**Returns:** Tool recommendations, workflow suggestions, and scientific guidance
```

## Channel Setup

### Telegram Setup

1. **Create a Bot with BotFather**
   - Open Telegram and search for `@BotFather`
   - Send `/newbot` command
   - Follow prompts to name your bot
   - Copy the bot token (format: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

2. **Configure in Clawdbot**
   ```json
   {
     "channels": {
       "telegram": {
         "enabled": true,
         "botToken": "<YOUR_BOT_TOKEN>",
         "dmPolicy": "pairing",
         "allowFrom": ["*"]
       }
     }
   }
   ```

3. **Start the Gateway**
   ```bash
   clawdbot gateway
   ```

4. **Test**
   - Search for your bot in Telegram by its username
   - Send a message to start chatting

### Slack Setup

#### Step 1: Create Slack App

1. Go to https://api.slack.com/apps
2. Click "Create New App" → "From scratch"
3. Name your app and select your workspace

#### Step 2: Configure App Manifest

Go to **App Manifest** in the left sidebar and paste this JSON:

```json
{
  "display_information": {
    "name": "BioMateAI"
  },
  "features": {
    "bot_user": {
      "display_name": "BioMateAI",
      "always_online": true
    },
    "app_home": {
      "messages_tab_enabled": true,
      "messages_tab_read_only_enabled": false
    }
  },
  "oauth_config": {
    "scopes": {
      "bot": [
        "chat:write",
        "im:history",
        "im:read",
        "im:write",
        "app_mentions:read",
        "channels:history",
        "channels:read"
      ]
    }
  },
  "settings": {
    "socket_mode_enabled": true,
    "event_subscriptions": {
      "bot_events": [
        "app_mention",
        "message.im"
      ]
    },
    "org_deploy_enabled": false,
    "token_rotation_enabled": false
  }
}
```

#### Step 3: Generate Tokens

1. **App Token** (for Socket Mode):
   - Go to **Basic Information** → **App-Level Tokens**
   - Click "Generate Token and Scopes"
   - Add scope: `connections:write`
   - Copy the token (format: `xapp-...`)

2. **Bot Token**:
   - Go to **OAuth & Permissions**
   - Click "Install to Workspace"
   - Copy the "Bot User OAuth Token" (format: `xoxb-...`)

#### Step 4: Configure in Clawdbot

```json
{
  "channels": {
    "slack": {
      "mode": "socket",
      "enabled": true,
      "botToken": "xoxb-...",
      "appToken": "xapp-...",
      "dm": {
        "policy": "open",
        "allowFrom": ["*"]
      },
      "groupPolicy": "open"
    }
  }
}
```

#### Step 5: Reinstall App

After any manifest changes, go to **Install App** → **Reinstall to Workspace**.

## Running the Gateway

### Start Gateway

```bash
# Foreground (for debugging)
clawdbot gateway

# Background
nohup clawdbot gateway > /tmp/clawdbot-gateway.log 2>&1 &
```

### Check Status

```bash
clawdbot channels status
```

Expected output:
```
Gateway reachable.
- Telegram default: enabled, configured, running, mode:polling, token:config
- Slack default: enabled, configured, running, bot:config, app:config
```

### Health Check

```bash
clawdbot doctor
```

### View Logs

```bash
# Gateway startup log
tail -f /tmp/clawdbot-gateway.log

# Detailed log
tail -f /tmp/clawdbot/clawdbot-$(date +%Y-%m-%d).log
```

## Security Considerations

### Network Security

- **All connections are localhost (127.0.0.1)** - No public IPs exposed
- Clawdbot gateway runs on `ws://127.0.0.1:18789`
- Biomate backend runs on `http://localhost:5000`
- Channel connections (Telegram, Slack) are **outbound only** - no inbound ports needed

### Authentication

- **Telegram**: Uses `dmPolicy: "pairing"` by default - unknown senders receive a pairing code
- **Slack**: Configure `dm.policy` and `dm.allowFrom` to control access
- **API Keys**: Store tokens in config file (not in environment for multi-account support)

### Recommendations

1. Use `groupPolicy: "allowlist"` for production to restrict channel access
2. Enable DM pairing for unknown users
3. Keep the gateway on localhost only
4. Rotate tokens periodically

## Troubleshooting

### Slack Bot Not Responding

1. **Check Event Subscriptions**: Ensure `message.im` and `app_mention` are subscribed
2. **Enable Messages Tab**: In App Home, enable "Messages Tab"
3. **Reinstall App**: After manifest changes, reinstall to workspace
4. **Check DM Policy**: Ensure `dm.policy: "open"` if you want open access

### Gateway Won't Start

1. **Check Node Version**: Must be 22+
   ```bash
   node --version
   ```

2. **Check Port Availability**:
   ```bash
   lsof -i :18789
   ```

3. **Validate Config**:
   ```bash
   clawdbot doctor --fix
   ```

### Telegram Bot Not Working

1. **Verify Bot Token**: Check with BotFather
2. **Check Polling Mode**: Telegram uses polling (outbound), no webhook needed
3. **Start Conversation**: User must send `/start` or any message first

## Biomate Chat API

The following endpoints are available for messaging channel integration:

### POST /api/biomate/chat

Send a message to Biomate and get a response.

**Request:**
```json
{
  "message": "I need to align RNA-seq reads",
  "sessionId": "slack-U123456",
  "channel": "slack",
  "userId": "U123456"
}
```

**Response:**
```json
{
  "success": true,
  "response": "I can help you with RNA-seq alignment...",
  "sessionId": "slack-U123456"
}
```

### GET /api/biomate/health

Health check endpoint.

**Response:**
```json
{
  "status": "ok",
  "service": "biomate",
  "assistantReady": true
}
```

### GET /api/biomate/status/:invocationId

Get workflow execution status.

**Response:**
```json
{
  "invocationId": "abc123",
  "state": "running",
  "progress": 50
}
```

## Future Integration

The current setup uses Clawdbot's built-in Claude agent. Future integration will:

1. **Connect Biomate Skill to Backend**: Route bioinformatics queries to Biomate's Galaxy Assistant
2. **Workflow Execution**: Allow users to execute workflows directly from messaging channels
3. **Status Updates**: Push workflow progress updates to users via their preferred channel
4. **File Handling**: Support file uploads (FASTQ, BAM, etc.) through messaging platforms

## References

- [Clawdbot GitHub Repository](https://github.com/clawdbot/clawdbot)
- [Clawdbot Documentation](https://docs.clawd.bot)
- [Slack API Documentation](https://api.slack.com/docs)
- [Telegram Bot API](https://core.telegram.org/bots/api)
- [Biomate Project](../README.md)

## Changelog

- **2026-01-28**: Initial Clawdbot integration with Telegram and Slack channels
