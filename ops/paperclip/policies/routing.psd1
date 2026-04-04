@{
    Executors = @{
        implementation = @{
            Preferred = 'jules'
            FallbackChain = @('jules', 'gemini', 'qwen', 'codex', 'copilot', 'antigravity')
        }
        review = @{
            Preferred = 'gemini'
            FallbackChain = @('gemini', 'qwen', 'codex', 'copilot')
        }
        triage = @{
            Preferred = 'qwen'
            FallbackChain = @('qwen', 'gemini', 'codex', 'copilot')
        }
        architecture = @{
            Preferred = 'codex'
            FallbackChain = @('codex', 'gemini', 'qwen')
        }
        monitoring = @{
            Preferred = 'native'
            FallbackChain = @('native')
        }
    }

    Reviewers = @{
        Default = @('gemini', 'qwen', 'codex')
        HighRisk = @('codex', 'gemini', 'qwen')
    }

    Roles = @{
        ceo = 'CEO / Chief Architect'
        chief_of_staff = 'Chief of Staff / Capacity Router'
        discovery = 'Discovery Scout'
        jules = 'Jules Builder'
        gemini_review = 'Gemini Reviewer'
        qwen_review = 'Qwen Reviewer'
        codex_review = 'Codex Reviewer'
        ops = 'Ops / Merge Steward'
        atlas = 'Atlas Context Agent'
    }
}
