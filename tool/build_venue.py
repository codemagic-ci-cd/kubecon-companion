#!/usr/bin/env python3
"""Build assets/data/venue.json for the Salt Palace Convention Center (KubeCon NA 2026).

Layout is a schematic reconstruction from:
  * the official KubeCon NA 2026 venue map (events.linuxfoundation.org/kcna26-venue-map, PDF text positions)
  * Salt Palace floor plan PDFs (visitsaltlake.com / simpleview "SPCCFloorPlans2pg", "SPCCFlatMapMPGversion")
Map orientation follows the official event map: SOUTH (200 South) on the LEFT, NORTH on the RIGHT,
WEST (200 W / 300 W) at the TOP, EAST (West Temple) at the BOTTOM.

Run: python3 tool/build_venue.py
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "assets", "data")

# --------------------------------------------------------------------------------------------
# Shared direction fragments (all routes start at Registration / 200 South (Main) Entrance)
# --------------------------------------------------------------------------------------------
ENTER = "Enter the Salt Palace through the 200 South (Main) Entrance on 200 South, between West Temple and 200 West"
BADGE = "Registration + Badge Pick-Up is right inside the doors in the South Lobby; pick up your badge first if you don't have it"
INTO_CONCOURSE = ("Walk north out of the South Lobby past the South Foyer into the Lower Concourse, the long main corridor "
                  "(exhibit halls on your left, Grand Ballroom on your right)")
TO_NORTH_END = ("Keep walking north along the Lower Concourse past Hall DE and the Solutions Showcase Main Entrance "
                "on your left and the Grand Ballroom on your right")
PAST_150 = "Continue past the North Grand Ballroom Foyer and Rooms 150 and 151 on your right"
UP_TO_L2 = ("At the north end of the Lower Concourse, take the North Foyer escalators (elevator alongside) "
            "up one floor to Level 2")
L2_ARRIVE = "At the top you arrive in the Level 2 North Foyer at the start of the Upper Concourse"
TO_155_WING = ("At the north end of the Lower Concourse, bear left (west) past Hall 1 toward the Secondary Entrance "
               "and the 155 meeting-room wing")
WING_LIFT = "Take the escalators or elevator in the 155 wing lobby"
TIP_EAST = ("Shortcut: the East Entrance on West Temple opens straight onto Level 2 at East Registration "
            "(re-entry with badge)")
HYATT_GO = [ENTER,
            "From Badge Pick-Up in the South Lobby, head right (east) toward West Temple and follow the "
            "'Hyatt Regency' signs to the hotel's connected entrance at the southeast corner of the Salt Palace",
            "Enter the Hyatt Regency lobby (170 South West Temple)"]


def hyatt_dirs(level, tail):
    return HYATT_GO + [f"Take the Hyatt Regency elevators up to Level {level}",
                       f"Step out into the Level {level} Elevator Lobby"] + tail


# --------------------------------------------------------------------------------------------
# Levels
# --------------------------------------------------------------------------------------------
levels = [
    {"id": "L1", "name": "Level 1", "order": 1, "building": "Salt Palace",
     "description": "Street level: 200 South (Main) Entrance + Registration, Lower Concourse, Hall DE (keynotes), "
                    "Grand Ballroom, Rooms 150/151/155, Solutions Showcase (Halls A-C + 1-5)"},
    {"id": "L2", "name": "Level 2", "order": 2, "building": "Salt Palace",
     "description": "Upper Concourse: East Registration (coat + bag check), Rooms 250-254, 255 wing, Upper Mezzanine (257-260)"},
    {"id": "L3", "name": "Level 3", "order": 3, "building": "Salt Palace",
     "description": "Room 355 wing (above 255 and 155)"},
    {"id": "H2", "name": "Hyatt Regency - Level 2", "order": 12, "building": "Hyatt Regency",
     "description": "Salt Lake Ballroom A-DE and foyers"},
    {"id": "H3", "name": "Hyatt Regency - Level 3", "order": 13, "building": "Hyatt Regency",
     "description": "Park City and the mountain-named meeting rooms"},
    {"id": "H4", "name": "Hyatt Regency - Level 4", "order": 14, "building": "Hyatt Regency",
     "description": "Regency Ballroom A-D, Traverse, Wasatch, Broadcast Lounge"},
    {"id": "H5", "name": "Hyatt Regency - Level 5", "order": 15, "building": "Hyatt Regency",
     "description": "National-park-named meeting rooms (Zion, Bryce, Canyonlands, Arches, Capitol Reef)"},
]

# --------------------------------------------------------------------------------------------
# Landmarks (x 0..1000 south->north, y 0..600 west->east)
# --------------------------------------------------------------------------------------------
landmarks = [
    # Level 1
    {"id": "lm-l1-200s-entrance", "name": "200 South (Main) Entrance", "levelId": "L1", "kind": "entrance", "x": 8, "y": 480},
    {"id": "lm-l1-badge-pickup", "name": "Registration + Badge Pick-Up (South Lobby)", "levelId": "L1", "kind": "registration", "x": 70, "y": 482},
    {"id": "lm-l1-hyatt-connection", "name": "Hyatt Regency connection", "levelId": "L1", "kind": "entrance", "x": 125, "y": 560},
    {"id": "lm-l1-south-foyer", "name": "South Foyer", "levelId": "L1", "kind": "info", "x": 205, "y": 502},
    {"id": "lm-l1-keynote", "name": "Hall DE - Keynotes", "levelId": "L1", "kind": "keynote", "x": 215, "y": 365},
    {"id": "lm-l1-safety-desk", "name": "Onsite Safety + Lost & Found (Lower Concourse, between Halls D and C)", "levelId": "L1", "kind": "info", "x": 293, "y": 458},
    {"id": "lm-l1-showcase-entrance", "name": "Solutions Showcase Main Entrance", "levelId": "L1", "kind": "expo", "x": 400, "y": 446},
    {"id": "lm-l1-west-temple-entrance", "name": "West Temple Entrance", "levelId": "L1", "kind": "entrance", "x": 412, "y": 592},
    {"id": "lm-l1-first-aid-150", "name": "First Aid (by Room 150)", "levelId": "L1", "kind": "info", "x": 470, "y": 466},
    {"id": "lm-l1-first-aid-halls-2-3", "name": "First Aid (outside Halls 2 + 3)", "levelId": "L1", "kind": "info", "x": 745, "y": 318},
    {"id": "lm-l1-escalators-north", "name": "North Foyer escalators (to Level 2)", "levelId": "L1", "kind": "escalator", "x": 598, "y": 482},
    {"id": "lm-l1-elevator-north", "name": "North Foyer elevator", "levelId": "L1", "kind": "elevator", "x": 598, "y": 505},
    {"id": "lm-l1-secondary-entrance", "name": "Secondary Entrance (155 wing)", "levelId": "L1", "kind": "entrance", "x": 745, "y": 420},
    {"id": "lm-l1-escalators-155", "name": "155 wing escalators + elevator (to Levels 2 + 3)", "levelId": "L1", "kind": "escalator", "x": 805, "y": 418},
    {"id": "lm-l1-lower-mezzanine", "name": "Lower Mezzanine (walkway to Hall 4)", "levelId": "L1", "kind": "stairs", "x": 748, "y": 262},
    {"id": "lm-l1-lunch", "name": "Lunch + coffee (Solutions Showcase)", "levelId": "L1", "kind": "food", "x": 630, "y": 260},
    {"id": "lm-l1-corner-store", "name": "Corner Store + Attendee T-shirt Pick-Up", "levelId": "L1", "kind": "expo", "x": 585, "y": 118},
    {"id": "lm-l1-restrooms-south", "name": "Restrooms (approx., South Foyer)", "levelId": "L1", "kind": "restroom", "x": 240, "y": 462},
    {"id": "lm-l1-restrooms-north", "name": "Restrooms (approx., North Foyer)", "levelId": "L1", "kind": "restroom", "x": 445, "y": 462},
    {"id": "lm-l1-info-desk", "name": "Info Desk (approx., Lower Concourse)", "levelId": "L1", "kind": "info", "x": 160, "y": 455},
    # Level 2
    {"id": "lm-l2-escalators-north", "name": "North Foyer escalators (to Level 1)", "levelId": "L2", "kind": "escalator", "x": 598, "y": 482},
    {"id": "lm-l2-elevator-north", "name": "North Foyer elevator", "levelId": "L2", "kind": "elevator", "x": 598, "y": 505},
    {"id": "lm-l2-north-foyer", "name": "Level 2 North Foyer / Upper Concourse", "levelId": "L2", "kind": "info", "x": 690, "y": 470},
    {"id": "lm-l2-east-entrance", "name": "East Entrance on West Temple (re-entry with badge)", "levelId": "L2", "kind": "entrance", "x": 770, "y": 592},
    {"id": "lm-l2-coat-check", "name": "Coat + Bag Check (East Registration)", "levelId": "L2", "kind": "registration", "x": 840, "y": 545},
    {"id": "lm-l2-escalators-155", "name": "255 wing escalators + elevator (to Levels 1 + 3)", "levelId": "L2", "kind": "escalator", "x": 805, "y": 418},
    {"id": "lm-l2-restrooms", "name": "Restrooms (approx., Upper Concourse)", "levelId": "L2", "kind": "restroom", "x": 735, "y": 455},
    # Level 3
    {"id": "lm-l3-escalators-155", "name": "355 wing escalators + elevator (to Levels 1 + 2)", "levelId": "L3", "kind": "escalator", "x": 805, "y": 418},
    {"id": "lm-l3-restrooms", "name": "Restrooms (approx., 355 foyer)", "levelId": "L3", "kind": "restroom", "x": 735, "y": 418},
    # Hyatt
    {"id": "lm-h2-elevators", "name": "Elevator Lobby", "levelId": "H2", "kind": "elevator", "x": 249, "y": 420},
    {"id": "lm-h3-elevators", "name": "Elevator Lobby", "levelId": "H3", "kind": "elevator", "x": 268, "y": 420},
    {"id": "lm-h3-open-below", "name": "Open to Salt Lake Foyer below", "levelId": "H3", "kind": "info", "x": 270, "y": 200},
    {"id": "lm-h4-elevators", "name": "Elevator Lobby", "levelId": "H4", "kind": "elevator", "x": 262, "y": 420},
    {"id": "lm-h4-foyer-south", "name": "Regency Foyer South", "levelId": "H4", "kind": "info", "x": 436, "y": 405},
    {"id": "lm-h4-foyer-north", "name": "Regency Foyer North", "levelId": "H4", "kind": "info", "x": 625, "y": 405},
    {"id": "lm-h5-elevators", "name": "Elevator Lobby", "levelId": "H5", "kind": "elevator", "x": 262, "y": 420},
]

# --------------------------------------------------------------------------------------------
# Rooms
# --------------------------------------------------------------------------------------------
rooms = []


def room(id, name, level, x, y, w, h, directions, aliases=(), **extra):
    r = {"id": id, "name": name, "aliases": list(aliases), "levelId": level,
         "x": x, "y": y, "w": w, "h": h, "directions": directions}
    r.update(extra)
    rooms.append(r)


# ---- Level 1 -------------------------------------------------------------------------------
room("hyatt-lobby", "Hyatt Regency Lobby", "L1", 0, 530, 120, 70,
     HYATT_GO + ["You are in the Hyatt Regency lobby; group meet-ups gather here near the front desk"],
     ["Hyatt Regency Lobby", "Hyatt Lobby"], building="Hyatt Regency")

room("200-south-entrance-south", "Registration + Badge Pick-Up (200 South Entrance)", "L1", 10, 440, 120, 85,
     [ENTER,
      "Registration + Badge Pick-Up is straight ahead in the South Lobby, right inside the 200 South doors",
      "After you have your badge, visit any Info Desk for an ID check and 21+ wristband"],
     ["Salt Palace | 200 South Entrance (South)", "200 South Entrance", "Main Entrance", "Badge Pick-Up",
      "Registration", "South Lobby"])

room("l1-hall-de", "Hall DE (Keynotes)", "L1", 140, 290, 150, 150,
     [ENTER, BADGE, INTO_CONCOURSE,
      "Hall DE is the first exhibit hall on your left, just past the South Foyer; keynote doors open off the Lower Concourse"],
     ["Salt Palace | Level 1 | Hall DE", "Hall DE", "Halls D-E", "Keynote Hall", "Keynotes"])

# Grand Ballroom: west row (concourse side) J | H | BDF, east row (West Temple side) GI | ACE
GB_INTRO = [ENTER, BADGE, INTO_CONCOURSE]
room("l1-grand-ballroom-j", "Grand Ballroom J", "L1", 250, 474, 32, 34,
     GB_INTRO + ["Grand Ballroom J is the first ballroom door on your right, right after the South Foyer"],
     ["Salt Palace | Level 1 | Grand Ballroom J", "Ballroom J"])
room("l1-grand-ballroom-h", "Grand Ballroom H", "L1", 282, 474, 30, 34,
     GB_INTRO + ["Pass Grand Ballroom J on your right; Grand Ballroom H is the next door on your right"],
     ["Salt Palace | Level 1 | Grand Ballroom H", "Ballroom H"])
room("l1-grand-ballroom-bdf", "Grand Ballroom BDF", "L1", 312, 474, 78, 34,
     GB_INTRO + ["Pass Grand Ballroom J and H on your right",
                 "Grand Ballroom BDF is the long section on your right, opposite the Solutions Showcase Main Entrance"],
     ["Salt Palace | Level 1 | Grand Ballroom BDF", "Ballroom BDF", "Grand Ballroom B-D-F"])
room("l1-grand-ballroom-gi", "Grand Ballroom GI", "L1", 250, 508, 62, 36,
     GB_INTRO + ["At the South Foyer turn right (east) along the south side of the Grand Ballroom",
                 "Grand Ballroom GI is the southeast section, on the West Temple side behind Ballrooms J and H"],
     ["Salt Palace | Level 1 | Grand Ballroom GI", "Ballroom GI", "Grand Ballroom G-I"])
room("l1-grand-ballroom-ace", "Grand Ballroom ACE", "L1", 312, 508, 78, 36,
     GB_INTRO + ["Walk north past Grand Ballrooms J, H and BDF on your right to the North Grand Ballroom Foyer",
                 "Turn right into the foyer; Grand Ballroom ACE is the northeast section on the West Temple side, "
                 "entered from the North Foyer"],
     ["Salt Palace | Level 1 | Grand Ballroom ACE", "Ballroom ACE", "Grand Ballroom A-C-E"])
room("l1-north-grand-ballroom-foyer", "North Grand Ballroom Foyer", "L1", 392, 474, 50, 70,
     GB_INTRO + ["Walk north past the Grand Ballroom doors on your right",
                 "The North Grand Ballroom Foyer opens on your right at the north end of the ballroom, "
                 "next to the West Temple Entrance"],
     ["Salt Palace | Level 1 | North Grand Ballroom Foyer", "North Foyer", "North Ballroom Foyer"])
room("l1-150", "Room 150 A-G", "L1", 452, 474, 58, 40,
     GB_INTRO + ["Walk north past the Grand Ballroom and the North Grand Ballroom Foyer on your right",
                 "Room 150 is the next set of doors on your right; the First Aid station is beside it"],
     ["Salt Palace | Level 1 | 150", "150", "150 A-G", "Room 150"])
room("l1-151", "Room 151 A-G", "L1", 514, 474, 60, 40,
     GB_INTRO + ["Walk north past the Grand Ballroom, the North Grand Ballroom Foyer and Room 150 on your right",
                 "Room 151 is the next room on your right, just before the North Foyer escalators"],
     ["Salt Palace | Level 1 | 151", "151", "151 A-G", "Room 151"])

# Solutions Showcase (Halls A-C)
room("l1-solutions-showcase-hall-b-starlight-summit-zone", "Solutions Showcase - Starlight Summit Zone (Hall B, Learning Lounge)",
     "L1", 296, 290, 80, 155,
     GB_INTRO + ["Walk north past Hall DE on your left to the Solutions Showcase Main Entrance (left side, opposite Grand Ballroom BDF)",
                 "Enter the Showcase and turn left (south); the Starlight Summit Zone with the Learning Lounge is the "
                 "southern part of Halls A-C, next to Hall DE"],
     ["Salt Palace | Level 1 | Solutions Showcase | Hall B | Starlight Summit Zone", "Starlight Summit",
      "Learning Lounge", "Hall B"])
room("l1-halls-a-c-halls-1-5", "Solutions Showcase - Halls A-C + Halls 1-5", "L1", 376, 290, 139, 155,
     GB_INTRO + ["Walk north past Hall DE on your left",
                 "The Solutions Showcase Main Entrance is on your left, opposite Grand Ballroom BDF; the Showcase fills "
                 "Halls A-C and continues north and west into Halls 1-5",
                 "Coffee breaks, lunch and the #KubeCrawl welcome reception are served throughout the Showcase"],
     ["Salt Palace | Level 1 | Halls A-C, Halls 1-5", "Solutions Showcase", "Expo Hall", "Halls A-C",
      "Showcase", "Sponsor Showcase"])
# Halls 1-5
room("l1-solutions-showcase-hall-1-alpine-overlook-zone-network-nook", "Network Nook (Hall 1, Alpine Overlook Zone)",
     "L1", 520, 345, 105, 95,
     GB_INTRO + [TO_NORTH_END,
                 "Enter the Showcase from the north end of the Lower Concourse into Hall 1 (on your left)",
                 "The Network Nook is in the southern half of Hall 1, in the Alpine Overlook Zone near the Astral Peak area"],
     ["Salt Palace | Level 1 | Solutions Showcase | Hall 1 | Alpine Overlook Zone | Network Nook", "Network Nook"])
room("l1-solutions-showcase-hall-1-alpine-overlook-zone-demo-theater", "Demo Theater (Hall 1, Alpine Overlook Zone)",
     "L1", 625, 345, 115, 95,
     GB_INTRO + [TO_NORTH_END, PAST_150,
                 "Enter Hall 1 on your left at the north end of the Lower Concourse",
                 "The Demo Theater is in the northern half of Hall 1 (Alpine Overlook Zone)"],
     ["Salt Palace | Level 1 | Solutions Showcase | Hall 1 | Alpine Overlook Zone | Demo Theater", "Demo Theater",
      "Alpine Overlook"])
room("l1-halls-2-3", "Solutions Showcase - Halls 2 + 3 (Honeycomb Hub)", "L1", 520, 290, 220, 55,
     GB_INTRO + [TO_NORTH_END, "Enter Hall 1 on your left",
                 "Walk straight through Hall 1 (heading west); Halls 2 + 3 with the Honeycomb Hub are directly behind it"],
     ["Hall 2", "Hall 3", "Halls 2-3", "Honeycomb Hub"])
room("l1-lower-concourse-foyer-hall-4-via-lower-mezzanine", "Hall 4 (Lower Concourse Foyer + Hall 4 via Lower Mezzanine)",
     "L1", 520, 230, 220, 60,
     GB_INTRO + [TO_NORTH_END, PAST_150,
                 "At the north end of the Lower Concourse follow signs to the Lower Mezzanine",
                 "Take the Lower Mezzanine walkway west; it leads down into Hall 4 (on show days walk through Halls 1-3 instead)"],
     ["Salt Palace | Level 1 | Lower Concourse Foyer + Hall 4 (via Lower Mezzanine)", "Hall 4",
      "Lower Concourse Foyer + Hall 4", "Amber Hive"])
room("l1-solutions-showcase-halls-5-cosmic-canyon-zone", "Cosmic Canyon Zone (Hall 5)", "L1", 520, 100, 120, 130,
     GB_INTRO + [TO_NORTH_END, "Enter the Showcase through Hall 1 on your left",
                 "Walk west through Halls 2, 3 and 4 to Hall 5 at the far (west) end of the Showcase",
                 "The Cosmic Canyon Zone is the southern half of Hall 5, with the Poster Pavilion and Corner Store"],
     ["Salt Palace | Level 1 | Solutions Showcase | Halls 5 | Cosmic Canyon Zone",
      "Salt Palace | Level 1 | Solutions Showcase | Hall 5 | Cosmic Canyon Zone", "Cosmic Canyon", "Hall 5",
      "Cloud Native University", "Poster Pavilion"])
room("l1-solutions-showcase-hall-5-cosmic-canyon-zone-project-pavilion", "Project Pavilion (Hall 5, Cosmic Canyon Zone)",
     "L1", 640, 100, 100, 130,
     GB_INTRO + [TO_NORTH_END, "Enter the Showcase through Hall 1 on your left",
                 "Walk west through Halls 2, 3 and 4 to Hall 5 at the far (west) end",
                 "The Project Pavilion is in the northern half of Hall 5"],
     ["Salt Palace | Level 1 | Solutions Showcase | Hall 5 | Cosmic Canyon Zone | Project Pavilion", "Project Pavilion"])
room("l1-155", "Room 155 A-F", "L1", 750, 336, 110, 66,
     GB_INTRO + [TO_NORTH_END, PAST_150, TO_155_WING,
                 "Room 155 is on the ground floor of the wing, by the Secondary Entrance"],
     ["Salt Palace | Level 1 | 155", "155", "Room 155"])

# ---- Level 2 -------------------------------------------------------------------------------
L2_BASE = [ENTER, BADGE, INTO_CONCOURSE, TO_NORTH_END, PAST_150, UP_TO_L2, L2_ARRIVE]
room("l2-east-registration", "East Registration (Coat + Bag Check)", "L2", 740, 520, 130, 48,
     L2_BASE + ["Walk north along the Upper Concourse; East Registration with Coat + Bag Check is on your right "
                "along the West Temple windows, opposite Rooms 250-251", TIP_EAST],
     ["Salt Palace | Level 2 | East Registration", "East Registration", "Coat + Bag Check", "Coat Check", "Bag Check"])
room("l2-250-a-c", "Room 250 A-C", "L2", 760, 470, 30, 48,
     L2_BASE + ["Walk north along the Upper Concourse",
                "Room 250 A-C is the first meeting room on your right"],
     ["Salt Palace | Level 2 | 250 A-C", "250 A-C", "250 ABC", "250"])
room("l2-250-d-f", "Room 250 D-F", "L2", 790, 470, 30, 48,
     L2_BASE + ["Walk north along the Upper Concourse",
                "Pass Room 250 A-C on your right; Room 250 D-F is the next door on your right"],
     ["Salt Palace | Level 2 | 250 D-F", "250 D-F", "250 DEF"])
room("l2-251-a-c", "Room 251 A-C", "L2", 826, 470, 30, 48,
     L2_BASE + ["Walk north along the Upper Concourse past Room 250 A-C and 250 D-F on your right",
                "Room 251 A-C is the 3rd room on your right, across from Coat + Bag Check"],
     ["Salt Palace | Level 2 | 251 A-C", "251 A-C", "251 ABC", "251"])
room("l2-251-d-f", "Room 251 D-F", "L2", 856, 470, 30, 48,
     L2_BASE + ["Walk north along the Upper Concourse past Rooms 250 A-C, 250 D-F and 251 A-C on your right",
                "Room 251 D-F is the 4th room on your right"],
     ["Salt Palace | Level 2 | 251 D-F", "251 D-F", "251 DEF"])
room("l2-252", "Room 252 A-B", "L2", 892, 455, 40, 30,
     L2_BASE + ["Walk to the far north end of the Upper Concourse past Rooms 250 and 251",
                "Room 252 is at the end of the concourse, next to the Business Center"],
     ["252", "252 A-B"])
room("l2-253", "Room 253 A-B", "L2", 892, 488, 40, 30,
     L2_BASE + ["Walk to the far north end of the Upper Concourse past Rooms 250 and 251 on your right",
                "Room 253 is the last room on your right"],
     ["253", "253 A-B"])
room("l2-254", "Room 254", "L2", 880, 385, 60, 55,
     L2_BASE + ["Walk north along the Upper Concourse past Rooms 250 and 251 on your right",
                "At the north end turn left (west); Room 254 is ahead on the left, past the 255 wing"],
     ["Salt Palace | Level 2 | 254", "254", "254 A-C", "Room 254"])
L2_WING = L2_BASE + ["Walk north along the Upper Concourse, then turn left (west) toward the 255 meeting-room wing",
                     "Alternative: from Level 1 take the escalators/elevator in the 155 wing up one floor"]
room("l2-255-a", "Room 255 A", "L2", 750, 369, 28, 33,
     L2_WING + ["Room 255 A is the first (southeast) room of the 255 wing"],
     ["Salt Palace | Level 2 | 255 A", "255 A", "255A"])
room("l2-255-bc", "Room 255 BC", "L2", 778, 369, 82, 33,
     L2_WING + ["Pass Room 255 A; Room 255 BC is the next, larger room on the same (east) side of the wing"],
     ["Salt Palace | Level 2 | 255 BC", "255 BC", "255 B-C"])
room("l2-255-d", "Room 255 D", "L2", 750, 336, 28, 33,
     L2_WING + ["Room 255 D is on the west side of the wing, behind Room 255 A"],
     ["Salt Palace | Level 2 | 255 D", "255 D", "255D", "Contribfest"])
room("l2-255-ef", "Room 255 EF", "L2", 778, 336, 82, 33,
     L2_WING + ["Room 255 EF is the large room on the west side of the wing, behind Room 255 BC"],
     ["Salt Palace | Level 2 | 255 EF", "255 EF", "255 E-F"])
UPPER_MEZZ = L2_BASE + ["Walk to the north end of the Upper Concourse and turn left (west)",
                        "Pass Room 254 and follow signs up to the Upper Mezzanine"]
room("l2-257", "Room 257 A-B", "L2", 870, 315, 60, 28,
     UPPER_MEZZ + ["Room 257 is the first room on the Upper Mezzanine"], ["257", "257 A-B"])
room("l2-258", "Room 258", "L2", 870, 296, 30, 17,
     UPPER_MEZZ + ["Room 258 is past Room 257"], ["258"])
room("l2-259", "Room 259", "L2", 900, 296, 30, 17,
     UPPER_MEZZ + ["Room 259 is next to Room 258"], ["259"])
room("l2-260a", "Room 260A (All-Attendee Quiet Room)", "L2", 900, 262, 30, 30,
     UPPER_MEZZ + ["Walk past Rooms 257, 258 and 259", "Room 260A is at the end of the Upper Mezzanine"],
     ["Salt Palace | Level 2 | 260A", "260A", "260 A", "Quiet Room"])
room("l2-260b", "Room 260B (Women + Non-Binary Quiet Room)", "L2", 870, 262, 30, 30,
     UPPER_MEZZ + ["Walk past Rooms 257, 258 and 259", "Room 260B is next to Room 260A at the end of the Upper Mezzanine"],
     ["Salt Palace | Level 2 | 260B", "260B", "260 B"])
room("l2-upper-mezzanine", "Upper Mezzanine", "L2", 935, 262, 55, 100,
     UPPER_MEZZ + ["The Upper Mezzanine lounge area is beside Rooms 257-260"],
     ["Salt Palace | Level 2 | Upper Mezzanine", "Upper Mezzanine"])

# ---- Level 3 -------------------------------------------------------------------------------
L3_BASE = [ENTER, BADGE, INTO_CONCOURSE, TO_NORTH_END, PAST_150, TO_155_WING,
           WING_LIFT + " up two floors to Level 3"]
for rid, nm, x, w, y, side in [("a", "A", 750, 24, 369, "first room on the east side"),
                               ("b", "B", 774, 43, 369, "middle room on the east side"),
                               ("c", "C", 817, 43, 369, "far room on the east side"),
                               ("d", "D", 750, 24, 336, "first room on the west side"),
                               ("e", "E", 774, 43, 336, "middle room on the west side"),
                               ("f", "F", 817, 43, 336, "far room on the west side")]:
    room(f"l3-355-{rid}", f"Room 355 {nm}", "L3", x, y, w, 33,
         L3_BASE + [f"Room 355 {nm} is the {side} of the 355 wing (directly above Room 255)"],
         [f"Salt Palace | Level 3 | 355 {nm}", f"355 {nm}", f"355{nm}"])

# ---- Hyatt Regency -------------------------------------------------------------------------
H2T = ["Walk through the Salt Lake Foyer South ahead of you"]
room("hyatt-l2-salt-lake-ballroom-a", "Salt Lake Ballroom A", "H2", 320, 124, 113, 131,
     hyatt_dirs(2, H2T + ["Salt Lake Ballroom A is the first ballroom door on your right"]),
     ["Hyatt Regency | Level 2 | Salt Lake Ballroom A"], building="Hyatt Regency")
room("hyatt-l2-salt-lake-ballroom-b", "Salt Lake Ballroom B", "H2", 320, 0, 113, 124,
     hyatt_dirs(2, H2T + ["Continue past Ballroom A; Salt Lake Ballroom B is behind it at the end of the foyer"]),
     ["Hyatt Regency | Level 2 | Salt Lake Ballroom B"], building="Hyatt Regency")
room("hyatt-l2-salt-lake-ballroom-c", "Salt Lake Ballroom C", "H2", 433, 0, 193, 255,
     hyatt_dirs(2, ["Walk ahead into the Salt Lake Foyer West",
                    "Salt Lake Ballroom C is the middle ballroom section, doors on your left off the Foyer West"]),
     ["Hyatt Regency | Level 2 | Salt Lake Ballroom C"], building="Hyatt Regency")
room("hyatt-l2-salt-lake-ballroom-de", "Salt Lake Ballroom DE", "H2", 626, 0, 180, 255,
     hyatt_dirs(2, ["Walk ahead into the Salt Lake Foyer West and keep going past Ballroom C",
                    "Salt Lake Ballroom DE is the last (largest) ballroom section at the far end of the foyer"]),
     ["Hyatt Regency | Level 2 | Salt Lake Ballroom DE", "Salt Lake Ballroom D-E"], building="Hyatt Regency")
room("hyatt-l2-the-nest", "The Nest", "H2", 433, 340, 100, 70,
     hyatt_dirs(2, ["The Nest is just ahead, between the elevators and the Salt Lake Foyer West"]),
     ["The Nest"], building="Hyatt Regency")
room("hyatt-l2-aspen", "Aspen", "H2", 20, 420, 93, 85,
     hyatt_dirs(2, ["Turn away from the ballrooms; Aspen is at the end of the corridor on the other side of the elevators"]),
     ["Aspen"], building="Hyatt Regency")
room("hyatt-l2-blue-spruce", "Blue Spruce", "H2", 700, 470, 106, 63,
     hyatt_dirs(2, ["Walk through the Salt Lake Foyer East", "Blue Spruce is at the far end of the Foyer East"]),
     ["Blue Spruce"], building="Hyatt Regency")
room("hyatt-l2-cottonwood", "Cottonwood", "H2", 846, 480, 107, 57,
     hyatt_dirs(2, ["Walk through the Salt Lake Foyer East past Blue Spruce", "Cottonwood is the last room at the end"]),
     ["Cottonwood"], building="Hyatt Regency")
room("hyatt-l2-juniper", "Juniper", "H2", 860, 410, 107, 63,
     hyatt_dirs(2, ["Walk through the Salt Lake Foyer East past Blue Spruce", "Juniper is beside Cottonwood at the end"]),
     ["Juniper"], building="Hyatt Regency")

room("hyatt-l3-park-city", "Park City", "H3", 33, 330, 134, 100,
     hyatt_dirs(3, ["Turn left out of the elevator lobby", "Park City is the room just past the elevators"]),
     ["Hyatt Regency | Level 3 | Park City", "Park City"], building="Hyatt Regency")
for rid, nm, x in [("alta", "Alta", 400), ("snowbird", "Snowbird", 463), ("solitude", "Solitude", 530),
                   ("brighton", "Brighton", 603)]:
    room(f"hyatt-l3-{rid}", nm, "H3", x, 230, 63 if rid != "brighton" else 73, 92,
         hyatt_dirs(3, ["Walk ahead along the corridor overlooking the Salt Lake Ballroom",
                        f"{nm} is one of the row of mountain-named rooms (Alta, Snowbird, Solitude, Brighton) on your left"]),
         [nm], building="Hyatt Regency")
room("hyatt-l3-powder-mountain", "Powder Mountain", "H3", 713, 190, 120, 85,
     hyatt_dirs(3, ["Walk ahead past Alta, Snowbird, Solitude and Brighton", "Powder Mountain is at the end of that row"]),
     ["Powder Mountain"], building="Hyatt Regency")
room("hyatt-l3-woodward", "Woodward", "H3", 713, 395, 93, 78,
     hyatt_dirs(3, ["Walk to the far end of the corridor", "Woodward is near Deer Valley and Snowbasin"]),
     ["Woodward"], building="Hyatt Regency")
room("hyatt-l3-snowbasin", "Snowbasin", "H3", 860, 370, 100, 64,
     hyatt_dirs(3, ["Walk to the far end of the corridor", "Snowbasin is the end room next to Deer Valley"]),
     ["Snowbasin"], building="Hyatt Regency")
room("hyatt-l3-deer-valley", "Deer Valley", "H3", 860, 434, 100, 63,
     hyatt_dirs(3, ["Walk to the far end of the corridor", "Deer Valley is the end room next to Snowbasin"]),
     ["Deer Valley"], building="Hyatt Regency")

H4T = ["Walk ahead into the Regency Foyer"]
room("hyatt-l4-traverse", "Traverse", "H4", 47, 400, 146, 99,
     hyatt_dirs(4, ["Turn away from the Regency Foyer", "Traverse is past the elevators at the end of the corridor"]),
     ["Traverse"], building="Hyatt Regency")
room("hyatt-l4-regency-ballroom-a", "Regency Ballroom A", "H4", 180, 105, 207, 290,
     hyatt_dirs(4, H4T + ["Regency Ballroom A is the first ballroom section, closest to the elevators"]),
     ["Hyatt Regency | Level 4 | Regency Ballroom A"], building="Hyatt Regency")
room("hyatt-l4-regency-ballroom-b-d", "Regency Ballroom B-D", "H4", 387, 105, 400, 290,
     hyatt_dirs(4, H4T + ["Pass Regency Ballroom A",
                          "Regency Ballroom B-D (sections B, C and D opened into one room) fills the rest of the "
                          "ballroom; enter from the Regency Foyer South or North"]),
     ["Hyatt Regency | Level 4 | Regency Ballroom B-D", "Regency Ballroom BCD", "Regency Ballroom B-C-D"],
     building="Hyatt Regency",
     combines=["hyatt-l4-regency-ballroom-b", "hyatt-l4-regency-ballroom-cd"],
     note="Same physical space as Regency Ballroom B + CD (air walls open); intentionally overlaps those two rooms.")
room("hyatt-l4-regency-ballroom-b", "Regency Ballroom B", "H4", 387, 105, 193, 290,
     hyatt_dirs(4, H4T + ["Pass Regency Ballroom A; Regency Ballroom B is the next section, off the Regency Foyer South"]),
     ["Hyatt Regency | Level 4 | Regency Ballroom B"], building="Hyatt Regency", partOf="hyatt-l4-regency-ballroom-b-d")
room("hyatt-l4-regency-ballroom-cd", "Regency Ballroom CD", "H4", 580, 105, 207, 290,
     hyatt_dirs(4, H4T + ["Walk through the Regency Foyer to its north end",
                          "Regency Ballroom CD is the last section, off the Regency Foyer North"]),
     ["Hyatt Regency | Level 4 | Regency Ballroom CD", "Regency Ballroom C-D"], building="Hyatt Regency",
     partOf="hyatt-l4-regency-ballroom-b-d")
room("hyatt-l4-wasatch", "Wasatch", "H4", 713, 440, 93, 100,
     hyatt_dirs(4, H4T + ["Walk to the north end of the Regency Foyer", "Wasatch is on the far side of the foyer"]),
     ["Wasatch"], building="Hyatt Regency")
room("hyatt-l4-broadcast-lounge", "Broadcast Lounge", "H4", 847, 412, 120, 78,
     hyatt_dirs(4, H4T + ["Walk to the north end of the Regency Foyer past Wasatch",
                          "The Broadcast Lounge is at the end"]),
     ["Broadcast Lounge"], building="Hyatt Regency")

H5T = ["Walk ahead along the Level 5 corridor"]
for rid, nm, x, y, w, h, where in [
        ("zion", "Zion", 340, 300, 60, 60, "the first room on your left"),
        ("bryce", "Bryce", 400, 300, 60, 60, "next to Zion"),
        ("canyonlands", "Canyonlands", 473, 390, 120, 55, "across the corridor from Bryce"),
        ("arches", "Arches", 553, 300, 54, 60, "past Bryce"),
        ("capitol-reef", "Capitol Reef", 620, 310, 80, 55, "at the end of the corridor")]:
    raw = {"zion": ["Hyatt Regency | Level 5 | Zion", "Prayer Room"],
           "capitol-reef": ["Hyatt Regency | Level 5 | Capitol Reef"]}.get(rid, [])
    room(f"hyatt-l5-{rid}", nm, "H5", x, y, w, h, hyatt_dirs(5, H5T + [f"{nm} is {where}"]),
         raw + [nm], building="Hyatt Regency")

# --------------------------------------------------------------------------------------------
# Off-site venues (walking steps from the 200 South (Main) Entrance)
# --------------------------------------------------------------------------------------------
EXIT = "Exit the Salt Palace through the 200 South (Main) Entrance onto 200 South"
offsite = [
    {"id": "offsite-hyatt-regency", "name": "Hyatt Regency Salt Lake City (hotel front entrance)",
     "address": "170 South West Temple, Salt Lake City, UT 84101", "lat": 40.7653, "lng": -111.8945, "walkMinutes": 2,
     "directions": [EXIT, "Turn left (east) and walk to the corner of 200 South and West Temple",
                    "Turn left (north) on West Temple; the Hyatt Regency entrance is right there, attached to the Salt Palace",
                    "Indoors you can also reach it through the connection at the southeast corner of the South Lobby"]},
    {"id": "offsite-ac-hotel-downtown", "name": "AC Hotel Salt Lake City Downtown",
     "address": "225 West 200 South, Salt Lake City, UT 84101", "lat": 40.7647558, "lng": -111.8973346, "walkMinutes": 5,
     "directions": [EXIT, "Turn right (west) and walk along 200 South",
                    "Cross 200 West at the light",
                    "The AC Hotel is just past the corner at 225 West 200 South"]},
    {"id": "offsite-pierpont-place", "name": "Pierpont Place",
     "address": "163 W Pierpont Ave, Salt Lake City, UT 84101", "lat": 40.7636, "lng": -111.8958, "walkMinutes": 5,
     "directions": [EXIT, "Cross 200 South at the crosswalk",
                    "Walk south on 200 West for about half a block",
                    "Turn left (east) onto Pierpont Avenue",
                    "Pierpont Place is at 163 W Pierpont Ave, a short way along on your right"]},
    {"id": "offsite-hilton-city-center", "name": "Hilton Salt Lake City Center",
     "address": "255 South West Temple, Salt Lake City, UT 84101", "lat": 40.76395, "lng": -111.89362, "walkMinutes": 5,
     "directions": [EXIT, "Turn left (east) and walk to the corner of 200 South and West Temple (Hyatt Regency on your left)",
                    "Cross 200 South and walk south on West Temple",
                    "The Hilton Salt Lake City Center is on your right, about halfway down the block at 255 South West Temple"]},
    {"id": "offsite-kimpton-monaco", "name": "Kimpton Hotel Monaco Salt Lake City (Floor 2, Paris Ballroom)",
     "address": "15 W 200 S, Salt Lake City, UT 84101", "lat": 40.76483, "lng": -111.8917, "walkMinutes": 5,
     "directions": [EXIT, "Turn left (east) and walk along 200 South to West Temple",
                    "Cross West Temple and continue east on 200 South toward Main Street",
                    "Kimpton Hotel Monaco is on the corner just before Main Street (15 West 200 South)",
                    "Take the stairs or elevator to Floor 2 for the Paris Ballroom"]},
    {"id": "offsite-edison-house", "name": "Edison House",
     "address": "335 S 200 W, Salt Lake City, UT 84101", "lat": 40.7618, "lng": -111.8963, "walkMinutes": 8,
     "directions": [EXIT, "Turn right (west) and walk to the corner of 200 South and 200 West",
                    "Cross 200 South and walk south on 200 West",
                    "Cross 300 South and continue about half a block",
                    "Edison House (21+ social club) is at 335 South 200 West"]},
    {"id": "offsite-le-meridien", "name": "Le Meridien Salt Lake City Downtown",
     "address": "131 S 300 W, Salt Lake City, UT 84101", "lat": 40.7662291, "lng": -111.899423, "walkMinutes": 8,
     "directions": [EXIT, "Turn right (west) and walk along 200 South past 200 West",
                    "At 300 West turn right (north)",
                    "Walk about half a block north; Le Meridien is at 131 South 300 West, across from the Salt Palace's west side"]},
    {"id": "offsite-utah-moca", "name": "Utah Museum of Contemporary Art",
     "address": "20 S West Temple, Salt Lake City, UT 84101", "lat": 40.7683461, "lng": -111.8947354, "walkMinutes": 8,
     "directions": [EXIT, "Turn left (east) and walk to West Temple",
                    "Turn left (north) and walk up West Temple along the Salt Palace's east side",
                    "Pass 100 South and Abravanel Hall",
                    "Utah MOCA is on your left at 20 South West Temple, just before South Temple"]},
    {"id": "offsite-marriott-downtown-city-creek", "name": "Salt Lake Marriott Downtown at City Creek",
     "address": "75 S W Temple St, Salt Lake City, UT 84101", "lat": 40.7680, "lng": -111.8928, "walkMinutes": 7,
     "directions": [EXIT, "Turn left (east) and walk to West Temple",
                    "Turn left (north) and walk up West Temple along the Salt Palace's east side",
                    "Cross 100 South; the Marriott Downtown is on your right (east side of West Temple) at 75 South West Temple"]},
    {"id": "offsite-gallivan-center", "name": "Gallivan Center",
     "address": "50 E 200 S, Salt Lake City, UT 84111", "lat": 40.7650, "lng": -111.8893, "walkMinutes": 9,
     "directions": [EXIT, "Turn left (east) and walk along 200 South",
                    "Cross West Temple, then Main Street",
                    "The Gallivan Center plaza opens on your right, between Main Street and State Street"]},
    {"id": "offsite-marriott-city-center", "name": "Salt Lake City Marriott City Center",
     "address": "220 S State St, Salt Lake City, UT 84111", "lat": 40.7644, "lng": -111.8884, "walkMinutes": 11,
     "directions": [EXIT, "Turn left (east) and walk along 200 South",
                    "Cross West Temple and Main Street, passing the Gallivan Center on your right",
                    "At State Street the Marriott City Center is on your right, at 220 South State Street"]},
    {"id": "offsite-radisson-downtown", "name": "Radisson Hotel Salt Lake City Downtown",
     "address": "215 W South Temple, Salt Lake City, UT 84101", "lat": 40.768988, "lng": -111.8978173, "walkMinutes": 12,
     "directions": [EXIT, "Turn left (east) and walk to West Temple",
                    "Turn left (north) and walk up West Temple past the Salt Palace and Abravanel Hall to South Temple",
                    "Turn left (west) on South Temple",
                    "Walk past 200 West; the Radisson is on your left at 215 West South Temple",
                    "Shorter if you are already inside: leave through the north end of the Salt Palace and walk west on South Temple"]},
    {"id": "offsite-clark-planetarium", "name": "Clark Planetarium",
     "address": "110 South 400 West, Salt Lake City, UT 84101", "lat": 40.7667, "lng": -111.9029, "walkMinutes": 13,
     "directions": [EXIT, "Turn right (west) and walk along 200 South",
                    "Cross 200 West and 300 West",
                    "At 400 West turn right (north) and walk one block, passing the TRAX Planetarium station",
                    "Clark Planetarium is on your left at 100 South, at the south end of The Gateway"]},
]

venue = {
    "name": "Salt Palace Convention Center",
    "address": "90 South West Temple, Salt Lake City, UT 84101 (main entrance + registration on 200 South)",
    "isApproximate": True,
    "orientation": {"left": "south (200 South)", "right": "north (toward South Temple)",
                    "top": "west (200 West / 300 West)", "bottom": "east (West Temple)"},
    "notes": ("Schematic reconstruction from the official KubeCon NA 2026 venue map (bit.ly/kcna26maps) and Salt Palace "
              "floor plan PDFs. Positions are approximate; restroom/info-desk/escalator markers are best guesses - "
              "follow onsite signage. Hyatt Regency levels are separate maps (H2-H5); the hotel lobby is shown on Level 1."),
    "sources": [
        "https://events.linuxfoundation.org/kcna26-venue-map",
        "https://events.linuxfoundation.org/kubecon-cloudnativecon-north-america/attend/venue-travel/",
        "https://assets.simpleviewinc.com/simpleview/image/upload/v1/clients/saltlake/SPCCFlatMapMPGversion_230e4948-60fb-49d8-b247-5aac692076c1.pdf",
        "https://res.cloudinary.com/simpleview/image/upload/v1/clients/saltlake/SPCCFloorPlans2pg_ddefcdd5-9dc9-4182-bfe0-c00dce6d4e72.pdf",
    ],
    "levels": levels,
    "landmarks": landmarks,
    "rooms": rooms,
    "offsite": offsite,
}

out = os.path.join(DATA, "venue.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump(venue, f, ensure_ascii=False, indent=1)
    f.write("\n")
print("wrote", out, len(rooms), "rooms", len(offsite), "offsite", len(landmarks), "landmarks")
