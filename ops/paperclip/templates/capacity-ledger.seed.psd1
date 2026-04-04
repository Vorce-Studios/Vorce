@{
    generatedAt = 'seed'
    tools = @{
        jules = @{
            status = 'available'
            mode = 'api'
            notes = 'Primary low-cost builder for implementation work.'
        }
        gemini = @{
            status = 'available'
            mode = 'cli'
            notes = 'Preferred reviewer and analysis worker.'
        }
        qwen = @{
            status = 'available'
            mode = 'cli'
            notes = 'Default fallback for review and triage.'
        }
        codex = @{
            status = 'available'
            mode = 'cli'
            notes = 'Primary CEO and high-risk escalation tool.'
        }
        copilot = @{
            status = 'degraded'
            mode = 'cli'
            notes = 'Limited availability; use as overflow only.'
        }
        antigravity = @{
            status = 'manual_only'
            mode = 'cli'
            notes = 'Useful worker host, but not treated as a headless runtime by default.'
        }
        atlas = @{
            status = 'optional'
            mode = 'workspace'
            notes = 'Context source backed by local atlas artifacts when present.'
        }
    }
}
