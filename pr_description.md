## 🛡️ Sicherheits-Update

**🚨 Schweregrad:** MITTEL
**💡 Schwachstelle:** In `crates/vorce-control/src/web/server.rs` erlaubte die Verwendung von `tower_http::cors::Any` zusammen mit einem Wildcard-Origin (`*`) potenziell unsichere Cross-Origin-Anfragen. Dies ist problematisch für einen Kontroll-Server, da es externe Webseiten ermächtigen könnte, unerlaubt auf die API von Vorce zuzugreifen (CORS Bypass / CSRF-ähnliches Risiko bei Authentifizierungslücken).
**🎯 Impact:** Bösartige Webseiten könnten im Browser des Nutzers API-Aufrufe gegen Vorce absetzen, wenn der Nutzer die Vorce Web-Oberfläche nutzt und der Server so konfiguriert wurde, dass er `*` als Origin akzeptiert.
**🔧 Fix:** Die Verwendung von `Any` wurde entfernt. Stattdessen werden Wildcard-Einträge in `allowed_origins` beim Konfigurieren des Webservers herausgefiltert und die explizit angegebenen Origins streng geparst und der `CorsLayer` übergeben. Dadurch wird verhindert, dass versehentlich ein Wildcard-CORS konfiguriert wird.
**✅ Verifikation:** Alle CI Tests und Pre-Commit-Skripte (`scripts/jules/pre-pr-checks.sh`) wurden erfolgreich lokal durchlaufen und validiert. `cargo check` und `cargo test` für `vorce-control` waren erfolgreich.
