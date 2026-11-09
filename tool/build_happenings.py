#!/usr/bin/env python3
"""Writes assets/data/happenings.json and assets/data/info.json.

Facts were collected on 2026-11-09 from the official KubeCon + CloudNativeCon NA 2026
pages on events.linuxfoundation.org (schedule, experiences, inclusion + accessibility,
health + safety, kids day, child care, co-located schedule, venue + travel).
roomId uses the same slug rule as tool/build_sessions.py (room_id()).
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "data")
TZ = "-07:00"
BASE = "https://events.linuxfoundation.org/kubecon-cloudnativecon-north-america"
SCHED = f"{BASE}/program/schedule/"
COLO = f"{BASE}/co-located-events/cncf-hosted-co-located-schedule/"
EXP = f"{BASE}/features-add-ons/experiences/"
INCL = f"{BASE}/attend/inclusion-accessibility/"
HS = f"{BASE}/attend/health-and-safety/"
KIDS = f"{BASE}/features-add-ons/kids-day/"
CHILD = f"{BASE}/attend/child-care/"
HUB = f"{BASE}/features-add-ons/community-hub/"
VENUE = f"{BASE}/attend/venue-travel/"
CNCF_BLOG = "https://www.cncf.io/blog/2026/09/11/kubecon-cloudnativecon-north-america-2026-your-week-in-salt-lake-city/"


def slug(s):
    s = s.lower().replace("&", " and ")
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")


def room_id(raw):
    """Same rule as build_sessions.room_id."""
    if raw is None:
        return None
    parts = [p.strip() for p in raw.split("|") if p.strip()]
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


def t(day, hhmm):
    return f"2026-11-{day:02d}T{hhmm}:00{TZ}"


items = []


def add(id, title, day, start, end, kind, location, description, source, url=None,
        room=True, end_day=None):
    items.append({
        "id": id,
        "title": title,
        "start": t(day, start),
        "end": t(end_day or day, end),
        "kind": kind,
        "location": location,
        "roomId": room_id(location) if room is True else room,
        "description": description,
        "url": url,
        "source": source,
    })


REG = "Salt Palace | 200 South Entrance (South)"
COAT = "Salt Palace | Level 2 | East Registration"
HALLS = "Salt Palace | Level 1 | Halls A-C, Halls 1-5"
HYATT_LT = "Hyatt Regency | Level 4 | Regency Ballroom B-D"
KEYNOTE = "Salt Palace | Level 1 | Hall DE"
COLO_FOOD = "Salt Palace | Level 1 | Lower Concourse Foyer + Hall 4 (via Lower Mezzanine)"
ID_NOTE = ("After picking up your badge, visit any Info Desk for an ID check and a 21+ "
           "wristband to redeem drink tickets at event receptions.")

# --- Registration + badge pick-up -------------------------------------------------
for d, s, e in [(8, "08:00", "17:00"), (9, "07:00", "17:00"), (10, "07:30", "18:00"),
                (11, "08:00", "17:30"), (12, "08:00", "16:00")]:
    add(f"registration-{d}", "Registration + Badge Pick-Up", d, s, e, "registration", REG,
        ID_NOTE if d <= 10 else "Registration and badge pick-up desk.", SCHED)

# --- Info desk ID checks (21+ wristbands) -------------------------------------------
for d, s, e in [(8, "08:00", "17:00"), (9, "07:00", "19:00"), (10, "07:30", "18:15")]:
    add(f"id-check-{d}", "Info Desk ID Check (21+ wristbands)", d, s, e, "other",
        "Any Info Desk", "Get an ID check and 21+ wristband to redeem drink tickets at "
        "receptions. ID check stations are also available during the reception.",
        SCHED, room=None)

# --- Coat + bag check ---------------------------------------------------------------
for d, s, e in [(8, "08:00", "18:00"), (9, "07:00", "19:00"), (10, "07:30", "20:00"),
                (11, "08:00", "18:00"), (12, "08:00", "16:30")]:
    add(f"coat-check-{d}", "Coat + Bag Check", d, s, e, "other", COAT,
        "Coat and bag check at East Registration, Level 2.", SCHED)

# --- Monday Nov 9: co-located events + Project Lightning Talks -----------------------
add("colo-am-break-9", "Co-located Events AM Break", 9, "10:15", "10:40", "break",
    "Salt Palace | Level 2 | Meeting Room Foyers",
    "Morning break for CNCF-hosted co-located events (staggered 10:15-10:40 AM by event). "
    "Menu: assorted danishes, overnight oats.", COLO, room=None)
add("colo-lunch-9", "Co-located Events Lunch", 9, "11:40", "13:30", "meal", COLO_FOOD,
    "Lunch for All-Access pass holders, staggered by co-located event between 11:40 AM "
    "and 1:30 PM. Boxed sandwiches (e.g. slow-roasted beef, BBQ chicken, mortadella).",
    COLO)
add("colo-pm-break-9", "Co-located Events PM Break", 9, "14:55", "15:20", "break",
    "Salt Palace | Level 2 | Meeting Room Foyers",
    "Afternoon break for CNCF-hosted co-located events (staggered 2:55-3:20 PM by event). "
    "Menu: hummus and crudite cups, brownies and blondies.", COLO, room=None)
add("lt-coffee-am-9", "Coffee Break (Project Lightning Talks)", 9, "10:48", "11:03", "break",
    HYATT_LT, "Coffee break during Project Lightning Talks.", SCHED)
add("lt-lunch-9", "Lunch on Own (Project Lightning Talks)", 9, "12:46", "13:30", "meal",
    HYATT_LT, "Lunch break in the Project Lightning Talks program; lunch is on your own.",
    SCHED)
add("lt-coffee-pm-9", "Coffee Break (Project Lightning Talks)", 9, "14:48", "15:03", "break",
    HYATT_LT, "Afternoon coffee break during Project Lightning Talks.", SCHED)
add("linkerd-premiere-9", "Documentary Premiere: The Linkerd Story", 9, "18:30", "19:30",
    "social", "Salt Palace | Level 1 | 151",
    "Premiere of the documentary on the people behind Linkerd, presented by CNCF with Buoyant.",
    EXP)

# --- Tuesday Nov 10 -----------------------------------------------------------------
add("keynotes-10", "Opening Keynotes", 10, "09:00", "10:45", "keynote", KEYNOTE,
    "Welcome + Opening Remarks followed by keynotes.", SCHED)
add("showcase-10", "Solutions Showcase Open", 10, "10:45", "17:15", "expo", HALLS,
    "Sponsor booths, Project Pavilion, Learning Lounge, Network Nook, activation zones and "
    "games. Reopens 6:00-7:30 PM for #KubeCrawl + #CloudNativeFest.", SCHED)
add("coffee-am-10", "Coffee Break", 10, "10:45", "11:30", "break", HALLS,
    "Morning coffee break in the Solutions Showcase.", SCHED)
add("women-gathering-10", "Women's Community Gathering", 10, "11:00", "12:00", "social",
    "Salt Palace | Level 1 | Grand Ballroom J",
    "A welcoming space for women, non-binary people and allies to connect and talk about "
    "allyship.", SCHED)
add("lunch-10", "Lunch", 10, "12:50", "14:50", "meal", HALLS,
    "Lunch in the Solutions Showcase.", SCHED)
add("pet-a-pup-10", "Pet-a-Pup", 10, "14:00", "16:00", "other",
    "Salt Palace | Level 1 | North Grand Ballroom Foyer",
    "Visit friendly therapy puppies to reduce stress.", EXP)
add("coffee-pm-10", "Coffee Break", 10, "16:10", "16:40", "break", HALLS,
    "Afternoon coffee break in the Solutions Showcase.", SCHED)
add("kubecrawl-10", "#KubeCrawl + #CloudNativeFest (Booth Crawl + Welcome Reception)", 10,
    "18:00", "19:30", "party", HALLS,
    "All-attendee welcome reception and booth crawl in the Solutions Showcase: local food "
    "favorites, beverages, games and activities. Visit any Info Desk for an ID check and 21+ "
    "wristband to redeem drink tickets. KubeCrawl Trivia runs 6:30-6:45 PM at the Learning "
    "Lounge (Hall B).", EXP)

# --- Wednesday Nov 11 ---------------------------------------------------------------
add("fun-run-11", "Group Fun Run/Walk", 11, "06:30", "08:00", "social",
    "Hyatt Regency Lobby",
    "Casual all-levels conference walk/run. Meet in the Hyatt Regency lobby at 6:30 for a "
    "6:45 departure.", SCHED)
add("puppy-yoga-11", "Puppy Yoga", 11, "07:00", "08:00", "social",
    "Hyatt Regency | Level 3 | Park City",
    "Yoga with puppies. 40-person capacity, first come, first served.", SCHED)
add("keynotes-11", "Keynotes", 11, "09:00", "10:48", "keynote", KEYNOTE,
    "Morning keynotes.", SCHED)
add("showcase-11", "Solutions Showcase Open", 11, "10:30", "17:00", "expo", HALLS,
    "Sponsor booths, Project Pavilion, Learning Lounge, Network Nook and activation zones.",
    SCHED)
add("coffee-am-11", "Coffee Break", 11, "10:30", "11:00", "break", HALLS,
    "Morning coffee break in the Solutions Showcase.", SCHED)
add("lunch-11", "Lunch", 11, "12:20", "14:20", "meal", HALLS,
    "Lunch in the Solutions Showcase.", SCHED)
add("coffee-pm-11", "Coffee Break", 11, "15:40", "16:10", "break", HALLS,
    "Afternoon coffee break in the Solutions Showcase.", SCHED)
add("graduation-celebration-11", "Celebration of Newly Graduated Projects + Project Birthdays",
    11, "15:40", "16:10", "social",
    "Salt Palace | Level 1 | Solutions Showcase | Hall 5 | Cosmic Canyon Zone | Project Pavilion",
    "Celebrate newly graduated projects (OpenTelemetry, Buildpacks, Karmada, Kubeflow) and "
    "10-year birthdays of Dapr and Fluentd. Grab a treat at the project kiosks.", SCHED)

# --- Thursday Nov 12 ----------------------------------------------------------------
add("keynotes-12", "Keynotes", 12, "09:00", "10:30", "keynote", KEYNOTE,
    "Morning keynotes.", SCHED)
add("showcase-12", "Solutions Showcase Open (last day)", 12, "10:30", "14:00", "expo", HALLS,
    "Final Solutions Showcase hours. Closes at 2:00 PM.", SCHED)
add("coffee-am-12", "Coffee Break", 12, "10:30", "11:00", "break", HALLS,
    "Morning coffee break in the Solutions Showcase.", SCHED)
add("security-slam-12", "Security Slam Awards Ceremony", 12, "10:45", "11:10", "social",
    "Salt Palace | Level 1 | Solutions Showcase | Hall 5 | Cosmic Canyon Zone | Project Pavilion",
    "Awards ceremony on the Project Pavilion Stage.", SCHED, room=room_id(
        "Salt Palace | Level 1 | Solutions Showcase | Hall 5 | Cosmic Canyon Zone | Project Pavilion"))
add("lunch-12", "Lunch", 12, "12:20", "13:50", "meal", HALLS,
    "Lunch in the Solutions Showcase.", SCHED)

# --- Learning Lounge hours ----------------------------------------------------------
LL = "Salt Palace | Level 1 | Solutions Showcase | Hall B | Starlight Summit Zone"
for d, s, e in [(10, "10:30", "19:30"), (11, "10:15", "17:00"), (12, "10:15", "14:00")]:
    add(f"learning-lounge-{d}", "Learning Lounge", d, s, e, "expo", LL,
        "CNCF learning and certification lounge with 10-Minute Tip Talks, swag for certified "
        "folks and course discounts.", EXP)

# --- Kids Day + child care ----------------------------------------------------------
add("kids-day-8", "Kids Day", 8, "13:00", "16:30", "other", "Salt Palace Convention Center",
    "Free afternoon of tech workshops for kids ages 8-14 (pre-registration required; "
    "registration is closed). Took place Sunday Nov 8, before the main conference.",
    KIDS, url=KIDS, room=None)
for d, s, e in [(9, "08:30", "18:30"), (10, "08:30", "19:30"), (11, "08:30", "18:00"),
                (12, "08:30", "16:00")]:
    add(f"child-care-{d}", "Onsite Child Care (RSVP only)", d, s, e, "other", "Onsite",
        "Complimentary child care for children up to 12 who RSVP'd by Oct 5. Parents provide "
        "peanut-free food and snacks. Location shared with registered families.",
        CHILD, url=CHILD, room=None)

# --- Whole-day facilities (Nov 9-12) -------------------------------------------------
FAC = [
    ("quiet-room", "All-Attendee Quiet Room", "Salt Palace | Level 2 | 260A",
     "Quiet space for when you need a break from interaction. Please refrain from "
     "conversation, interaction or work.", INCL),
    ("quiet-room-wnb", "Women + Non-Binary Quiet Room", "Salt Palace | Level 2 | 260B",
     "Quiet room dedicated to women and non-binary attendees.", INCL),
    ("prayer-room", "Prayer Room", "Hyatt Regency | Level 5 | Zion",
     "All-attendee prayer room.", INCL),
    ("nursing-room", "Nursing Room", "Onsite (ask Registration or an Info Desk)",
     "Private nursing/lactation room available all event days. Ask registration or "
     "information desk staff for the location.", INCL),
    ("first-aid", "First Aid Stations", "Salt Palace | Level 1 | by Room 150 or outside Halls 2 + 3",
     "First aid / medical assistance stations. For emergencies dial 911.", INCL),
    ("safety-desk", "Onsite Safety + Lost & Found Desk",
     "Salt Palace | Level 1 | Lower Concourse | between Halls D and C",
     "Report safety concerns, request a Safety Chaperone, or check lost and found.", HS),
]
for fid, title, loc, desc, src in FAC:
    room = room_id(loc) if loc.startswith(("Salt Palace", "Hyatt")) else None
    if fid in ("first-aid", "safety-desk"):
        room = None  # multiple / corridor locations, not a single room
    for d in (9, 10, 11, 12):
        add(f"{fid}-{d}", title, d, "07:00", "20:00", "other", loc, desc, src, room=room)

items.sort(key=lambda x: (x["start"], x["end"], x["id"]))
ids = [x["id"] for x in items]
assert len(ids) == len(set(ids)), "duplicate ids"

with open(os.path.join(OUT, "happenings.json"), "w", encoding="utf-8") as f:
    json.dump({"items": items}, f, ensure_ascii=False, indent=1)

info = {
    "wifi": None,
    "codeOfConduct": f"{BASE}/attend/code-of-conduct/",
    "venueAddress": "Salt Palace Convention Center, 90 South West Temple, Salt Lake City, UT 84101",
    "emergency": ("Emergency: dial 911. First aid stations: Salt Palace Level 1 by Room 150 and "
                  "outside Halls 2 + 3. Onsite Safety + Lost & Found Desk: Level 1, Lower "
                  "Concourse, between Halls D and C. Nearest 24/7 hospital: Holy Cross Hospital - "
                  "Salt Lake, 1050 East South Temple, 801-350-4111. Urgent care: Salt Lake "
                  "InstaCare, 389 South 900 East, 385-282-2400 (8 AM-8 PM). SLC Police "
                  "non-emergency: 801-799-3000. Code of conduct reports: eventconduct@cncf.io."),
    "links": [
        {"title": "Official schedule", "url": SCHED},
        {"title": "Venue + Travel", "url": VENUE},
        {"title": "Venue map", "url": "https://events.linuxfoundation.org/kcna26-venue-map"},
        {"title": "Solutions Showcase map", "url": "https://events.linuxfoundation.org/kcna26-expo-map"},
        {"title": "Experiences", "url": EXP},
        {"title": "Health + Safety", "url": HS},
        {"title": "Inclusion + Accessibility", "url": INCL},
        {"title": "FAQ", "url": f"{BASE}/attend/faq/"},
        {"title": "Code of Conduct", "url": f"{BASE}/attend/code-of-conduct/"},
        {"title": "Co-located events schedule", "url": COLO},
        {"title": "Codemagic", "url": "https://codemagic.io/"},
    ],
    "sources": [SCHED, VENUE, HS, INCL, f"{BASE}/attend/faq/", EXP],
    "notes": "No public Wi-Fi details were published on the event site as of 2026-11-09.",
}
with open(os.path.join(OUT, "info.json"), "w", encoding="utf-8") as f:
    json.dump(info, f, ensure_ascii=False, indent=1)

print(f"wrote {len(items)} happenings")
print("roomIds:", sorted({x['roomId'] for x in items if x['roomId']}))
