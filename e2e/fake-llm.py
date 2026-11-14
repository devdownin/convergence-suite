#!/usr/bin/env python3
"""Modèle factice compatible OpenAI pour le banc de bout en bout (compose.e2e.yaml).

Il ne remplace pas le jugement d'un modèle : il rend la boucle déterministe pour éprouver tout ce qui
l'entoure — appel d'outil réel, citation de la mesure, décision gouvernée, approbation, action,
vérification. Il lit vraiment le résultat d'etat_gare : une gare ACTIVE donne un processus OK et aucune
anomalie, une gare STALE donne une anomalie avec DECLARE_ANOMALY. Il n'invente donc pas la panne, il la
recopie.

Hors cycle de supervision (toute autre requête de l'agent), il répond un texte neutre.
"""
import json
import os
import re
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATION = os.environ.get("E2E_STATION", "GL-BPV-0134")
PROCESS = os.environ.get("E2E_PROCESS", "pipeline-peage")
PORT = int(os.environ.get("PORT", "8000"))
CYCLE_MARKER = "Processus à relever"
ANOMALY = {"type_ano": "Coupure d'alimentation électrique d'une voie", "cardinalite": 1, "criticite": "Haute"}


def log(message):
    print(f"[fake-llm] {message}", flush=True)


def text_of(message):
    content = message.get("content")
    if isinstance(content, list):
        return "".join(part.get("text", "") for part in content if isinstance(part, dict))
    return content or ""


def completion(model, content=None, tool_calls=None):
    message = {"role": "assistant", "content": content, "refusal": None}
    if tool_calls:
        message["tool_calls"] = tool_calls
    return {
        "id": "chatcmpl-" + uuid.uuid4().hex,
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [{"index": 0, "message": message, "logprobs": None,
                     "finish_reason": "tool_calls" if tool_calls else "stop"}],
        "usage": {"prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150},
    }


def cycle_answer(tool_name, results):
    """Réponse structurée du cycle, d'après le dernier résultat d'etat_gare."""
    status = None
    for result in results:
        found = re.findall(r'\\?"etat\\?"\s*:\s*\\?"(\w+)', result)
        if found:
            status = found[-1]
    gap = None
    for result in results:
        found = re.findall(r'\\?"ecartSecondes\\?"\s*:\s*(\d+)', result)
        if found:
            gap = found[-1]
    coverage = {"complete": False, "stopReason": "NOT_REPORTED"}
    if status != "STALE":
        state = "OK" if status == "ACTIVE" else "UNKNOWN"
        log(f"cycle : {STATION} {status or 'illisible'} → {state}, aucune anomalie")
        return {"processes": [{"processId": PROCESS, "state": state, "coverage": coverage,
                               "note": f"etat_gare {STATION} : {status or 'illisible'}"}],
                "anomalies": []}
    log(f"cycle : {STATION} STALE (écart {gap} s) → DECLARE_ANOMALY proposé")
    return {
        "processes": [{"processId": PROCESS, "state": "ERROR", "coverage": coverage,
                       "note": f"Gare {STATION} sans passage depuis {gap} s"}],
        "anomalies": [{
            "processId": PROCESS,
            "title": f"Gare {STATION} muette",
            "severity": "ERROR",
            "observations": [{"label": f"État de la gare {STATION}", "value": f"STALE, écart {gap} s",
                              "tool": tool_name}],
            "analysis": "Aucun passage n'est plus enregistré sur une gare habituellement très fréquentée. "
                        "Une coupure d'équipement est probable.",
            "probableCause": "Coupure d'alimentation d'une voie",
            "confidence": 0.9,
            "recommendation": f"Déclarer l'anomalie sur la gare {STATION} pour l'afficher sur la carte",
            "capability": "DECLARE_ANOMALY",
            "actionArguments": {"gare": STATION, "anomalies": [ANOMALY]},
        }],
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, status, body):
        payload = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            self.send(200, {"object": "list", "data": [{"id": "fake-scripted", "object": "model", "owned_by": "e2e"}]})
        else:
            self.send(200, {"status": "UP"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        request = json.loads(self.rfile.read(length) or b"{}")
        if not self.path.rstrip("/").endswith("/chat/completions"):
            self.send(404, {"error": {"message": "route inconnue du modèle factice : " + self.path}})
            return
        if request.get("stream"):
            # Le cycle passe par l'appel bloquant ; un flux n'est pas prévu dans ce banc.
            self.send(400, {"error": {"message": "le modèle factice ne diffuse pas en flux"}})
            return
        model = request.get("model", "fake-scripted")
        messages = request.get("messages", [])
        if not any(CYCLE_MARKER in text_of(m) for m in messages):
            log("requête hors cycle : réponse neutre")
            self.send(200, completion(model, "Réponse du modèle factice de banc d'essai."))
            return
        names = [t.get("function", {}).get("name", "") for t in request.get("tools", [])]
        tool = next((n for n in names if n == "etat_gare" or n.endswith("_etat_gare")), None)
        results = [text_of(m) for m in messages if m.get("role") == "tool"]
        if not results and tool:
            log(f"cycle : appel de {tool} sur {STATION} ({len(names)} outils proposés)")
            self.send(200, completion(model, None, [{"id": "call_" + uuid.uuid4().hex[:12], "type": "function",
                                                     "function": {"name": tool,
                                                                  "arguments": json.dumps({"gare": STATION})}}]))
            return
        if not tool:
            log(f"cycle : etat_gare absent des {len(names)} outils proposés")
        self.send(200, completion(model, json.dumps(cycle_answer(tool, results), ensure_ascii=False)))


if __name__ == "__main__":
    log(f"écoute sur {PORT}, gare {STATION}, processus {PROCESS}")
    sys.stdout.flush()
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
