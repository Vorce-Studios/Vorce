# Git Safety Mandates

## Repository Protection
- **Target Repository**: {{TARGET_REPOSITORY}}
- **Allowed Branches**: {{ALLOWED_BRANCHES}}
- **Protected Branches**: {{PROTECTED_BRANCHES}}

## PR Safety Rules
### Merging Requirements
- **CI Status**: PR muss "SUCCESS" haben
- **Auto Approve**: {{AUTO_APPROVE}}
- **Review Required**: {{REVIEW_REQUIRED}}
- **Conflict Check**: PR darf keine Merge-Konflikte haben

### Naming Conventions
- **Branch Prefix**: {{BRANCH_PREFIX}}
- **PR Title**: {{PR_TITLE_FORMAT}}
- **Commit Message**: {{COMMIT_MESSAGE_FORMAT}}

## Safety Checks
### Before Merging
1. **PR Review**: PR muss von mindestens {{MIN_REVIEWS}} Reviewern geprüft werden
2. **Status Checks**: Alle Status Checks müssen erfolgreich sein
3. **No Conflicts**: Keine Merge-Konflikte mit Base Branch
4. **Size Limit**: PR Größe muss unter {{PR_SIZE_LIMIT}} KB liegen

### After Merging
1. **Branch Cleanup**: Automatisches Löschen des Feature Branches
2. **Tag Creation**: Automatisches Erstellen eines Release Tags
3. **Notification**: Automatische Benachrichtigung an Team

## Error Handling
- **Merge Conflicts**: Automatische Eskalation an CEO
- **PR Failures**: Automatische Wiederversuch nach {{RETRY_DELAY}} Minuten
- **Branch Protection**: Automatisches Rollback bei Regelverletzung

## Compliance
- **Audit Trail**: Alle Merge-Operationen werden geloggt
- **Approval Chain**: {{APPROVAL_CHAIN}} muss zustimmen
- **Backup Branches**: {{BACKUP_BRANCHES}} werden vor jedem Merge gesichert