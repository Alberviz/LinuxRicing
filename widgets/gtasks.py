#!/home/alberviz/.local/share/mchose-venv/bin/python
"""
Google Tasks CLI & JSON Backend for Linux / Caelestia / Quickshell
"""

import sys
import os
import json
import argparse
from datetime import datetime

CONFIG_DIR = os.path.expanduser("~/.config/google-tasks")
CACHE_FILE = os.path.expanduser("~/.cache/google_tasks.json")
CREDENTIALS_FILE = os.path.join(CONFIG_DIR, "credentials.json")
TOKEN_FILE = os.path.join(CONFIG_DIR, "token.json")
SCOPES = ["https://www.googleapis.com/auth/tasks"]

def ensure_config_dir():
    os.makedirs(CONFIG_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)

def get_service():
    ensure_config_dir()
    if not os.path.exists(TOKEN_FILE) and not os.path.exists(CREDENTIALS_FILE):
        return None

    try:
        from google.auth.transport.requests import Request
        from google.oauth2.credentials import Credentials
        from google_auth_oauthlib.flow import InstalledAppFlow
        from googleapiclient.discovery import build

        creds = None
        if os.path.exists(TOKEN_FILE):
            creds = Credentials.from_authorized_user_file(TOKEN_FILE, SCOPES)

        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
                with open(TOKEN_FILE, "w") as token:
                    token.write(creds.to_json())
            elif os.path.exists(CREDENTIALS_FILE):
                flow = InstalledAppFlow.from_client_secrets_file(CREDENTIALS_FILE, SCOPES)
                creds = flow.run_local_server(port=0)
                with open(TOKEN_FILE, "w") as token:
                    token.write(creds.to_json())
            else:
                return None

        return build("tasks", "v1", credentials=creds)
    except Exception as e:
        return None

def fetch_tasks():
    service = get_service()
    if not service:
        # Return helpful demo/instructional tasks when not yet logged in
        return {
            "authenticated": False,
            "message": "Configura credentials.json en ~/.config/google-tasks/",
            "tasks": [
                {
                    "id": "demo-1",
                    "title": "Colocar credentials.json en ~/.config/google-tasks/",
                    "due": "Pendiente",
                    "completed": False,
                    "notes": "Descárgalo de Google Cloud Console"
                },
                {
                    "id": "demo-2",
                    "title": "Ejecutar: gtasks --auth",
                    "due": "Paso 2",
                    "completed": False,
                    "notes": "Para iniciar sesión con tu cuenta de Google"
                },
                {
                    "id": "demo-3",
                    "title": "¡Tus tareas de Google Tasks aparecerán aquí!",
                    "due": "Listo",
                    "completed": False,
                    "notes": "Sincronización en tiempo real"
                }
            ]
        }

    try:
        tasklists = service.tasklists().list(maxResults=5).execute()
        items = tasklists.get("items", [])
        if not items:
            return {"authenticated": True, "tasks": []}

        # Use the primary list (first list)
        primary_list_id = items[0]["id"]
        tasks_result = service.tasks().list(
            tasklist=primary_list_id,
            showCompleted=True,
            showHidden=False,
            maxResults=10
        ).execute()

        raw_tasks = tasks_result.get("items", [])
        tasks = []
        for t in raw_tasks:
            title = t.get("title", "").strip()
            if not title:
                continue

            due_str = ""
            if "due" in t:
                try:
                    dt = datetime.fromisoformat(t["due"].replace("Z", "+00:00"))
                    due_str = dt.strftime("%d/%m")
                except Exception:
                    due_str = t["due"][:10]

            is_completed = (t.get("status") == "completed")
            tasks.append({
                "id": t["id"],
                "listId": primary_list_id,
                "title": title,
                "due": due_str,
                "completed": is_completed,
                "notes": t.get("notes", "")
            })

        # Sort uncompleted first
        tasks.sort(key=lambda x: x["completed"])

        data = {
            "authenticated": True,
            "listName": items[0].get("title", "Mis Tareas"),
            "tasks": tasks[:5] # Top 5 tasks for the widget
        }
        with open(CACHE_FILE, "w") as f:
            json.dump(data, f)
        return data
    except Exception as e:
        # Fallback to cache if offline
        if os.path.exists(CACHE_FILE):
            try:
                with open(CACHE_FILE, "r") as f:
                    return json.load(f)
            except Exception:
                pass
        return {"authenticated": False, "error": str(e), "tasks": []}

def toggle_task(task_id, list_id=None):
    service = get_service()
    if not service:
        # If demo mode, just toggle local cache
        return False

    try:
        if not list_id:
            tasklists = service.tasklists().list(maxResults=1).execute()
            list_id = tasklists.get("items", [])[0]["id"]

        task = service.tasks().get(tasklist=list_id, task=task_id).execute()
        current_status = task.get("status", "needsAction")
        new_status = "needsAction" if current_status == "completed" else "completed"

        task["status"] = new_status
        if new_status == "completed":
            task["completed"] = datetime.utcnow().isoformat() + "Z"
        else:
            task.pop("completed", None)

        service.tasks().update(tasklist=list_id, task=task_id, body=task).execute()
        fetch_tasks() # Refresh cache
        return True
    except Exception:
        return False

def add_task(title, list_id=None):
    service = get_service()
    if not service:
        return False

    try:
        if not list_id:
            tasklists = service.tasklists().list(maxResults=1).execute()
            list_id = tasklists.get("items", [])[0]["id"]

        body = {"title": title, "status": "needsAction"}
        service.tasks().insert(tasklist=list_id, body=body).execute()
        fetch_tasks()
        return True
    except Exception:
        return False

def main():
    parser = argparse.ArgumentParser(description="Google Tasks CLI & JSON Backend")
    parser.add_argument("--json", action="store_true", help="Output tasks formatted in JSON")
    parser.add_argument("--auth", action="store_true", help="Start OAuth2 authentication flow")
    parser.add_argument("--toggle", metavar="TASK_ID", help="Toggle completion status of task ID")
    parser.add_argument("--add", metavar="TITLE", help="Create a new task")
    args = parser.parse_args()

    if args.auth:
        ensure_config_dir()
        if not os.path.exists(CREDENTIALS_FILE):
            print(f"Error: No se encontró {CREDENTIALS_FILE}")
            print("Por favor descarga tus credenciales OAuth Desktop desde Google Cloud Console.")
            sys.exit(1)
        print("Iniciando flujo de autenticación de Google...")
        service = get_service()
        if service:
            print("¡Autenticación completada con éxito! Token guardado.")
        else:
            print("Falló la autenticación.")
        return

    if args.toggle:
        toggle_task(args.toggle)
        print(json.dumps({"success": True}))
        return

    if args.add:
        add_task(args.add)
        print(json.dumps({"success": True}))
        return

    # Default to json
    print(json.dumps(fetch_tasks(), indent=2))

if __name__ == "__main__":
    main()
