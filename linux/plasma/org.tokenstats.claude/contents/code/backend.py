#!/usr/bin/env python3
"""Data source for the Token Stats plasmoid: prints one JSON document to stdout.

Limits come from api.anthropic.com/api/oauth/usage (login from ~/.claude/.credentials.json, read only),
token counts from ~/.claude/projects/**/*.jsonl, prices from pricing.json (next to this file once installed, otherwise
Sources/TokenStats/Resources/pricing.json of the checkout).
"""
import glob, json, os, re, sys, urllib.error, urllib.request
from datetime import datetime, timedelta

HOME = os.path.expanduser("~")
HERE = os.path.dirname(os.path.abspath(__file__))
CREDS = f"{HOME}/.claude/.credentials.json"
PROJECTS = f"{HOME}/.claude/projects"
CACHE_DIR = f"{HOME}/.cache/tokenstats"
LIMITS_CACHE = f"{CACHE_DIR}/limits.json"
WINDOWS = {"session": 5 * 3600, "weekly_all": 7 * 86400, "weekly_scoped": 7 * 86400}


def plan_label(c):
    m = re.search(r"max_(\d+)x", c.get("rateLimitTier") or "")
    return f"{c.get('subscriptionType', '').title()}{f' {m.group(1)}×' if m else ''}"


def fetch_limits():
    c = json.load(open(CREDS))["claudeAiOauth"]
    req = urllib.request.Request(
        "https://api.anthropic.com/api/oauth/usage",
        headers={"Authorization": f"Bearer {c['accessToken']}", "anthropic-beta": "oauth-2025-04-20",
                 "User-Agent": "claude-code/2"})
    data = json.load(urllib.request.urlopen(req, timeout=15))
    rows = []
    for l in data.get("limits") or []:
        model = ((l.get("scope") or {}).get("model") or {}).get("display_name")
        if l["kind"] == "session":
            title, sub = "Session", "5 h"
        elif l["kind"] == "weekly_all":
            title, sub = "Week", "7 d, all models"
        else:
            title, sub = model or l["kind"].replace("_", " ").title(), "weekly limit"
        rows.append({"title": title, "sub": sub, "pct": l["percent"], "reset": l.get("resets_at"),
                     "window": WINDOWS.get(l["kind"], 7 * 86400)})
    extra = data.get("extra_usage") or {}
    extra_txt = None
    if extra.get("is_enabled"):
        div = 10 ** extra.get("decimal_places", 2)
        cur = {"EUR": "€", "USD": "$"}.get(extra.get("currency"), extra.get("currency", ""))
        extra_txt = f"Extra {extra['used_credits'] / div:,.2f} {cur} / {extra['monthly_limit'] / div:,.2f} {cur}"
    return {"plan": plan_label(c), "limits": rows, "extra": extra_txt}


def load_prices():
    for path in (f"{HERE}/pricing.json", f"{HERE}/../../../../../Sources/TokenStats/Resources/pricing.json"):
        try:
            d = json.load(open(path))
            return d["models"], d["asOf"]
        except (OSError, ValueError, KeyError):
            pass
    return {}, None


PRICES, PRICES_AS_OF = load_prices()


def price_for(model):
    if model in PRICES:
        return PRICES[model]
    undated = re.sub(r"-\d{8}$", "", model)
    if undated in PRICES:
        return PRICES[undated]
    pre = [k for k in PRICES if model.startswith(k)]
    return PRICES[max(pre, key=len)] if pre else None


def model_name(model):
    name = re.sub(r"-\d{8}$", "", model)
    if name.startswith("claude-"):
        parts = name[7:].split("-")
        return parts[0].title() + (" " + ".".join(parts[1:]) if parts[1:] else "")
    return model


def scan(path):
    """-> {msg_id: (day, model, in, out, cache_read, cw5m, cw1h)}"""
    msgs = {}
    with open(path, errors="replace") as f:
        for line in f:
            if '"usage"' not in line:
                continue
            try:
                e = json.loads(line)
                m = e["message"]; u = m["usage"]
                day = datetime.fromisoformat(e["timestamp"].replace("Z", "+00:00")).astimezone().date()
            except (KeyError, ValueError, TypeError):
                continue
            cc = u.get("cache_creation") or {}
            w1 = cc.get("ephemeral_1h_input_tokens", 0)
            w5 = cc.get("ephemeral_5m_input_tokens", u.get("cache_creation_input_tokens", 0) - w1)
            # streaming writes several lines per message id; the last one is the final count
            msgs[m.get("id") or e.get("uuid")] = (
                day, m.get("model", "?"), u.get("input_tokens", 0), u.get("output_tokens", 0),
                u.get("cache_read_input_tokens", 0), w5, w1)
    return msgs


def collect_usage(days=31):
    today = datetime.now().astimezone().date()
    since = today - timedelta(days=days - 1)
    per_day = {}
    seen = set()
    for path in glob.glob(f"{PROJECTS}/**/*.jsonl", recursive=True):
        if datetime.fromtimestamp(os.stat(path).st_mtime).date() < since:
            continue
        for mid, (day, model, *counts) in scan(path).items():
            if day < since or mid in seen or model == "<synthetic>":
                continue
            seen.add(mid)
            acc = per_day.setdefault(day, {}).setdefault(model, [0, 0, 0, 0, 0])
            for i, n in enumerate(counts):
                acc[i] += n
    out = []
    for day in (today - timedelta(days=i) for i in range(days - 1, -1, -1)):
        models = []
        for model, (i, o, cr, w5, w1) in per_day.get(day, {}).items():
            p = price_for(model)
            value = None if not p else (i * p["input"] + o * p["output"] + cr * p["cacheRead"]
                                        + w5 * p["cacheWrite5m"] + w1 * p["cacheWrite1h"])
            models.append({"model": model_name(model), "in": i, "out": o, "cache": cr + w5 + w1, "value": value})
        out.append({"date": day.isoformat(), "models": models})
    return out


def main():
    result = {"error": None, "priceDate": PRICES_AS_OF}
    try:
        info = fetch_limits()
        os.makedirs(CACHE_DIR, exist_ok=True)
        json.dump(info, open(LIMITS_CACHE, "w"))
    except urllib.error.HTTPError as e:
        info = None
        result["error"] = ("rate-limited, showing last values" if e.code == 429
                           else "login expired: run `claude`" if e.code == 401 else f"HTTP {e.code}")
    except Exception as e:
        info = None
        result["error"] = f"offline ({type(e).__name__})"
    if info is None:
        try:
            info = json.load(open(LIMITS_CACHE))
        except (OSError, ValueError):
            info = {"plan": "", "limits": [], "extra": None}
    result.update(info)
    try:
        result["usage"] = collect_usage()
    except Exception as e:
        result["usage"] = []
        result["error"] = result["error"] or f"usage: {type(e).__name__}"
    json.dump(result, sys.stdout)


if __name__ == "__main__":
    main()
