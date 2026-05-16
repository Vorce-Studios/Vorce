import os
import time
import json
import PIL.Image
import mss
import google.generativeai as genai
from vorce_automation import VorceActions

# --- KONFIGURATION ---
def get_api_key():
    key = os.environ.get("CuaAPI-Key")
    if key: return key
    try:
        import winreg
        for root in [winreg.HKEY_CURRENT_USER, winreg.HKEY_LOCAL_MACHINE]:
            path = r"Environment" if root == winreg.HKEY_CURRENT_USER else r"System\CurrentControlSet\Control\Session Manager\Environment"
            try:
                with winreg.OpenKey(root, path, 0, winreg.KEY_READ) as reg_key:
                    val, _ = winreg.QueryValueEx(reg_key, "CuaAPI-Key")
                    if val: return val
            except FileNotFoundError: continue
    except Exception: pass
    return None

API_KEY = get_api_key()
# Wir nutzen das aktuellste stabile Modell aus deiner Liste
MODEL_NAME = "models/gemini-2.5-flash" 

if API_KEY:
    genai.configure(api_key=API_KEY)

class VorcePilot:
    def __init__(self):
        self.actions = VorceActions()
        self.sct = mss.mss()
        self.model = None
        self._init_model()

    def _init_model(self):
        try:
            self.model = genai.GenerativeModel(
                model_name=MODEL_NAME,
                generation_config={"response_mime_type": "application/json"}
            )
        except Exception as e:
            print(f"Initialisierungsfehler: {e}")

    def capture_screen(self):
        screenshot = self.sct.grab(self.sct.monitors[1])
        img = PIL.Image.frombytes("RGB", screenshot.size, screenshot.bgra, "raw", "BGRX")
        return img

    def think_and_act(self, goal):
        print(f"\n[Pilot] Ziel: {goal}")
        
        while True:
            img = self.capture_screen()
            prompt = f"""
            Du bist ein Computer-Agent. Dein Ziel ist: {goal}
            Analysiere den Screenshot. Was ist der nächste Schritt?
            Antworte NUR im JSON-Format:
            {{
                "reasoning": "Warum mache ich das?",
                "action": "click" | "type" | "wait" | "done",
                "x": 0-1000, 
                "y": 0-1000,
                "text": "Text zum Tippen (falls action=type)",
                "finished": true/false
            }}
            Hinweis: Koordinaten x und y sind von 0 bis 1000.
            """
            
            try:
                response = self.model.generate_content([prompt, img])
                res_text = response.text.strip().replace("```json", "").replace("```", "")
                
                try:
                    decision = json.loads(res_text)
                except:
                    decision = eval(res_text)
                
                print(f"[KI] {decision['reasoning']}")
                
                if decision['action'] == "click":
                    self.actions.click(decision['x'], decision['y'])
                elif decision['action'] == "type":
                    self.actions.type_text(decision['text'])
                elif decision['action'] == "wait":
                    print("[Pilot] Warte kurz...")
                    time.sleep(2)
                
                if decision.get('finished', False) or decision['action'] == "done":
                    print("[Pilot] Aufgabe abgeschlossen!")
                    break
                    
                time.sleep(2)
                
            except Exception as e:
                print(f"Fehler im Loop: {e}")
                # Fallback auf ein alternatives Modell falls das gewählte nicht geht
                if "404" in str(e) or "not available" in str(e).lower():
                    global MODEL_NAME
                    MODEL_NAME = "models/gemini-3-flash-preview"
                    print(f"Wechsle auf Fallback-Modell: {MODEL_NAME}")
                    self._init_model()
                    continue
                break

if __name__ == "__main__":
    pilot = VorcePilot()
    if not API_KEY:
        print("!!! BITTE API-KEY SETZEN !!!")
    else:
        user_goal = input("Was soll ich für dich tun? ")
        pilot.think_and_act(user_goal)
