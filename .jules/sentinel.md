## 2026-04-15 - 🛡️ Sentinel: Update rustls-webpki to fix security vulnerability
**Schwachstelle:** The `rustls-webpki` crate had security vulnerabilities related to name constraints for URI names being incorrectly accepted (RUSTSEC-2026-0098) and permitted subtree name constraints for DNS names being accepted for certificates asserting a wildcard name (RUSTSEC-2026-0099). This affected the `Security Scan` CI check.
**Lektion:** Security dependencies like `rustls-webpki` need to be kept up-to-date to ensure they include patches for recently discovered vulnerabilities.
**Prävention:** Running `cargo audit` or `cargo deny check advisories` as part of CI catches these issues. The fix is to run `cargo update -p <crate>` to bump the vulnerable dependency to a patched version.
