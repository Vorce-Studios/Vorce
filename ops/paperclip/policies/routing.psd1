@{
    Executors = @{
        implementation = @{
            Preferred = 'jules'
            # Agile Swarm Matrix: Jules -> Antigravity Swarm -> Codex (High Leverage)
            FallbackChain = @('jules', 'antigravity', 'codex', 'gemini')
            RecoveryThreshold = 3 # If Jules fails 3x, skip to antigravity
        }
        parallel_implementation = @{
            Preferred = 'antigravity'
            FallbackChain = @('antigravity', 'jules', 'codex')
        }
        testing = @{
            Preferred = 'antigravity'
            FallbackChain = @('antigravity', 'ops', 'gemini')
        }
        documentation = @{
            Preferred = 'gemini'
            FallbackChain = @('gemini', 'antigravity', 'qwen')
        }
        review = @{
            Preferred = 'gemini'
            # Agile Feedback Loop: Reviewern ist gestattet, PRs direkt via Kommentar zurück an Jules/Antigravity zu schicken!
            FallbackChain = @('gemini', 'qwen', 'codex')
            DirectFeedbackAllowed = $true
        }
        triage = @{
            Preferred = 'qwen'
            FallbackChain = @('qwen', 'gemini')
        }
        architecture = @{
            Preferred = 'codex'
            FallbackChain = @('codex', 'antigravity', 'gemini')
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
        ceo = 'Victor (CEO / Chief Architect)'
        lena_assistant = 'Lena (Personal Assistant)'
        chief_of_staff = 'Leon (Chief of Staff / Capacity Router)'
        discovery = 'Noah (Discovery Scout)'
        jules = 'Julio (Builder)'
        jules_monitor = 'Julia (Session Monitor)'
        pr_monitor = 'Olivia (GitHub PR Monitor)'
        gemini_review = 'Mia (Gemini Reviewer)'
        qwen_review = 'Elias (Qwen Reviewer)'
        codex_review = 'Caleb (Codex Reviewer)'
        ops = 'Sophia (Ops / Merge Steward)'
        atlas = 'Atlas (Context Agent)'
        antigravity = 'Aria (Antigravity Builder)'
    }
}
