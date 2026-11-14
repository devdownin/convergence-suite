#!/usr/bin/env python3
"""Génère auth/realm-supervision.json : le royaume d'Autoroutes (upstream/) plus le client « kex-supervisor ».

Pourquoi un client distinct de « agent-anomalies » : Autoroutes nomme la source d'une déclaration
`mcp:<preferred_username>`. L'agent Kex déclare donc sous `mcp:service-account-kex-supervisor`, et ne
peut remplacer ni les incidents des équipements de péage ni ceux d'un autre agent.

Usage : scripts/build-realm.py          (réécrit auth/realm-supervision.json)
        scripts/build-realm.py --check  (échoue si le fichier généré n'est pas à jour ; utilisé en CI)
"""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
source = root / "upstream/autoroutes/auth/realm-supervision.json"
target = root / "auth/realm-supervision.json"

realm = json.loads(source.read_text(encoding="utf-8"))

agent = next(c for c in realm["clients"] if c["clientId"] == "agent-anomalies")
supervisor = json.loads(json.dumps(agent))  # copie profonde : même forme, autre identité
supervisor["clientId"] = "kex-supervisor"
supervisor["name"] = "Kex-anHarness — supervision"
supervisor["description"] = "Agent de supervision de la suite : déclare et lève des anomalies de gare"
supervisor["secret"] = "${KEX_SUPERVISOR_CLIENT_SECRET}"
supervisor.pop("id", None)
# Les mappeurs restent : sans celui des rôles du royaume (revendication « roles »), le jeton n'emporte
# pas ANOMALY_REPORTER et le MCP d'Autoroutes répond 403. Seuls leurs identifiants sont retirés, que
# Keycloak attribue à l'import et qui ne peuvent pas être partagés entre deux clients.
for mapper in supervisor.get("protocolMappers", []):
    mapper.pop("id", None)
realm["clients"].append(supervisor)

realm["users"].append({
    "username": "service-account-kex-supervisor",
    "enabled": True,
    "serviceAccountClientId": "kex-supervisor",
    "realmRoles": ["ANOMALY_REPORTER"],
})

rendu = json.dumps(realm, indent=2, ensure_ascii=False) + "\n"
if "--check" in sys.argv:
    if not target.exists() or target.read_text(encoding="utf-8") != rendu:
        sys.exit("auth/realm-supervision.json n'est pas à jour : lancer scripts/build-realm.py")
    print("auth/realm-supervision.json à jour")
else:
    target.write_text(rendu, encoding="utf-8")
    print(f"Écrit : {target.relative_to(root)}")
