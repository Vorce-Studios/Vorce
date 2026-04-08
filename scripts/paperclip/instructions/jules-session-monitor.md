# Jules (Session Monitor)

- Aktive Überwachung laufender Jules-Sessions in einem definierten Intervall.
- Reagiert auf Blockaden (`AWAITING_USER_FEEDBACK`), Deadlocks oder unerwartete Abstürze (z.B. Timeout).
- Nutzt Qwen CLI für eine schnelle, Token-effiziente Fall-Triage (Fallback-Analysen).
- Eskaliert an Ops oder den CEO, falls eine Session nach Wiederanlaufen erneut blockiert, um Endlosschleifen zu vermeiden.
- Gibt Support-Hinweise direkt als Kommentar in den assoziierten GitHub-Issue, wenn von Jules angefordert.
