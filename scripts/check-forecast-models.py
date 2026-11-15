"""Verify that both models produce a valid forecast from the same synthetic series."""
import json
import math
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

ORIGIN = "http://127.0.0.1:8000"
HORIZON = 10
SERIES_ID = "0" * 64
MODELS = (
    ("TimesFM", "/health/ready", "/v1/forecast", "google/timesfm-2.5-200m-pytorch"),
    ("Timestral", "/health/shadow/ready", "/v1/shadow/forecast", "mistralai/Timestral-28M"),
)


def wait_ready(name, path):
    print(f"Attente du modele {name}...", flush=True)
    deadline = time.monotonic() + 300
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(ORIGIN + path, timeout=5) as response:
                if json.load(response)["status"] == "READY":
                    return
        except urllib.error.HTTPError as error:
            if error.code != 503:
                raise
        except (urllib.error.URLError, TimeoutError):
            pass
        time.sleep(2)
    raise TimeoutError(f"{name} : modele indisponible apres 5 min ({path})")


def check_forecast(name, path, expected_model, token):
    request_id = str(uuid.uuid4())
    payload = {
        "schemaVersion": 1,
        "requestId": request_id,
        "horizonPoints": HORIZON,
        "series": [{"seriesId": SERIES_ID, "values": [100 + i % 24 for i in range(512)]}],
    }
    request = urllib.request.Request(
        ORIGIN + path,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        result = json.load(response)
    if result["modelId"] != expected_model or result["requestId"] != request_id:
        raise ValueError(f"{name} : modele ou identifiant de reponse inattendu")
    row, = result["series"]
    if row["seriesId"] != SERIES_ID:
        raise ValueError(f"{name} : identifiant de serie inattendu")
    for field in ("central", "q10", "q50", "q90"):
        points = row[field]
        if len(points) != HORIZON or not all(math.isfinite(point) for point in points):
            raise ValueError(f"{name} : {field} ne contient pas {HORIZON} points valides")
    print(f"{name} : {HORIZON} points, modele {result['modelId']}, inference {result['durationMillis']} ms")


def main():
    token = os.environ["TIMESFM_TOKEN"]
    for name, health, path, model in MODELS:
        try:
            wait_ready(name, health)
            check_forecast(name, path, model, token)
        except (OSError, ValueError, TypeError, KeyError) as error:
            print(f"{name} : echec du test ({error})", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
