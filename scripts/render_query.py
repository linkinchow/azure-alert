"""Render a module query the same way the Bicep templates do, for local testing with `az graph query`.

Usage:
  python scripts/render_query.py m2-flash query-vm.kql 3d > out.kql
  python scripts/render_query.py m1-service-health query.kql 24h
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def kql_list(values):
    return ", ".join("'" + v.replace("'", "\\'") + "'" for v in values)


def flash_cases(rules):
    rules = [r for r in rules if r.get("enabled", True)]
    out = {}
    for field in ("category", "severity", "initiator"):
        by_name = [f"base in~ ({kql_list(r['names'])}), '{r[field]}'" for r in rules if r["names"]]
        by_kw = [
            "isempty(name) and (" + " or ".join(f"summary contains '{k}'" for k in r["summaryKeywords"]) + f"), '{r[field]}'"
            for r in rules
            if r.get("summaryKeywords")
        ]
        out[field] = ", ".join(by_name + by_kw)
    return out


def render(module, query_file, lookback):
    mdir = ROOT / "modules" / module
    q = (mdir / query_file).read_text(encoding="utf-8")
    if module == "m2-flash":
        cases = flash_cases(json.loads((mdir / "rules.json").read_text(encoding="utf-8"))["rules"])
        q = q.replace("__CATEGORY__", cases["category"]).replace("__SEVERITY__", cases["severity"]).replace("__INITIATOR__", cases["initiator"])
    if module == "m1-service-health":
        q = q.replace("__EVENT_TYPES__", kql_list(["ServiceIssue", "PlannedMaintenance", "HealthAdvisory", "SecurityAdvisory", "Billing"]))
    if module == "m5-quota":
        q = q.replace("__BAND_CASE__", "pct >= 95, 95, pct >= 90, 90, pct >= 80, 80").replace("__CRITICAL_BAND__", "95")
    if module == "m6-scheduled-events":
        q = q.replace("__STATUSES__", kql_list(["Scheduled", "Started", "Completed", "Canceled"])).replace("__SOURCES__", kql_list(["Platform"]))
    if module == "m8-aks":
        q = q.replace("__KINDS__", kql_list(["OutOfSupport", "EOLSoon", "UpgradeScheduled", "UpgradeNotSucceeded"]))
    return q.replace("__LOOKBACK__", lookback)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    print(render(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "24h"))
