# Architecture - Wee-Orchestrator

> This document describes the runtime architecture of Wee-Orchestrator as of v2.0.

## Table of Contents

- [System Overview](#system-overview)
- [Component Diagram](#component-diagram)
- [Request Flow Chat Message](#request-flow-chat-message)
- [Request Flow Web UI](#request-flow-web-ui)
- [Task Scheduler Flow](#task-scheduler-flow)
- [Authentication Flow](#authentication-flow-web-ui-pairing)
- [Component Reference](#component-reference)
- [Data Stores](#data-stores)
- [Deployment Topology](#deployment-topology)
- [Environment Variables](#environment-variables)

---

## System Overview

Wee-Orchestrator is a Python-based multi-channel AI orchestration platform. It receives messages from three inbound channels (**Telegram**, **WebEx**, **Web UI**), routes them through a shared `SessionManager`, dispatches work to one of five AI CLI runtimes, and returns the response.

A built-in **Task Scheduler** can trigger AI jobs autonomously and deliver results back to the originating user via the same channel adapters.

```text
┌──────────────────────────────────────────────────────────────────┐
│                      Wee-Orchestrator Host                        │
│                                                                   │
│   Telegram ──► TelegramConnector ──┐                             │
│                                    │                             │
│   WebEx ────► WebEXConnector ──────┼──► SessionManager ──► AI   │
│                                    │                   CLIs      │
│   Browser ──► FastAPI /api/v1 ─────┘                             │
│                     │                                             │
│              TaskScheduler ───────────────────────────────────── │
└──────────────────────────────────────────────────────────────────┘
```

---

## Component Diagram

```mermaid
graph TB
    subgraph Inbound["Inbound Channels"]
        TG["Telegram"]
        WX["WebEx"]
        BR["Browser"]
    end

    subgraph Connectors["Channel Connectors"]
        TC["TelegramConnector"]
        WC["WebEXConnector"]
        FA["FastAPI App"]
    end

    subgraph Core["Orchestrator Core"]
        SM["SessionManager"]
        HM["HistoryManager"]
        AM["AuthManager"]
        RL["RateLimiter"]
    end

    subgraph Scheduler["Task Scheduler"]
        TS["TaskScheduler"]
    end

    subgraph Runtimes["AI CLI Runtimes"]
        CP["Copilot"]
        OC["OpenCode"]
        CL["Claude"]
        GM["Gemini"]
        CX["Codex"]
    end

    TG --> TC
    WX --> WC
    BR --> FA

    TC --> SM
    WC --> SM
    FA --> SM
    FA --> AM
    FA --> RL
    FA --> HM
    FA --> TS

    SM --> CP
    SM --> OC
    SM --> CL
    SM --> GM
    SM --> CX

    HM --> CH
    TS --> SM
```

---

## Request Flow Chat Message

The following sequence shows how a Telegram message is processed end-to-end.

```mermaid
sequenceDiagram
    participant U as User
    participant TC as TelegramConnector
    participant SM as SessionManager
    participant CLI as AI CLI
    participant TG as Telegram API

    U->>TG: sends message
    TC->>TG: getUpdates
    TG-->>TC: payload
    TC->>TC: ACL check
    TC->>SM: execute
    SM->>CLI: subprocess
    CLI-->>SM: stdout
    SM-->>TC: cleaned response
    TC->>TG: sendMessage
```

---

## Request Flow Web UI

Chat messages from the Web UI use SSE streaming.

```mermaid
sequenceDiagram
    participant B as Browser
    participant FA as FastAPI
    participant SM as SessionManager
    participant CLI as AI CLI

    B->>FA: GET config
    B->>FA: POST pairing
    B->>FA: POST verify
    B->>FA: POST sessions
    B->>FA: POST stream
    FA->>SM: execute
    SM->>CLI: subprocess
    CLI-->>SM: lines
    SM-->>FA: chunks
    FA-->>B: events
```

---

## Task Scheduler Flow

```mermaid
sequenceDiagram
    participant U as User
    participant FA as FastAPI
    participant TS as TaskScheduler
    participant SM as SessionManager

    U->>FA: POST jobs
    FA->>TS: schedule
    TS->>SM: execute
    SM-->>TS: result
    TS->>U: notify
```

---

## Authentication Flow Web UI Pairing

```mermaid
flowchart LR
    A([Browser]) -->|1| B[FastAPI]
    B -->|2| C[AuthManager]
    C -->|3| D([User phone])
    D -->|4| A
    A -->|5| B
```

---

## Component Reference

### SessionManager

| Method | Purpose |
| --- | --- |
| execute | Entry point |
| run_runtimes | Subprocess wrappers |
| strip_metadata | Clean stdout |

### HistoryManager

Stores chat history.

### AuthManager

Handles authentication.

### TaskScheduler

Embedded scheduler.

---

## Data Stores

| Store | Path |
| --- | --- |
| Session map | ~/.copilot/n8n-session-map.json |
| Chat history | ~/.copilot/chat-history.json |
| Scheduler jobs | /opt/.task-scheduler/jobs.json |

---

## Deployment Topology

```text
┌────────────────────────────────────────────────────┐
│              CLI-Tools Host                        │
│  ┌──────────────────────────────────────────────┐   │
│  │  PRODUCTION                                   │   │
│  └──────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────┘
```

---

## Environment Variables

| Variable | Default |
| --- | --- |
| APP_ENV | PROD |
| API_PORT | 8000 |
| SCHEDULER_ENABLED | true |
