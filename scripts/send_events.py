"""Post standard events to the Router (test helper).

  python scripts/send_events.py <events.json> [max]

<events.json> is either a list of standard events, a list of ARG rows ({eventId, event}) as produced by
`az graph query` / render_query.py, or {"events": [...]}. The Router callback URL is fetched with the
signed-in az account; requires env vars AA_SUB and AA_RG, AA_ROUTER defaults to aa-router.
"""
import json
import os
import subprocess
import sys
import urllib.request

SUB = os.environ["AA_SUB"]  # subscription of the alerting resource group
RG = os.environ["AA_RG"]  # alerting resource group
ROUTER = os.environ.get("AA_ROUTER", "aa-router")


def router_url():
    rid = f"/subscriptions/{SUB}/resourceGroups/{RG}/providers/Microsoft.Logic/workflows/{ROUTER}"
    return subprocess.check_output(
        f'az rest --method post --url "https://management.azure.com{rid}/triggers/manual/listCallbackUrl?api-version=2019-05-01" --query value -o tsv',
        shell=True,
        env={**os.environ, "MSYS_NO_PATHCONV": "1"},
    ).decode().strip()


def load(path, limit):
    data = json.load(open(path, encoding="utf-8"))
    if isinstance(data, dict):
        data = data.get("events", [])
    events = [row["event"] if "event" in row else row for row in data]
    return events[:limit]


if __name__ == "__main__":
    events = load(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 100)
    req = urllib.request.Request(router_url(), data=json.dumps({"events": events}).encode(), headers={"Content-Type": "application/json"})
    resp = urllib.request.urlopen(req, timeout=60)
    print(resp.status, resp.read().decode())
