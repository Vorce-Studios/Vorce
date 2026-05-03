@{
    Mode = @{
        DefaultEnabled = $false
        PreferredApprovalChannel = 'telegram'
        HeartbeatMinutes = 20
        QuietHoursMinutes = 90
        RequireTelegramForApprovalRouting = $false
    }
    Notifications = @{
        ShortPrefix = '[Vorce-Studios]'
        IncludeIssueLinks = $true
        IncludePaperclipLinks = $false
    }
}
