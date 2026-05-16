import pyautogui
import time
import json
import os
from pynput import mouse, keyboard

# Sicherheit: Maus in die Ecke oben links fahren bricht das Programm ab
pyautogui.FAILSAFE = True

class VorceActions:
    def __init__(self):
        self.screen_width, self.screen_height = pyautogui.size()

    def click(self, x_norm, y_norm):
        """Klickt auf normalisierte Koordinaten (0-1000)"""
        x = int(x_norm * self.screen_width / 1000)
        y = int(y_norm * self.screen_height / 1000)
        pyautogui.click(x, y)
        print(f"[Action] Klick auf {x}, {y}")

    def type_text(self, text):
        pyautogui.write(text, interval=0.05)
        print(f"[Action] Tippe: {text}")

    def play_macro(self, file_path):
        if not os.path.exists(file_path):
            print(f"Fehler: {file_path} nicht gefunden.")
            return
        
        with open(file_path, 'r') as f:
            events = json.load(f)
        
        print(f"Starte Wiedergabe: {file_path}")
        start_time = events[0]['time']
        for event in events:
            time.sleep(event['time'] - start_time)
            start_time = event['time']
            
            if event['type'] == 'click':
                pyautogui.click(event['x'], event['y'], button=event['button'])
            elif event['type'] == 'key':
                pyautogui.press(event['key'])
        print("Wiedergabe beendet.")

class VorceRecorder:
    def __init__(self):
        self.events = []
        self.recording = False

    def on_click(self, x, y, button, pressed):
        if pressed and self.recording:
            self.events.append({
                'time': time.time(),
                'type': 'click',
                'x': x,
                'y': y,
                'button': str(button).replace('Button.', '')
            })

    def on_press(self, key):
        if key == keyboard.Key.esc:
            self.recording = False
            return False # Stop listener
        
        if self.recording:
            try:
                char = key.char
            except AttributeError:
                char = str(key).replace('Key.', '')
                
            self.events.append({
                'time': time.time(),
                'type': 'key',
                'key': char
            })

    def record(self, filename="macro.json"):
        print("--- AUFNAHME STARTET ---")
        print("Drücke ESC zum Stoppen...")
        self.events = []
        self.recording = True
        
        with mouse.Listener(on_click=self.on_click) as m_listener:
            with keyboard.Listener(on_press=self.on_press) as k_listener:
                k_listener.join()
                # mouse listener stops when keyboard listener finishes
        
        with open(filename, 'w') as f:
            json.dump(self.events, f, indent=2)
        print(f"Aufnahme gespeichert in {filename}")

if __name__ == "__main__":
    # Test-Modus
    recorder = VorceRecorder()
    recorder.record("test_macro.json")
    
    print("Warte 3 Sekunden vor der Wiedergabe...")
    time.sleep(3)
    
    actions = VorceActions()
    actions.play_macro("test_macro.json")
