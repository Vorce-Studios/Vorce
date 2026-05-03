cat << 'DIFF' > changelog.diff
<<<<<<< SEARCH
## [Unreleased]
- 2026-04-24: test(ci): VOR-41 Add Windows packaging smoke test to validate installer artifact (#356)
=======
## [Unreleased]
- 2026-04-27: fix: Fix stale selection feedback in module-canvas and node-editor
- 2026-04-24: test(ci): VOR-41 Add Windows packaging smoke test to validate installer artifact (#356)
>>>>>>> REPLACE
DIFF
patch -p0 CHANGELOG.md < changelog.diff
