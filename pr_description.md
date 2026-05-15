## 🧹 Code Health: Remove unused Mixxx MidiLearnTarget

🎯 **What:**
The `Mixxx` Midi assignment/learn target logic has been successfully removed from `MidiLearnTarget` and UI panels. To preserve backward compatibility for user config files, `Mixxx` is kept in `MidiAssignmentTarget` but marked as obsolete/ignored (`ObsoleteMixxx`).

💡 **Why:**
Removing unused code helps reduce technical debt, decreases overall complexity, and improves the maintainability of the codebase. Changing config formats necessitates a careful migration to ensure existing configurations correctly map unsupported data without crashing.

✅ **Verification:**
Ran `scripts/jules/pre-pr-checks.sh`. No failures or broken dependencies were found. Serde annotations verify that the obsolete config data is safely ignored when loading old user data while keeping serialization functioning.

✨ **Result:**
The codebase is now cleaner, having properly deprecated an unused `Mixxx` assignment target while gracefully handling old configurations.

## Verlinktes Issue
Fixes #1234
