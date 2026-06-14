# Cluster QA Matrix

## 1. Ziel
Eine belastbare QA- und Betriebsabsicherung fuer Multi-Instance-Cluster herstellen, inklusive Recovery, Drift-Absicherung und klarer Reconnect-Szenarien.

## 2. Reconnect-, Timeout- und Recovery-Szenarien
| Fall | Setup | Aktion | Erwartetes Ergebnis | Typ |
|---|---|---|---|---|
| Master Timeout | Master und Slave verbunden | Master faellt aus | Slave haelt Playback-Zustand, markiert sich als "Unsynced", stoppt aber nicht sofort | Automated |
| Slave Reconnect | Slave ist getrennt | Slave verbindet sich neu | Initialer `State Sync` wird vollstaendig durchgefuehrt, bevor Slave wieder rendert | Automated |
| Stale Peer State | Lokaler und entfernter Cluster-Status divergiert | Reconciliation | Online-Status wird bevorzugt, Offline-Zustand überschreibt nicht lokalen Online-Zustand | Automated |

## 3. Drift- und Zeitbasis-Faelle
| Fall | Setup | Aktion | Erwartetes Ergebnis | Typ |
|---|---|---|---|---|
| Deterministic Drift Resolution | Zwei Instanzen haben abweichende Properties bei gleicher ID | Reconciliation | Lexikographisch groesserer Wert setzt sich deterministisch durch | Automated |
| Output Assignment Drift | Master und Remote haben verschiedene Instanzen fuer Output assigned | Reconciliation | Kleinere Instanz-ID wird deterministisch ausgewaehlt | Automated |

## 4. Smoke-Faelle: Multi-Instance Control und lokaler Multi-Projector Output
| Fall | Setup | Aktion | Erwartetes Ergebnis | Typ |
|---|---|---|---|---|
| Multi-Projector Loopback | Master und Local Slave auf gleicher Maschine | Zuweisung von >1 Output an Slave | Cluster Config akzeptiert Zuordnung, Zuweisung wird registriert | Automated |
