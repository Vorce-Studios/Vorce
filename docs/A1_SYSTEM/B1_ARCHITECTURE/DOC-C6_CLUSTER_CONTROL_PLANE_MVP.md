# Cluster Control Plane MVP (1.0)

Dieses Dokument definiert das Minimum Viable Product (MVP) für die Cluster Control Plane in Vorce 1.0 (Single-Master/Control-Only).

## 1. Ziel & Scope

Das Ziel für den 1.0-Release ist eine minimale, testbare Control-Plane, die den Betrieb eines zentralen Master-Knotens mit mehreren Rendering-Slaves ermöglicht (Single-Master).

**In Scope (1.0 MVP):**
* Definition des Nachrichtenmodells für Wiedergabesteuerung (Play, Pause, Stop, Seek) und State Sync.
* Definition des Mindestverhaltens für Ready/Health/Heartbeat-Signale.
* Dokumentation des erwarteten Reconnect/Timeout-Verhaltens.
* Dokumentation/Behandlung von Drift-Erkennung (entweder implementiert, testbar oder explizit als Einschränkung dokumentiert).

**Out of Scope (Post-1.0):**
* Multi-Master Setups (Redundanz, Failover).
* Dezentrale State-Verwaltung (jeder Node darf alles).
* Sub-Frame genaue Synchronisation (Genlock über Netzwerk) für alle Typen.
* Automatisches Load-Balancing von Rendering-Aufgaben.
* Komplexe Topologie-Erkennung und Auto-Discovery.

## 2. Nachrichtenmodell & Semantik

Das Nachrichtenmodell für die Kommunikation zwischen Master und Slaves/Peers basiert auf strikt deterministischen Befehlen. Der Master ist die *Source of Truth*.

### 2.1 State Sync & Playback Control

* **Play/Pause/Stop:**
  * Der Master sendet explizite `Play`, `Pause`, `Stop` Events.
  * *Semantik (Slave):* Der Slave wendet den Befehl sofort nach Erhalt an. Er versucht, sein lokales Playback an den Master-Zustand anzupassen.
* **Seek (Scrubbing):**
  * Der Master sendet ein `Seek(position)` Event.
  * *Semantik (Slave):* Der Slave springt hart an die spezifizierte Position.
* **State Sync (Full):**
  * Bei Verbindung oder auf Anforderung (z.B. nach Reconnect) sendet der Master den vollständigen aktuellen Wiedergabestatus (welche Medien, welche Position, Play/Pause-Status).

### 2.2 Ready / Health / Heartbeat

Um den Zustand des Clusters zu überwachen, implementieren alle Knoten ein Health-System:

* **Heartbeat:**
  * Master sendet periodisch (z.B. alle 1s) einen `Heartbeat`.
  * Slaves antworten mit einem `HeartbeatAck` (inklusive lokalem Status).
* **Ready-State:**
  * Ein Slave gilt als `Ready`, wenn er sich erfolgreich am Master angemeldet hat und den initialen `State Sync` vollständig verarbeitet hat.
* **Health:**
  * Die Health des Clusters wird auf dem Master aggregiert. Ein Slave gilt als *Healthy*, wenn regelmäßige HeartbeatAcks eingehen und keine Fehlerberichte vorliegen.

## 3. Reconnect & Timeout

* **Timeout:** Ein Node (Master oder Slave) gilt als getrennt (Disconnected), wenn für eine definierte Zeit (z.B. 5 Sekunden) keine Heartbeats empfangen wurden.
* **Master Timeout (aus Slave-Sicht):** Wenn der Slave den Master verliert, stoppt er die lokale Wiedergabe nicht zwingend sofort, markiert sich aber als "Unsynced". Neue Befehle werden abgewartet. (Fallback-Verhalten definierbar).
* **Reconnect:**
  * Ein getrennter Slave versucht aktiv, sich wieder mit dem bekannten Master zu verbinden.
  * Nach erfolgreichem Reconnect **muss** ein initialer `State Sync` erfolgen, bevor der Slave wieder aktiv rendert oder seine Position anpasst.

## 4. Drift-Erkennung (1.0)

Drift entsteht, wenn die lokale Playback-Geschwindigkeit von Slaves von der Master-Clock abweicht.

* **1.0 Ansatz:** Für das 1.0 MVP wird Drift-Erkennung **dokumentiert, aber nicht zwingend aktiv ausgeglichen (als bekannte Einschränkung)**.
* **Implementierung:** Der Master sendet periodisch (z.B. als Teil des State Syncs oder speziellen Time-Sync-Events) seine aktuelle Timecode/Position.
* **Slave-Verhalten:** Der Slave vergleicht die empfangene Master-Position mit seiner lokalen Position.
  * *Ist-Zustand 1.0:* Wenn der Drift einen kritischen Schwellenwert (z.B. > 100ms) überschreitet, führt der Slave einen harten `Seek` aus, um wieder aufzuholen (Snap). Kein weiches Pitch-Bending oder Resampling im MVP.

## 5. Testability / Harness

Für das 1.0 MVP muss die Control Plane testbar sein:

* **Manuelles Testharness:** Ein CLI-Tool oder eine dedizierte Debug-UI im Vorce-Client, die es erlaubt, sich als "Simulierter Slave" zu verbinden, Befehle (Play/Pause/Seek) zu empfangen und den lokalen State anzuzeigen.
* **Automatisierte Tests:** Unit-Tests für die Serialisierung/Deserialisierung der Nachrichten und die Zustandsübergänge (z.B. Reconnect-Logik, Ready-State).

---
*(Zugehörig zu Issue #46 und #656)*
