"""Inspect Logic App runs during testing.

  python scripts/la_runs.py runs <workflow> [n]          recent runs with status; failed actions with error
  python scripts/la_runs.py sent [n]                       cards the router sent in its latest n runs, with the Feishu response
  python scripts/la_runs.py output <workflow> <action> [n] outputs of an action in the latest n runs

Requires env vars AA_SUB (subscription id) and AA_RG (resource group of the alerting solution); AA_ROUTER = router workflow name (default aa-router).
"""
import json
import os
import subprocess
import sys
import urllib.request

SUB = os.environ["AA_SUB"]  # subscription of the alerting resource group
RG = os.environ["AA_RG"]  # alerting resource group
BASE = f"https://management.azure.com/subscriptions/{SUB}/resourceGroups/{RG}/providers/Microsoft.Logic/workflows"
_token = None


def token():
    global _token
    if not _token:
        _token = subprocess.check_output("az account get-access-token --query accessToken -o tsv", shell=True).decode().strip()
    return _token


def get(url):
    if url.startswith("/"):
        url = "https://management.azure.com" + url
    sep = "&" if "?" in url else "?"
    if "api-version" not in url:
        url += sep + "api-version=2019-05-01"
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token()})
    return json.load(urllib.request.urlopen(req, timeout=60))


def fetch_link(link):
    # outputsLink / inputsLink are SAS URLs that need no auth header
    return json.load(urllib.request.urlopen(link["uri"], timeout=60))


def runs(workflow, n):
    data = get(f"{BASE}/{workflow}/runs?$top={n}")["value"]
    for r in data:
        p = r["properties"]
        print(p["startTime"][:19], p["status"], r["name"])
        if p["status"] == "Failed":
            acts = get(f"{BASE}/{workflow}/runs/{r['name']}/actions")["value"]
            for a in acts:
                ap = a["properties"]
                if ap["status"] == "Failed":
                    err = ap.get("error") or {}
                    print("   FAILED", a["name"], json.dumps(err, ensure_ascii=False)[:600])


def sent(n, router=os.environ.get("AA_ROUTER", "aa-router")):
    data = get(f"{BASE}/{router}/runs?$top={n}")["value"]
    for r in reversed(data):
        print("=" * 100)
        print(r["properties"]["startTime"][:19], "run", r["properties"]["status"])
        try:
            cards = get(f"{BASE}/{router}/runs/{r['name']}/actions/Card/repetitions")["value"]
            posts = {p["name"]: p for p in get(f"{BASE}/{router}/runs/{r['name']}/actions/Post_card/repetitions")["value"]}
        except Exception as e:  # run without events
            print("  (no cards)", e)
            continue
        for c in sorted(cards, key=lambda x: x["name"]):
            card = fetch_link(c["properties"]["outputsLink"])["card"]
            post = posts.get(c["name"])
            resp = fetch_link(post["properties"]["outputsLink"]).get("body") if post and post["properties"].get("outputsLink") else None
            print(" ", card["header"]["template"], card["header"]["title"]["content"][:110], "->", json.dumps(resp, ensure_ascii=False)[:80])


def output(workflow, action, n):
    data = get(f"{BASE}/{workflow}/runs?$top={n}")["value"]
    for r in data:
        try:
            a = get(f"{BASE}/{workflow}/runs/{r['name']}/actions/{action}")["properties"]
        except Exception as e:  # action may not have run
            print(r["name"], "n/a", e)
            continue
        out = fetch_link(a["outputsLink"]) if a.get("outputsLink") else None
        print(r["properties"]["startTime"][:19], a["status"], json.dumps(out, ensure_ascii=False)[:3000])


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    cmd = sys.argv[1]
    if cmd == "runs":
        runs(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 5)
    elif cmd == "sent":
        sent(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
    elif cmd == "output":
        output(sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 1)
