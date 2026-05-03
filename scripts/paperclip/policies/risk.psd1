@{
    HighRiskPathHints = @(
        'crates/Vorce-render/',
        'crates/Vorce-media/',
        'crates/Vorce-core/',
        'crates/Vorce-ui/',
        'crates/Vorce/',
        'crates/Vorce-io/'
    )

    UiPathHints = @(
        'crates/Vorce-ui/',
        'crates/Vorce/src/app/',
        'crates/Vorce/src/ui/',
        'assets/',
        'resources/'
    )

    ReviewRequiredKeywords = @(
        'unsafe',
        'render',
        'preview',
        'projector',
        'media',
        'audio',
        'output',
        'persistence',
        'migration',
        'dependency',
        'ci'
    )

    MergeFastLane = @{
        MaxFiles = 5
        MaxNetLines = 150
        AllowVisibleUiChanges = $false
        AllowDependencyChanges = $false
        AllowUnsafeChanges = $false
    }
}
