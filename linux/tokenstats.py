#!/usr/bin/env python3
"""Linux tray port of mahype/token-stats (MIT), Claude Code only.

Limits come from api.anthropic.com/api/oauth/usage, token counts from ~/.claude/projects/**/*.jsonl,
prices from Sources/TokenStats/Resources/pricing.json of this repo (list prices = API comparison value).
"""
import json, os, sys, glob, re, subprocess, threading, urllib.request, urllib.error
from collections import defaultdict
from datetime import datetime, timedelta, timezone

# gtk-layer-shell must be loaded before libwayland-client, so re-exec once with LD_PRELOAD
import glob as _glob
_LAYER_LIB = next(iter(_glob.glob("/usr/lib*/**/libgtk-layer-shell.so.0", recursive=True)), None)
if _LAYER_LIB and _LAYER_LIB not in os.environ.get("LD_PRELOAD", ""):
    os.environ["LD_PRELOAD"] = (_LAYER_LIB + " " + os.environ.get("LD_PRELOAD", "")).strip()
    os.execv(sys.executable, [sys.executable] + sys.argv)

import cairo  # noqa: F401  (needed for the draw callbacks)
import gi
gi.require_foreign("cairo")
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GLib, Gio

try:
    gi.require_version("GtkLayerShell", "0.1")
    from gi.repository import GtkLayerShell as LayerShell
except (ValueError, ImportError):
    LayerShell = None

HOME = os.path.expanduser("~")
HERE = os.path.dirname(os.path.abspath(__file__))
CREDS = f"{HOME}/.claude/.credentials.json"
PROJECTS = f"{HOME}/.claude/projects"
ICON_DIR = f"{HOME}/.cache/tokenstats"
INTERVAL_S = 300

GREEN, YELLOW, RED = (0.30, 0.75, 0.50), (0.89, 0.66, 0.24), (0.85, 0.30, 0.30)
BLUE, BLUE_DIM = (0.0, 0.57, 1.0), (0.06, 0.37, 0.64)
WINDOWS = {"session": 5 * 3600, "weekly_all": 7 * 86400, "weekly_scoped": 7 * 86400}

CSS = b"""
window.ts { background: #1e1e1e; color: #e6e6e6; }
.ts-title { font-size: 20px; font-weight: bold; }
.ts-dim { color: #9a9a9a; }
.ts-h { font-size: 16px; font-weight: bold; }
.ts-big { font-size: 24px; font-weight: bold; }
.ts-mono { font-family: monospace; }
.ts-card { background: #2c2c2c; border-radius: 12px; padding: 12px 14px; }
.ts-pill { border: 1px solid; border-radius: 99px; padding: 1px 10px; font-weight: bold; }
.ts-chip { background: #2c2c2c; border-radius: 8px; padding: 6px 10px; font-family: monospace; }
.ts-foot { background: #242424; padding: 10px 16px; }
button.ts-tab { background: none; border: none; border-radius: 0; box-shadow: none; color: #9a9a9a;
                padding: 6px 12px; font-weight: bold; border-bottom: 3px solid transparent; }
button.ts-tab:checked { color: #fff; border-bottom-color: #0a84ff; }
button.ts-seg { background: #2c2c2c; border: none; border-radius: 8px; box-shadow: none; color: #9a9a9a; padding: 3px 14px; }
button.ts-seg:checked { background: #3a3a3a; color: #fff; font-weight: bold; }
button.ts-range { background: none; border: none; box-shadow: none; color: #9a9a9a; padding: 2px 6px; }
button.ts-range:checked { color: #fff; font-weight: bold; }
"""


# ---------- data ----------

def load_creds():
    return json.load(open(CREDS))["claudeAiOauth"]


def plan_label(c):
    tier = c.get("rateLimitTier") or ""
    m = re.search(r"max_(\d+)x", tier)
    return f"{c.get('subscriptionType', '').title()}{f' {m.group(1)}×' if m else ''}"


def fetch_limits():
    c = load_creds()
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
    if extra.get("is_enabled"):
        div = 10 ** extra.get("decimal_places", 2)
        cur = {"EUR": "€", "USD": "$"}.get(extra.get("currency"), extra.get("currency", ""))
        extra = f"Extra {extra['used_credits'] / div:,.2f} {cur} / {extra['monthly_limit'] / div:,.2f} {cur}"
    else:
        extra = None
    return {"plan": plan_label(c), "limits": rows, "extra": extra}


def load_prices():
    try:
        d = json.load(open(f"{HERE}/../Sources/TokenStats/Resources/pricing.json"))
        return d["models"], d["asOf"]
    except (OSError, ValueError, KeyError):
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


# file -> (mtime, size, {msg_id: (day, model, in, out, cache_read, cw5m, cw1h)})
_file_cache = {}


def _scan(path):
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
    """-> {day: {model: [in, out, cache_read, cw5m, cw1h]}}"""
    today = datetime.now().astimezone().date()
    since = today - timedelta(days=days - 1)
    out = defaultdict(lambda: defaultdict(lambda: [0, 0, 0, 0, 0]))
    seen = set()
    for path in glob.glob(f"{PROJECTS}/**/*.jsonl", recursive=True):
        st = os.stat(path)
        if datetime.fromtimestamp(st.st_mtime).date() < since:
            continue
        c = _file_cache.get(path)
        if not c or c[:2] != (st.st_mtime, st.st_size):
            c = (st.st_mtime, st.st_size, _scan(path))
            _file_cache[path] = c
        for mid, (day, model, *counts) in c[2].items():
            if day < since or mid in seen or model == "<synthetic>":
                continue
            seen.add(mid)
            acc = out[day][model]
            for i, n in enumerate(counts):
                acc[i] += n
    return out


def value_of(counts, model):
    p = price_for(model)
    if not p:
        return None
    i, o, cr, w5, w1 = counts
    return (i * p["input"] + o * p["output"] + cr * p["cacheRead"]
            + w5 * p["cacheWrite5m"] + w1 * p["cacheWrite1h"])


def fmt(n):
    return f"{n / 1e6:.1f} M" if n >= 1e6 else f"{n / 1e3:.0f} k" if n >= 1e3 else str(n)


def until(iso):
    secs = int((datetime.fromisoformat(iso) - datetime.now(timezone.utc)).total_seconds())
    return max(secs, 0)


def dur(secs):
    d, r = divmod(int(secs), 86400); h, r = divmod(r, 3600)
    if d:
        return f"{d} d" if not h else f"{d} d {h} h"
    return f"{h} h {r // 60} min" if h else f"{r // 60} min"


# ---------- widgets ----------

def color_for(pct):
    return RED if pct >= 100 else YELLOW if pct >= 80 else GREEN


def rgb(hexcolor):
    return tuple(int(hexcolor[i:i + 2], 16) / 255 for i in (1, 3, 5))


def rounded(cr, x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -1.5708, 0); cr.arc(x + w - r, y + h - r, r, 0, 1.5708)
    cr.arc(x + r, y + h - r, r, 1.5708, 3.1416); cr.arc(x + r, y + r, r, 3.1416, 4.7124)
    cr.close_path()


class Meter(Gtk.DrawingArea):
    """Progress bar with pace mark; hatched area = gap between used share and elapsed share."""

    def __init__(self, pct, elapsed):
        super().__init__()
        self.pct, self.elapsed = pct, elapsed
        self.set_size_request(-1, 16)
        self.connect("draw", self.on_draw)

    def on_draw(self, _w, cr):
        w, h = self.get_allocated_width(), self.get_allocated_height()
        col = color_for(self.pct)
        used = min(self.pct, 100) / 100 * w
        pace = None if self.elapsed is None else min(max(self.elapsed, 0), 1) * w
        rounded(cr, 0, 0, w, h, h / 2)
        cr.clip()
        cr.set_source_rgb(0.2, 0.2, 0.2); cr.paint()
        cr.set_source_rgb(*col); cr.rectangle(0, 0, used, h); cr.fill()
        if pace is not None:
            a, b = sorted((used, pace))
            cr.save()
            cr.rectangle(a, 0, b - a, h); cr.clip()
            cr.set_source_rgba(*col, 0.55); cr.set_line_width(2)
            for x in range(int(a) - h, int(b) + h, 5):
                cr.move_to(x, h); cr.line_to(x + h, 0)
            cr.stroke()
            cr.restore()
            cr.set_source_rgba(1, 1, 1, 0.6); cr.rectangle(pace - 1, 0, 2, h); cr.fill()


class BarChart(Gtk.DrawingArea):
    def __init__(self, series):  # [(label, value, is_last)]
        super().__init__()
        self.series = series
        self.set_size_request(-1, 110)
        self.connect("draw", self.on_draw)

    def on_draw(self, _w, cr):
        w, h = self.get_allocated_width(), self.get_allocated_height()
        n = len(self.series)
        if not n:
            return
        top = max((v for _, v, _ in self.series), default=0) or 1
        gap = 6 if n <= 12 else 2
        bw = (w - gap * (n - 1)) / n
        ch = h - 20
        every = 1 if n <= 8 else max(1, n // 7)
        cr.select_font_face("sans-serif"); cr.set_font_size(11)
        for i, (label, v, last) in enumerate(self.series):
            x = i * (bw + gap)
            bh = v / top * ch
            cr.set_source_rgb(*(BLUE if last else BLUE_DIM))
            rounded(cr, x, ch - bh, bw, bh, 3); cr.fill()
            if label and (i % every == 0 or last):
                cr.set_source_rgb(*((1, 1, 1) if last else (0.6, 0.6, 0.6)))
                ext = cr.text_extents(label)
                cr.move_to(x + (bw - ext.width) / 2, h - 4); cr.show_text(label)


def label(text, css=None, xalign=0, wrap=False):
    l = Gtk.Label(label=text, xalign=xalign)
    l.set_line_wrap(wrap)
    for c in (css or "").split():
        l.get_style_context().add_class(c)
    return l


def markup(l, color):
    l.set_markup(f'<span foreground="{color}">{GLib.markup_escape_text(l.get_text())}</span>')
    return l


def hexc(c):
    return "#%02x%02x%02x" % tuple(int(x * 255) for x in c)


class Popup(Gtk.Window):
    def __init__(self, app):
        super().__init__(title="Token Stats")
        self.app = app
        self.get_style_context().add_class("ts")
        self.set_default_size(400, 640)
        self.set_resizable(False)
        self.set_decorated(False)
        self.connect("delete-event", lambda *_: self.hide() or True)
        self.connect("key-press-event", lambda _w, e: e.keyval == Gdk.KEY_Escape and self.hide())
        self.connect("focus-out-event", self.on_focus_out)
        self.shown_at = 0
        if LayerShell:
            LayerShell.init_for_window(self)
            LayerShell.set_layer(self, LayerShell.Layer.TOP)
            LayerShell.set_namespace(self, "tokenstats")
            LayerShell.set_keyboard_mode(self, LayerShell.KeyboardMode.ON_DEMAND)
        self.page, self.range = "limits", "7d"
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(outer)

        head = Gtk.Box(spacing=8, margin=16)
        head.pack_start(label("Token Stats", "ts-title"), True, True, 0)
        seg = Gtk.Box(spacing=2)
        self.page_btns = {}
        for key, text in (("limits", "Limits"), ("usage", "Usage")):
            b = Gtk.ToggleButton(label=text); b.get_style_context().add_class("ts-seg")
            b.connect("clicked", self.on_page, key); seg.pack_start(b, False, False, 0)
            self.page_btns[key] = b
        head.pack_end(seg, False, False, 0)
        outer.pack_start(head, False, False, 0)

        tabs = Gtk.Box(margin_left=10)
        t = Gtk.ToggleButton(label="● Claude"); t.set_active(True); t.get_style_context().add_class("ts-tab")
        tabs.pack_start(t, False, False, 0)
        outer.pack_start(tabs, False, False, 0)
        outer.pack_start(Gtk.Separator(), False, False, 0)

        self.body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=16, spacing=14)
        sw = Gtk.ScrolledWindow(); sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw.add(self.body)
        outer.pack_start(sw, True, True, 0)

        foot = Gtk.Box(spacing=8); foot.get_style_context().add_class("ts-foot")
        self.status = label("", "ts-dim")
        foot.pack_start(self.status, True, True, 0)
        rb = Gtk.Button(label="⟳"); rb.connect("clicked", lambda *_: app.refresh())
        foot.pack_end(rb, False, False, 0)
        qb = Gtk.Button(label="Quit"); qb.connect("clicked", lambda *_: Gtk.main_quit())
        foot.pack_end(qb, False, False, 0)
        outer.pack_end(foot, False, False, 0)
        self.page_btns["limits"].set_active(True)

    def on_focus_out(self, *_):
        # ignore the focus flicker right after opening
        if GLib.get_monotonic_time() - self.shown_at > 500_000:
            self.hide()

    def show_at(self, x, y):
        """Open centred above (or below) the tray icon at screen position x, y."""
        self.render()
        self.show_all()
        self.shown_at = GLib.get_monotonic_time()
        if LayerShell:
            mon = Gdk.Display.get_default().get_monitor(0)
            geo = mon.get_geometry()
            w, h = self.get_size()
            from_top = y < geo.height / 2
            for edge, on in ((LayerShell.Edge.LEFT, True), (LayerShell.Edge.TOP, from_top),
                             (LayerShell.Edge.BOTTOM, not from_top), (LayerShell.Edge.RIGHT, False)):
                LayerShell.set_anchor(self, edge, on)
            LayerShell.set_margin(self, LayerShell.Edge.LEFT, int(min(max(x - w / 2, 8), geo.width - w - 8)))
            LayerShell.set_margin(self, LayerShell.Edge.TOP if from_top else LayerShell.Edge.BOTTOM, 8)
        self.present()

    def on_page(self, btn, key):
        if not btn.get_active():
            if self.page == key:
                btn.set_active(True)
            return
        self.page = key
        for k, b in self.page_btns.items():
            if k != key:
                b.set_active(False)
        self.render()

    def on_range(self, btn, key):
        if btn.get_active() and self.range != key:
            self.range = key
            self.render()

    def render(self):
        for c in self.body.get_children():
            c.destroy()
        a = self.app
        note = f"  ·  ⚠ {a.note}" if a.note else ""
        self.status.set_text((f"updated {a.updated:%H:%M}" if a.updated else "loading…") + note)
        (self.render_limits if self.page == "limits" else self.render_usage)()
        self.body.show_all()

    def render_limits(self):
        info = self.app.info
        if not info:
            self.body.pack_start(label("Loading…", "ts-dim"), False, False, 0)
            return
        worst = max((r["pct"] for r in info["limits"]), default=0)
        h = Gtk.Box(spacing=8)
        h.pack_start(label("Claude", "ts-h"), False, False, 0)
        h.pack_start(label(info["plan"], "ts-dim ts-mono"), False, False, 0)
        pill = markup(label(f"{worst:.0f} %", "ts-pill"), hexc(color_for(worst)))
        h.pack_end(pill, False, False, 0)
        self.body.pack_start(h, False, False, 0)
        for r in info["limits"]:
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            top = Gtk.Box(spacing=8)
            top.pack_start(label(r["title"], "ts-h"), False, False, 0)
            top.pack_start(label(r["sub"], "ts-dim"), False, False, 0)
            top.pack_end(markup(label(f"{r['pct']:.0f} %", "ts-h"), hexc(color_for(r["pct"]))), False, False, 0)
            box.pack_start(top, False, False, 0)
            left = until(r["reset"]) if r["reset"] else None
            elapsed = None if left is None else 1 - left / r["window"]
            box.pack_start(Meter(r["pct"], elapsed), False, False, 2)
            bottom = Gtk.Box()
            reset_txt = ""
            if r["reset"]:
                rt = datetime.fromisoformat(r["reset"]).astimezone()
                fmt_t = "%H:%M" if left < 86400 else "%a %H:%M"
                reset_txt = f"Reset {rt.strftime(fmt_t)}"
            bottom.pack_start(label(reset_txt, "ts-dim"), False, False, 0)
            if elapsed is not None:
                gap = (r["pct"] / 100 - elapsed) * r["window"]
                if abs(gap) < r["window"] * 0.02:
                    txt, col = "on pace", None
                elif gap > 0:
                    txt, col = f"{dur(gap)} ahead", hexc(color_for(r["pct"]))
                else:
                    txt, col = f"{dur(-gap)} unused", hexc(color_for(r["pct"]))
                l = label(txt, "ts-dim")
                bottom.pack_end(markup(l, col) if col else l, False, False, 0)
            box.pack_start(bottom, False, False, 0)
            self.body.pack_start(box, False, False, 4)
        if info["extra"]:
            self.body.pack_start(Gtk.Separator(), False, False, 0)
            chip = label(info["extra"], "ts-chip")
            row = Gtk.Box(); row.pack_start(chip, False, False, 0)
            self.body.pack_start(row, False, False, 0)

    def render_usage(self):
        usage = self.app.usage
        today = datetime.now().astimezone().date()
        info = self.app.info
        h = Gtk.Box(spacing=8)
        h.pack_start(label("Claude", "ts-h"), False, False, 0)
        if info:
            h.pack_start(label(info["plan"], "ts-dim ts-mono"), False, False, 0)
        self.body.pack_start(h, False, False, 0)

        ranges = [("1d", "Today", 1), ("7d", "7 days", 7), ("30d", "30 days", 30), ("month", "This month", None)]
        rbox = Gtk.Box(spacing=4)
        for key, text, _ in ranges:
            b = Gtk.ToggleButton(label=text); b.set_active(key == self.range)
            b.get_style_context().add_class("ts-range"); b.connect("toggled", self.on_range, key)
            rbox.pack_start(b, False, False, 0)
        self.body.pack_start(rbox, False, False, 0)

        n = {"1d": 1, "7d": 7, "30d": 30}.get(self.range) or today.day
        days = [today - timedelta(days=i) for i in range(n - 1, -1, -1)]
        per_model = defaultdict(lambda: [0, 0, 0, 0, 0])
        series, total_val, unpriced = [], 0.0, False
        for d in days:
            day_tokens = 0
            for model, c in usage.get(d, {}).items():
                for i in range(5):
                    per_model[model][i] += c[i]
                day_tokens += sum(c)
            series.append((d.strftime("%a")[:2] if n <= 7 else str(d.day), day_tokens, d == today))
        total = sum(sum(c) for c in per_model.values())
        cache = sum(c[2] + c[3] + c[4] for c in per_model.values())
        for model, c in per_model.items():
            v = value_of(c, model)
            if v is None:
                unpriced = True
            else:
                total_val += v

        cards = Gtk.Box(spacing=10, homogeneous=True)
        for title, big, small in (("TOKENS", fmt(total), f"{fmt(cache)} of which cache"),
                                  ("API COMPARISON VALUE", f"{total_val:,.2f} $", "at list prices")):
            card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            card.get_style_context().add_class("ts-card")
            card.pack_start(label(title, "ts-dim"), False, False, 0)
            card.pack_start(label(big, "ts-big"), False, False, 0)
            card.pack_start(label(small, "ts-dim"), False, False, 0)
            cards.pack_start(card, True, True, 0)
        self.body.pack_start(cards, False, False, 0)
        if n > 1:
            self.body.pack_start(BarChart(series), False, False, 4)

        for model, c in sorted(per_model.items(), key=lambda kv: -sum(kv[1])):
            v = value_of(c, model)
            row = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            top = Gtk.Box()
            top.pack_start(label(model_name(model), "ts-h"), False, False, 0)
            top.pack_end(label(f"{v:,.2f} $" if v is not None else "n/a", "ts-h"), False, False, 0)
            row.pack_start(top, False, False, 0)
            row.pack_start(label(f"{fmt(c[0])} in · {fmt(c[1])} out · {fmt(c[2] + c[3] + c[4])} cache", "ts-dim"),
                           False, False, 0)
            self.body.pack_start(row, False, False, 0)
            self.body.pack_start(Gtk.Separator(), False, False, 0)
        tot = Gtk.Box()
        tot.pack_start(label(f"{n} days · {fmt(total)} tokens" if n > 1 else f"Today · {fmt(total)} tokens", "ts-h"),
                       False, False, 0)
        tot.pack_end(label(f"{total_val:,.2f} $", "ts-h"), False, False, 0)
        self.body.pack_start(tot, False, False, 0)
        asof = f" (as of {PRICES_AS_OF})" if PRICES_AS_OF else ""
        foot = ("Local token counts from the session logs × list price" + asof + ", incl. cache rates. "
                "No billing data, only what the same usage would cost via the API."
                + (" Some models are missing from the price table." if unpriced else ""))
        self.body.pack_start(label(foot, "ts-dim", wrap=True), False, False, 0)


# ---------- tray (StatusNotifierItem, so a left click calls Activate with the icon position) ----------

SNI_XML = """<node><interface name="org.kde.StatusNotifierItem">
<method name="Activate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
<method name="SecondaryActivate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
<method name="ContextMenu"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
<method name="Scroll"><arg type="i" direction="in"/><arg type="s" direction="in"/></method>
<property name="Category" type="s" access="read"/><property name="Id" type="s" access="read"/>
<property name="Title" type="s" access="read"/><property name="Status" type="s" access="read"/>
<property name="WindowId" type="u" access="read"/><property name="IconName" type="s" access="read"/>
<property name="IconPixmap" type="a(iiay)" access="read"/><property name="OverlayIconName" type="s" access="read"/>
<property name="AttentionIconName" type="s" access="read"/><property name="ItemIsMenu" type="b" access="read"/>
<property name="Menu" type="o" access="read"/><property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
<signal name="NewIcon"/><signal name="NewToolTip"/><signal name="NewStatus"><arg type="s"/></signal>
</interface></node>"""


def render_icon(pct, size=32):
    """Ring in the state colour with the percentage inside, as ARGB32 bytes in network order."""
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    cr = cairo.Context(surf)
    c, r, lw = size / 2, size / 2 - 3, 3.5
    cr.set_line_width(lw)
    cr.set_source_rgba(0.6, 0.6, 0.6, 0.45); cr.arc(c, c, r, 0, 6.2832); cr.stroke()
    cr.set_source_rgb(*color_for(pct))
    cr.arc(c, c, r, -1.5708, -1.5708 + min(pct, 100) / 100 * 6.2832); cr.stroke()
    cr.select_font_face("sans-serif", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    cr.set_font_size(12 if pct < 100 else 10)
    cr.set_source_rgb(0.92, 0.92, 0.92)
    txt = f"{pct:.0f}"
    ext = cr.text_extents(txt)
    cr.move_to(c - ext.width / 2 - ext.x_bearing, c - ext.height / 2 - ext.y_bearing); cr.show_text(txt)
    raw = bytearray(surf.get_data())  # native little-endian BGRA -> ARGB
    out = bytearray(len(raw))
    out[0::4], out[1::4], out[2::4], out[3::4] = raw[3::4], raw[2::4], raw[1::4], raw[0::4]
    return size, size, bytes(out)


def display_scale():
    """Fractional scale of the first output (GTK only reports the rounded-up integer)."""
    try:
        out = subprocess.run(["kscreen-doctor", "-j"], capture_output=True, text=True, timeout=5).stdout
        return float(next(o["scale"] for o in json.loads(out)["outputs"] if o.get("enabled")))
    except (OSError, ValueError, StopIteration, KeyError, subprocess.SubprocessError):
        return 1.0


class Tray:
    PATH = "/StatusNotifierItem"

    def __init__(self, on_activate):
        self.on_activate, self.pixmap = on_activate, render_icon(0)
        self.last_activate, self.scale = 0, display_scale()
        self.conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.name = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
        Gio.bus_own_name_on_connection(self.conn, self.name, Gio.BusNameOwnerFlags.NONE, None, None)
        info = Gio.DBusNodeInfo.new_for_xml(SNI_XML).interfaces[0]
        self.conn.register_object(self.PATH, info, self.on_call, self.on_get, None)
        self.conn.call_sync("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                            "org.kde.StatusNotifierWatcher", "RegisterStatusNotifierItem",
                            GLib.Variant("(s)", (self.name,)), None, Gio.DBusCallFlags.NONE, 3000, None)

    def on_call(self, _c, _sender, _path, _iface, method, params, inv):
        if method == "Activate":
            x, y = params.unpack()
            # Plasma sends the icon centre in physical pixels, and twice per click
            now = GLib.get_monotonic_time()
            if now - self.last_activate < 400_000:
                inv.return_value(None)
                return
            self.last_activate = now
            x, y = x / self.scale, y / self.scale
            GLib.idle_add(self.on_activate, x, y)
        inv.return_value(None)

    def on_get(self, _c, _sender, _path, _iface, prop):
        w, h, data = self.pixmap
        return {
            "Category": GLib.Variant("s", "ApplicationStatus"), "Id": GLib.Variant("s", "tokenstats"),
            "Title": GLib.Variant("s", "Token Stats"), "Status": GLib.Variant("s", "Active"),
            "WindowId": GLib.Variant("u", 0), "IconName": GLib.Variant("s", ""),
            "IconPixmap": GLib.Variant("a(iiay)", [(w, h, list(data))]),
            "OverlayIconName": GLib.Variant("s", ""), "AttentionIconName": GLib.Variant("s", ""),
            "ItemIsMenu": GLib.Variant("b", False), "Menu": GLib.Variant("o", "/NO_DBUSMENU"),
            "ToolTip": GLib.Variant("(sa(iiay)ss)", ("", [], "Token Stats", "")),
        }.get(prop)

    def set_percent(self, pct):
        self.pixmap = render_icon(pct)
        self.conn.emit_signal(None, self.PATH, "org.kde.StatusNotifierItem", "NewIcon", None)


class App:
    def __init__(self):
        prov = Gtk.CssProvider(); prov.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), prov,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.info, self.usage, self.note, self.updated = None, {}, "", None
        self.popup = Popup(self)
        self.tray = Tray(self.toggle)
        self.refresh()
        GLib.timeout_add_seconds(INTERVAL_S, self.refresh)

    def toggle(self, x=0, y=10 ** 6):
        if self.popup.get_visible():
            self.popup.hide()
        else:
            self.popup.show_at(x, y)
        return False

    def refresh(self, *_):
        threading.Thread(target=self._work, daemon=True).start()
        return True

    def _work(self):
        note, info = "", self.info
        try:
            info = fetch_limits()
        except urllib.error.HTTPError as e:
            note = ("rate-limited, showing last values" if e.code == 429
                    else "login expired: run `claude`" if e.code == 401 else f"HTTP {e.code}")
        except Exception as e:
            note = f"offline ({type(e).__name__})"
        try:
            usage = collect_usage()
        except Exception:
            usage = self.usage
        GLib.idle_add(self._apply, info, usage, note)

    def _apply(self, info, usage, note):
        self.info, self.usage, self.note = info, usage, note
        self.updated = datetime.now()
        worst = max((r["pct"] for r in info["limits"]), default=0) if info else 0
        self.tray.set_percent(worst)
        if self.popup.get_visible():
            self.popup.render()


if __name__ == "__main__":
    App()
    Gtk.main()
