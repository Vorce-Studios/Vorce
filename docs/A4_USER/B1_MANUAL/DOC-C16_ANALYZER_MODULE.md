## FFT Analyzer Modul

**Was es macht:**
Das FFT Analyzer Modul analysiert eingehende Audiosignale in Echtzeit und wandelt sie in Frequenzbänder (Bass, Mitten, Höhen) um. Diese Werte können genutzt werden, um Parameter anderer Module synchron zur Musik zu steuern.

![Screenshot: Das FFT Analyzer Modul isoliert im Workspace](docs/assets/missing/modul-analyzer-ui.png)

**So benutzt du es:**

1. Ziehe das Modul in den Workspace.
2. Verbinde den Eingang mit einem Audio-Eingangsmodul.
3. Verbinde den Ausgang mit einem Parameter eines anderen Moduls (z.B. Shape-Größe).
4. Stelle den Parameter **Gain** auf deinen gewünschten Wert ein, um die Empfindlichkeit anzupassen.

![Screenshot: FFT Analyzer verbunden mit einem Shape-Modul](docs/assets/missing/modul-analyzer-connection.png)

**Tipp 💡:**
> Nutze das Smoothing, um sprunghafte Parameteränderungen bei schnellen Beats zu glätten.

**Parameter-Übersicht:**

| Parameter | Beschreibung | Standardwert |
|---|---|---|
| `Gain` | Verstärkt das Eingangssignal. | 1.0 |
| `Smoothing` | Glättet die Ausgangswerte über die Zeit. | 0.5 |
| `Frequency Range` | Legt den analysierten Frequenzbereich fest (Low, Mid, High). | All |
