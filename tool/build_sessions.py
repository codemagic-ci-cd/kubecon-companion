#!/usr/bin/env python3
"""Convert the official KubeCon + CloudNativeCon NA 2026 schedule (Sessionize API
backing events.linuxfoundation.org/.../program/schedule/) into two minified files:

  assets/data/schedule.json  loaded at startup: everything the schedule list, search,
                             filters, Now/Saved tabs and reminders need, plus a speaker
                             map id -> {name, title, company, links: x/github/bluesky}
                             (handles are used by search).
  assets/data/details.json   loaded after the first frame: session descriptions and
                             prerequisites, speaker bio/photo/linkedin/website, each
                             speaker once (deduped by Sessionize speaker id).

Usage:  python3 -I tool/build_sessions.py [path/to/all.json]
If no path is given it downloads https://sessionize.com/api/v2/svi82w6c/view/All.
"""
import datetime as dt
import json
import os
import re
import sys
import urllib.request

API = "https://sessionize.com/api/v2/svi82w6c/view/All"
SCHED_URL = "https://events.linuxfoundation.org/kubecon-cloudnativecon-north-america/program/schedule/?id={}"
TZ = "-07:00"  # America/Denver, MST (DST ended Nov 1 2026)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "data")

Q_COMPANY, Q_TITLE, Q_COMPANY_OVERRIDE, Q_NAME_DISPLAY, Q_MAP, Q_WEBSITE = (
    128829, 128830, 138119, 142725, 137119, 137006)

OFFSITE_ROOM = 88756

# Off-site sponsor co-located events: Sessionize puts them all in "Off-Site Location".
# Locations from each session's description ("Location: ...") and its Location Map link
# (short links resolved with curl). lat/lng marked approx=True are estimated, not from a link.
OFFSITE = {
    "pierpont-place": dict(name="Pierpont Place", address="W Pierpont Ave, Salt Lake City, UT 84101",
                           lat=40.7635741, lng=-111.8960208, approx=False),
    "marriott-city-center": dict(name="Salt Lake City Marriott City Center", address="220 S State St, Salt Lake City, UT 84111",
                                 lat=40.764351, lng=-111.8911, approx=False),
    "hilton-city-center": dict(name="Hilton Salt Lake City Center", address="255 South West Temple, Salt Lake City, UT 84101",
                               lat=40.7618, lng=-111.8945, approx=True),
    "kimpton-monaco": dict(name="Kimpton Hotel Monaco Salt Lake City (Floor 2, Paris Ballroom)", address="15 W 200 S, Salt Lake City, UT 84101",
                           lat=40.7646976, lng=-111.8948309, approx=False),
    "radisson-downtown": dict(name="Radisson Hotel Salt Lake City Downtown", address="215 W South Temple, Salt Lake City, UT 84101",
                              lat=40.768988, lng=-111.8978173, approx=False),
    "utah-moca": dict(name="Utah Museum of Contemporary Art", address="20 S West Temple, Salt Lake City, UT 84101",
                      lat=40.7683461, lng=-111.8947354, approx=False),
    "clark-planetarium": dict(name="Clark Planetarium", address="110 South 400 West, Salt Lake City, UT 84101",
                              lat=40.7667, lng=-111.9029, approx=True),
    "gallivan-center": dict(name="Gallivan Center", address="50 E 200 S, Salt Lake City, UT 84111",
                            lat=40.7655, lng=-111.8892, approx=True),
    "le-meridien": dict(name="Le Meridien Salt Lake City Downtown", address="131 S 300 W, Salt Lake City, UT 84101",
                        lat=40.7662291, lng=-111.899423, approx=False),
    "marriott-downtown-city-creek": dict(name="Salt Lake Marriott Downtown at City Creek", address="75 S W Temple St, Salt Lake City, UT 84101",
                                         lat=40.7684, lng=-111.8916, approx=True),
    "ac-hotel-downtown": dict(name="AC Hotel Salt Lake City Downtown", address="225 West 200 South, Salt Lake City, UT 84101",
                              lat=40.7647558, lng=-111.8973346, approx=False),
    "edison-house": dict(name="Edison House", address="Edison St, Salt Lake City, UT 84111",
                         lat=40.7617551, lng=-111.8989095, approx=False),
}
OFFSITE_BY_SESSION = {
    "1344383": "pierpont-place", "1341814": "marriott-city-center", "1309278": "hilton-city-center",
    "1356273": "kimpton-monaco", "1345255": "radisson-downtown", "1339971": "utah-moca",
    "1336214": "clark-planetarium", "1328916": "gallivan-center", "1367685": "le-meridien",
    "1356091": "kimpton-monaco", "1309279": "marriott-downtown-city-creek", "1328984": "le-meridien",
    "1363748": "ac-hotel-downtown", "1340051": "edison-house",
}

DISCLAIMER_RE = re.compile(r"_?In order to facilitate networking and business relationships at the event.*$", re.S)

PREREQ_RE = re.compile(
    r"prerequisites?:|pre-requisites?:|what to bring|requirements?:|bring (a|your)( own)?( linux)? laptop|"
    r"laptop[^.]{0,60}required|personal laptop|without a laptop|laptop per|laptop with|"
    r"no prior [^.]{0,40}(required|needed)|experience (is )?(needed|required)|kubectl basics|"
    r"familiarity with|basic understanding of|should be familiar|registration (is )?(not )?required|"
    r"github account", re.I)


def slug(s):
    s = s.lower().replace("&", " and ")
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")


def room_id(raw):
    parts = [p.strip() for p in raw.split("|") if p.strip()]
    if raw.strip() == "Room TBD":
        return "tbd"
    if parts[0] == "Hyatt Regency Lobby":
        return "hyatt-lobby"
    prefix = ""
    if parts[0] == "Hyatt Regency":
        prefix = "hyatt-"
        parts = parts[1:]
    elif parts[0] == "Salt Palace":
        parts = parts[1:]
    out = []
    for p in parts:
        m = re.fullmatch(r"Level (\d+)", p)
        out.append(f"l{m.group(1)}" if m else slug(p))
    return prefix + "-".join(out)


def iso(local):
    return dt.datetime.fromisoformat(local).isoformat() + TZ


def clean_desc(t):
    t = (t or "").replace("\r\n", "\n").replace("\r", "\n")
    t = DISCLAIMER_RE.sub("", t)
    t = re.sub(r"\n{3,}", "\n\n", t)
    return t.strip()


def prerequisites(desc, cats):
    found = []
    # explicit heading sections: "Prerequisites:" followed by bullet lines
    for m in re.finditer(r"(?im)^\s*(?:\*\*)?(prerequisites?|what to bring|requirements)(?:\*\*)?:?\s*(.*)$", desc):
        rest = desc[m.end():].split("\n\n")[0]
        if m.group(2).strip():
            found.append(m.group(2).strip())
        for line in rest.split("\n"):
            line = re.sub(r"^\s*[-*•]\s*", "", line).strip()
            if line:
                found.append(line)
    for para in desc.split("\n"):
        for sent in re.split(r"(?<=[.!?])\s+", para):
            sent = sent.strip().strip("*_ ")
            if 8 < len(sent) < 300 and PREREQ_RE.search(sent) and not re.search(r"https?://", sent):
                # skip prose that merely mentions requirements in the talk content
                if re.search(r"laptop|prior|experience|kubectl basics|familiar|registration|github account|bring|prerequisite", sent, re.I):
                    if re.match(r"^Important:\s*", sent):
                        sent = sent.split(":", 1)[1].strip()
                    found.append(sent)
    if "Separate Registration Required" in cats:
        found.append("Separate registration required")
    out, seen = [], set()
    for f in found:
        k = f.lower().rstrip(".")
        if k not in seen:
            seen.add(k)
            out.append(f)
    return out


def classify(title, primary, cats):
    t = title.lower()
    if primary == "Keynote Sessions":
        return "keynote"
    if primary == "Breaks":
        return "meal" if re.search(r"lunch|breakfast|dinner", t) else "break"
    if primary == "Registration":
        return "registration"
    if "kubecrawl" in t or "fest" in t or "reception" in t or "party" in t:
        return "social"
    if primary in ("Sponsor-hosted Co-located Events", "CNCF-hosted Co-located Events"):
        return "colocated"
    if primary == "Solutions Showcase":
        return "expo"
    if primary == "\U0001F4DA Tutorials":
        return "tutorial"
    if primary in ("⚡ Lightning Talks", "Project Lightning Talks"):
        return "lightning"
    if primary == "\U0001F6A8 Contribfest":
        return "workshop"
    if "panel" in t:
        return "panel"
    if primary == "Experiences":
        return "other" if "BoF" in cats else "social"
    if primary in ("Project Pavilion Tours", "\U0001FAA7 Poster Sessions", "Project Opportunities"):
        return "other"
    if re.search(r"workshop|hands-on", t):
        return "workshop"
    return "talk"


HIGHLIGHT_RE = re.compile(r"kubecrawl|cloudnativefest|reception|party|happy hour|fun run|puppy|pet-a-pup|"
                          r"trivia|premiere|escape room|welcome|opening", re.I)



import re as _re

_NULLISH = {"", "none", "n/a", "na", "-", "null", "self", "independent"}


def _clean(v):
    return None if v is None or v.strip().lower() in _NULLISH else v.strip()


def _handle(url, hosts):
    m = _re.match(r"https?://(?:www\.|mobile\.)?(" + "|".join(hosts) + r")/@?([A-Za-z0-9_.-]+)/?(?:[?#].*)?$", url.strip())
    if not m or m.group(2).lower() in {"intent", "share", "home", "orgs", "in", "profile"}:
        return None
    return m.group(2)


def speaker_links(sp):
    """Pull X/GitHub/LinkedIn/Bluesky/website from Sessionize links, matching by URL not label."""
    out = {}
    for link in sp.get("links", []):
        url = (link.get("url") or "").strip()
        if not url.startswith("http"):
            url = "https://" + url
        low = url.lower()
        if ("twitter.com/" in low or "//x.com/" in low or ".x.com/" in low) and "x" not in out:
            h = _handle(url, ["twitter\\.com", "x\\.com"])
            if h:
                out["x"] = h
        elif "github.com/" in low and "github" not in out:
            h = _handle(url, ["github\\.com"])
            if h:
                out["github"] = h
        elif "linkedin.com/" in low and "linkedin" not in out:
            out["linkedin"] = url
        elif "bsky.app/" in low and "bluesky" not in out:
            out["bluesky"] = url
        elif link.get("linkType") in ("Blog", "Company_Website") and "website" not in out:
            out["website"] = url
    return out

SEARCH_LINKS = ("x", "github", "bluesky")


def compact(d):
    """Drop empty values (None, "", [], {}, False) to keep the JSON small."""
    return {k: v for k, v in d.items() if v not in (None, "", [], {}, False)}


def base36(n):
    digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    out = ""
    while True:
        n, r = divmod(n, 36)
        out = digits[r] + out
        if n == 0:
            return out


def write_min(name, doc):
    with open(os.path.join(OUT_DIR, name), "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))


def main():
    if len(sys.argv) > 1:
        data = json.load(open(sys.argv[1], encoding="utf-8"))
        src_note = API
    else:
        with urllib.request.urlopen(API, timeout=60) as r:
            data = json.loads(r.read().decode("utf-8"))
        src_note = API

    cats = {i["id"]: i["name"] for c in data["categories"] for i in c["items"]}
    main_items = [i["id"] for c in data["categories"] if c["title"] == "All Sessions" for i in c["items"]]
    level_items = {i["id"]: i["name"] for c in data["categories"] if c["title"] == "Audience Level" for i in c["items"]}
    rooms = {r["id"]: r["name"].strip() for r in data["rooms"]}

    speakers, speaker_details = {}, {}
    for sp in data["speakers"]:
        qa = {q["questionId"]: (q["answerValue"] or "").strip() for q in sp.get("questionAnswers", [])}
        company = qa.get(Q_COMPANY_OVERRIDE) or qa.get(Q_COMPANY) or None
        title = qa.get(Q_TITLE) or None
        if not company and not title and sp.get("tagLine"):
            tl = sp["tagLine"]
            if ", " in tl:
                company, title = [x.strip() for x in tl.split(", ", 1)]
            else:
                title = tl
        links = speaker_links(sp)
        speakers[sp["id"]] = {
            "name": sp.get("fullName") or f'{sp.get("firstName","")} {sp.get("lastName","")}'.strip(),
            "title": _clean(title),
            "company": _clean(company),
            # Handles stay in the schedule file: search matches them.
            "links": {k: v for k, v in links.items() if k in SEARCH_LINKS},
        }
        speaker_details[sp["id"]] = {
            "bio": (sp.get("bio") or "").replace("\r\n", "\n").strip() or None,
            "photo": sp.get("profilePicture") or None,
            "links": {k: v for k, v in links.items() if k not in SEARCH_LINKS},
        }

    room_map = {}
    out = []
    session_details = {}
    used_speakers = set()
    for s in data["sessions"]:
        if s.get("status") not in (None, "Accepted"):
            continue
        sess_cats = [cats.get(x) for x in s["categoryItems"] if x in cats]
        primary = next((cats[x] for x in s["categoryItems"] if x in main_items), None)
        qa = {q["questionId"]: (q["answerValue"] or "").strip() for q in s.get("questionAnswers", [])}
        raw_room = rooms.get(s["roomId"], "Room TBD")
        if s["roomId"] == OFFSITE_ROOM:
            key = OFFSITE_BY_SESSION.get(str(s["id"]))
            rid = f"offsite-{key}" if key else "offsite-tbd"
            info = dict(OFFSITE.get(key, {}), raw=raw_room, kind="offsite", mapUrl=qa.get(Q_MAP))
        else:
            rid = room_id(raw_room)
            info = dict(raw=raw_room, kind="onsite")
        entry = room_map.setdefault(rid, dict(id=rid, **info, sessionCount=0))
        entry["sessionCount"] += 1

        desc = clean_desc(s.get("description"))
        title = re.sub(r"\s+", " ", s["title"]).strip()
        stype = classify(title, primary, sess_cats)
        spk = [x for x in s["speakers"] if x in speakers]
        used_speakers.update(spk)
        if not spk and qa.get(Q_NAME_DISPLAY):
            spk = [{"name": qa[Q_NAME_DISPLAY]}]  # no Sessionize profile: inline
        lvl = next((level_items[x] for x in s["categoryItems"] if x in level_items), None)
        level = {"Beginner": "beginner", "Advanced": "advanced", "Any Level": "any",
                 "Intermediate": "intermediate"}.get(lvl)
        track = re.sub(r"^[^\w]+", "", primary).strip() if primary else None
        highlight = stype in ("keynote", "break", "meal", "social") or bool(HIGHLIGHT_RE.search(title)) \
            or title == "Solutions Showcase"
        prereq = prerequisites(desc, sess_cats)
        sid = str(s["id"])
        out.append(compact({
            "id": sid,
            "title": title,
            "start": iso(s["startsAt"]),
            "end": iso(s["endsAt"]),
            "type": stype,
            "track": track,
            "roomId": rid,
            "level": level,
            "speakers": spk,
            "url": SCHED_URL.format(s["id"]),
            "highlight": highlight,
            "hasPrerequisites": bool(prereq),
        }))
        if desc or prereq:
            session_details[sid] = compact({"description": desc, "prerequisites": prereq})

    out.sort(key=lambda x: (x["start"], x["end"], x["title"]))
    now = dt.datetime.now(dt.timezone(dt.timedelta(hours=-7))).replace(microsecond=0).isoformat()
    # Sessionize speaker ids are 36-char UUIDs that gzip badly (~35 KB of the
    # schedule file); the app only needs them to join the two files, so use short
    # sequential base-36 ids instead. Not stable across rebuilds; never persist them.
    used = sorted(used_speakers)
    short = {k: base36(i) for i, k in enumerate(used)}
    for sess in out:
        if "speakers" in sess:
            sess["speakers"] = [short.get(x, x) if isinstance(x, str) else x for x in sess["speakers"]]
    schedule = {"source": src_note, "fetchedAt": now, "isSample": False,
                "speakers": {short[k]: compact(speakers[k]) for k in used},
                "sessions": out}
    details = {"source": src_note, "fetchedAt": now,
               "sessions": session_details,
               "speakers": {short[k]: d for k in used if (d := compact(speaker_details[k]))}}
    os.makedirs(OUT_DIR, exist_ok=True)
    write_min("schedule.json", schedule)
    write_min("details.json", details)
    rr = sorted(room_map.values(), key=lambda r: (r["kind"], r["id"]))
    with open(os.path.join(OUT_DIR, "rooms_raw.json"), "w", encoding="utf-8") as f:
        json.dump({"source": src_note, "rooms": rr}, f, ensure_ascii=False, indent=1)
    print(f"wrote {len(out)} sessions, {len(used)} speakers, {len(rr)} rooms")


if __name__ == "__main__":
    main()
