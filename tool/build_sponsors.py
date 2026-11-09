#!/usr/bin/env python3
"""Writes assets/data/sponsors.json (sponsor + booth directory).

Sources (official, events.linuxfoundation.org):
  - Sponsor directory page: name, level, booth, solution categories, description, website.
    Its header also carries the sponsor logo wall by tier, incl. Media Partners
    (which are not in the directory cards and have no booth listed).
  - Expo hall floor plan PDF ("View Full Floor Plan" on the directory page):
    booth number positions, used to place each booth in a hall/zone and map it to
    an official_map.json room id.

Raw files are cached in tool/sched_raw/sponsors/. Pass --refresh to re-download.
Needs pypdf (pip install pypdf) to read booth positions from the PDF.
"""
import datetime
import gzip
import html
import json
import os
import re
import sys
import urllib.parse
import urllib.request

import pypdf

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "sched_raw", "sponsors")
ASSETS = os.path.join(HERE, "..", "assets", "data")
OUT = os.path.join(ASSETS, "sponsors.json")
BASE = "https://events.linuxfoundation.org/kubecon-cloudnativecon-north-america"
DIRECTORY = f"{BASE}/sponsor/sponsor-directory/"
EXPO_MAP = "https://events.linuxfoundation.org/kcna26-expo-map"
UA = "Mozilla/5.0 (Macintosh) AppleWebKit/537.36 Chrome/130 Safari/537.36"

TIERS = ["Diamond", "Platinum", "Gold", "Silver", "Start-Up", "End User", "Media Partner"]
TIER_ALIASES = {"start-up": "Start-Up", "startup": "Start-Up", "media partners": "Media Partner",
                "media partner": "Media Partner", "end user": "End User"}

# Zones of the Solutions Showcase as drawn on the floor plan PDF, in PDF points
# (page 908 x 691, origin bottom-left). Each zone -> (hall group, official_map room id).
ZONES = {
    "Cosmic Canyon": ("Halls 1-5", "l1-solutions-showcase-halls-5-cosmic-canyon-zone"),  # Halls 4-5
    "Amber Hive": ("Halls 1-5", "l1-lower-concourse-foyer-hall-4-via-lower-mezzanine"),  # Halls 3-4
    "Honeycomb Hub": ("Halls 1-5", "l1-halls-2-3"),  # Halls 2-3
    "Alpine Overlook": ("Halls 1-5", "l1-halls-a-c-halls-1-5"),  # Hall 1, no own room on the map
    "Starlight Summit": ("Halls A-C", "l1-solutions-showcase-hall-b-starlight-summit-zone"),  # Halls B-C
    "Astral Peak": ("Halls A-C", "l1-halls-a-c-halls-1-5"),  # Hall A
}


def fetch(url, name, refresh):
    path = os.path.join(RAW, name)
    if refresh or not os.path.exists(path):
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read()
        os.makedirs(RAW, exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
    return path


def slug(s):
    s = s.lower().replace("&", " and ").replace("+", " plus ")
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


def norm(s):
    s = re.sub(r"\s+logo$", "", s.strip(), flags=re.I)
    return re.sub(r"[^a-z0-9]", "", s.lower())


def domain(u):
    if not u:
        return None
    host = urllib.parse.urlsplit(u).netloc.lower().split(":")[0]
    parts = host.split(".")
    if parts[0] in ("www", "info", "go", "get", "try", "events", "lp"):
        parts = parts[1:]
    return ".".join(parts[-2:]) if len(parts) >= 2 else host


def text(s):
    s = re.sub(r"<[^>]+>", " ", s)
    return re.sub(r"\s+", " ", html.unescape(s)).strip()


def tier_name(s):
    s = re.sub(r"^\d+\s*", "", s.strip())
    return TIER_ALIASES.get(s.lower(), s)


def clean_url(u):
    if not u:
        return None
    u = html.unescape(u).strip()
    p = urllib.parse.urlsplit(u)
    q = [(k, v) for k, v in urllib.parse.parse_qsl(p.query) if not k.lower().startswith(("utm_", "hs"))]
    return urllib.parse.urlunsplit((p.scheme, p.netloc, p.path, urllib.parse.urlencode(q), ""))


def shorten(s, n=280):
    if not s or len(s) <= n:
        return s or None
    cut = s[: n - 1]
    cut = cut[: cut.rfind(" ")] if " " in cut[n // 2:] else cut
    return cut.rstrip(" ,;:.-") + "…"


def booth_zone(x, y):
    if y > 485:
        return "Cosmic Canyon"
    if y > 381:
        return "Amber Hive"
    if y > 266:
        return "Honeycomb Hub"
    if x > 334:
        return "Alpine Overlook"
    # Diagonal between Starlight Summit (upper left) and Astral Peak (lower right)
    # runs through about (213, 139) and (145, 78).
    x0, y0, x1, y1 = 213, 139, 145, 78
    side = (x1 - x0) * (y - y0) - (y1 - y0) * (x - x0)
    return "Starlight Summit" if side < 0 else "Astral Peak"


def pdf_booths(pdf_path):
    """booth number -> zone, from text positions on the floor plan page."""
    page = pypdf.PdfReader(pdf_path).pages[0]
    found = {}

    def visit(t, cm, tm, *_):
        t = t.strip()
        if not re.fullmatch(r"\d{3}", t):
            return
        e, f = tm[4], tm[5]
        x = e * cm[0] + f * cm[2] + cm[4]
        y = e * cm[1] + f * cm[3] + cm[5]
        found.setdefault(t, booth_zone(x, y))

    page.extract_text(visitor_text=visit)
    return found


def parse_directory(h):
    out = []
    for art in re.findall(r"<article class=\"sponsor-directory__card\"(.*?)</article>", h, re.S):
        name = html.unescape(re.search(r'data-name="([^"]*)"', art).group(1)).strip()
        level = tier_name(re.search(r'data-level="([^"]*)"', art).group(1))
        cats = json.loads(html.unescape(re.search(r'data-categories="([^"]*)"', art).group(1)) or "[]")
        booth = re.search(r"<strong>Booth:</strong>\s*([^<]*)<", art)
        desc = re.search(r'sponsor-directory-modal__description">(.*?)</div>', art, re.S)
        web = re.search(r'class="sponsor-directory-modal__website" href="([^"]*)"', art)
        out.append({
            "name": name,
            "tier": level,
            "booth": booth.group(1).strip() if booth and booth.group(1).strip() else None,
            "website": clean_url(web.group(1)) if web else None,
            "description": shorten(text(desc.group(1))) if desc else None,
            "tags": sorted({c.strip() for c in cats if c.strip() and "vultr" not in c.lower()}),
        })
    return out


def parse_logo_wall(h):
    """Tier headings + logo links at the top of the directory page."""
    out = []
    for block in h.split('<div class="wp-block-cgb-sponsors-block">')[1:]:
        block = block.split("</div></div></div>")[0]
        m = re.search(r'<h3 class="sponsors-logos--header">(.*?)</h3>', block, re.S)
        if not m:
            continue
        tier = tier_name(text(m.group(1)))
        for href, title in re.findall(r'<a href="([^"]*)" title="Go to ([^"]*)"', block):
            out.append({"name": html.unescape(title).strip(), "tier": tier, "website": clean_url(href)})
    return out


def main():
    refresh = "--refresh" in sys.argv
    dir_html = open(fetch(DIRECTORY, "directory.html", refresh), encoding="utf-8").read()
    pdf = fetch(EXPO_MAP, "KCNA26-ExpoHallMap_Digital.pdf", refresh)
    zones = pdf_booths(pdf)

    by_key = {}
    for s in parse_directory(dir_html):
        by_key.setdefault(norm(s["name"]), s)
    wall = parse_logo_wall(dir_html)
    by_domain = {}
    for k, s in by_key.items():
        by_domain.setdefault((domain(s["website"]), s["tier"]), k)
    for w in wall:
        k = norm(w["name"])
        if k not in by_key:
            k = by_domain.get((domain(w["website"]), w["tier"]), k)
        if k not in by_key:
            k = next((o for o, s in by_key.items() if s["tier"] == w["tier"] and len(k) > 3
                      and (o.startswith(k) or k.startswith(o))), k)
        if k in by_key:
            by_key[k]["website"] = by_key[k]["website"] or w["website"]
            continue
        by_key[k] = {"name": w["name"], "tier": w["tier"], "booth": None, "website": w["website"],
                     "description": None, "tags": []}

    sponsors, unplaced = [], []
    for s in by_key.values():
        hall = room = None
        if s["booth"]:
            nums = re.findall(r"\d+", s["booth"])
            zs = {zones.get(n) for n in nums} - {None}
            if len(zs) == 1:
                hall, room = ZONES[zs.pop()]
            else:
                unplaced.append((s["name"], s["booth"]))
        sponsors.append({"id": slug(s["name"]), "name": s["name"], "tier": s["tier"], "booth": s["booth"],
                         "hall": hall, "roomId": room, "website": s["website"],
                         "description": s["description"], "tags": s["tags"]})

    rank = {t: i for i, t in enumerate(TIERS)}
    sponsors.sort(key=lambda s: (rank.get(s["tier"], len(TIERS)), s["name"].lower()))
    seen = set()
    for s in sponsors:
        base, i = s["id"], 2
        while s["id"] in seen:
            s["id"] = f"{base}-{i}"
            i += 1
        seen.add(s["id"])

    room_ids = set(json.load(open(os.path.join(ASSETS, "official_map.json")))["rooms"])
    assert all(s["roomId"] in room_ids for s in sponsors if s["roomId"]), "unknown roomId"

    doc = {
        "source": [DIRECTORY, EXPO_MAP],
        "fetchedAt": datetime.datetime.fromtimestamp(
            os.path.getmtime(os.path.join(RAW, "directory.html")), datetime.timezone.utc
        ).replace(microsecond=0).isoformat(),
        "sponsors": sponsors,
    }
    data = json.dumps(doc, ensure_ascii=False, separators=(",", ":")).encode()
    with open(OUT, "wb") as f:
        f.write(data)

    counts = {}
    for s in sponsors:
        counts[s["tier"]] = counts.get(s["tier"], 0) + 1
    print("sponsors", len(sponsors), counts)
    print("with booth", sum(1 for s in sponsors if s["booth"]),
          "placed in hall", sum(1 for s in sponsors if s["hall"]))
    print("unplaced booths", unplaced)
    print("size", len(data), "gzip", len(gzip.compress(data, 9)))


if __name__ == "__main__":
    main()
