#!/usr/bin/env python3
"""Write one tiny HTML page per session to web/s/<id>.html.

Link previews (Slack, iMessage, WhatsApp, X) read Open Graph tags without
running JavaScript, so the Flutter app can't give each session its own
preview. These static pages carry the session's title, time, room, speakers
and description, then forward to the app (/?session=<id>).

Run after the schedule data changes:  python3 tool/build_share_pages.py
"""
import html
import json
import os
import re
import shutil
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "assets", "data")
OUT = os.path.join(ROOT, "web", "s")
BASE = "https://kubecon.codemagic.app"


def load(name):
    with open(os.path.join(DATA, name), encoding="utf-8") as f:
        return json.load(f)


def when(start, end):
    s, e = datetime.fromisoformat(start), datetime.fromisoformat(end)
    def t(d):
        return d.strftime("%I:%M %p").lstrip("0")
    return f"{s.strftime('%a, %b')} {s.day} · {t(s)} – {t(e)} MT"


def short(text, n):
    text = re.sub(r"\s+", " ", text or "").strip()
    return text if len(text) <= n else text[: n - 1].rsplit(" ", 1)[0] + "…"


def main():
    schedule = load("schedule.json")
    details = load("details.json").get("sessions", {})
    venue = load("venue.json")
    rooms = {r["id"]: r["name"] for r in venue.get("rooms", [])}
    rooms.update({o["id"]: o["name"] for o in venue.get("offsite", [])})
    speakers = schedule.get("speakers", {})

    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT)
    for s in schedule["sessions"]:
        sid = s["id"]
        if not re.fullmatch(r"[A-Za-z0-9_-]+", sid):
            continue
        room = rooms.get(s.get("roomId"), "")
        who = ", ".join(
            speakers[p]["name"] for p in s.get("speakers", []) if p in speakers
        )
        line = " · ".join(x for x in [when(s["start"], s["end"]), room, who] if x)
        desc = short(details.get(sid, {}).get("description", ""), 240)
        og_desc = f"{line}. {desc}" if desc else line
        url = f"{BASE}/s/{sid}.html"
        target = f"/?session={sid}"
        e = html.escape
        page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(s['title'])} · KubeCon Companion</title>
<meta name="description" content="{e(og_desc)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="KubeCon Companion by Codemagic">
<meta property="og:title" content="{e(s['title'])}">
<meta property="og:description" content="{e(og_desc)}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{BASE}/og-image.png">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{e(s['title'])}">
<meta name="twitter:description" content="{e(og_desc)}">
<link rel="canonical" href="{url}">
<meta http-equiv="refresh" content="0; url={target}">
<script>location.replace({json.dumps(target)});</script>
<style>body{{margin:0;background:#01091A;color:#D2DBEE;font-family:system-ui,-apple-system,sans-serif;padding:32px 16px}}a{{color:#fff}}</style>
</head>
<body>
<h1>{e(s['title'])}</h1>
<p>{e(line)}</p>
<p><a href="{target}">Open in KubeCon Companion</a></p>
</body>
</html>
"""
        with open(os.path.join(OUT, f"{sid}.html"), "w", encoding="utf-8") as f:
            f.write(page)
    print(f"wrote {len(os.listdir(OUT))} share pages to web/s/")


if __name__ == "__main__":
    main()
