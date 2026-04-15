
## 2025-02-12 - Fix rustls-webpki Security Advisories
**Schwachstelle:** The project was using `rustls-webpki` version `0.103.11`, which contained two critical security vulnerabilities (RUSTSEC-2026-0098 and RUSTSEC-2026-0099) related to improper handling of URI name constraints and wildcard certificates. This could potentially allow for misissued certificates to bypass validation constraints.
**Lektion:** Security dependencies like `rustls` and its ecosystem crates need to be monitored closely and updated proactively to patch critical vulnerabilities detected by `cargo-deny`.
**Prävention:** Updated `rustls-webpki` to `0.103.12` using `cargo update -p rustls-webpki` to resolve the advisories and ensure secure certificate validation.
