import subprocess
import time
import sys
import os

def start_vorce_and_wait():
    print("Starte Vorce Build & Launch...")
    batch_path = os.path.join("VjMapper", "scripts", "vorce", "run-vorce-Full.bat")
    
    # Run the batch script and capture output
    process = subprocess.Popen(
        batch_path, 
        stdout=subprocess.PIPE, 
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP
    )
    
    print("Warte auf Kompilierung und Start (Das kann beim ersten Mal dauern)...")
    
    app_started = False
    # Read output line by line
    for line in iter(process.stdout.readline, ''):
        print(f"[Vorce Log] {line.strip()}")
        
        # Heuristic: Cargo finishes compiling and runs the binary
        # Vorce will likely print something like "Starting..." or "Initialized"
        # We also check for 'wgpu' or 'egui' initialization logs which are common in Bevy apps
        lower_line = line.lower()
        if "running `target\\release\\vorce.exe`" in lower_line or \
           "wgpu" in lower_line or \
           "initialized" in lower_line or \
           "starting vorce" in lower_line and not "mode with default" in lower_line:
            
            # Wait a few seconds after the first promising log line for the GUI to actually render
            print("\n>>> VORCE START-SIGNAL ERKANNT! Warte 5 Sekunden auf GUI... <<<")
            time.sleep(5)
            app_started = True
            break

    if not app_started:
        print("Konnte Start-Signal im Log nicht finden.")
        
    return process

if __name__ == "__main__":
    process = start_vorce_and_wait()
    if process:
        print("\nVorce sollte nun offen sein. Das Python-Skript läuft noch, um den Prozess am Leben zu halten.")
        print("Drücke Strg+C zum Beenden.")
        try:
            process.wait()
        except KeyboardInterrupt:
            process.terminate()
