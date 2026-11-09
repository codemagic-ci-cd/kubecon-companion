#!/usr/bin/env python3
"""Merge the calibrated map annotations into assets/data/official_map.json.

Inputs (image pixel coordinates of assets/maps/kcna26_venue_map.jpg):
  assets/data/map_salt_palace.json  Salt Palace panels (sp-L1, sp-L2, sp-L3)
  assets/data/map_hyatt.json        Hyatt Regency panels (hy-L2 .. hy-L5)

Validates ids, edges, room coverage of venue.json / sessions / happenings and
that every room door is reachable from the 200 South entrance.

  python3 -I tool/merge_official_map.py [--debug out.png]
(--debug needs Pillow and draws boxes, nodes and edges on the map image.)
"""

import json
import sys
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "assets" / "data"
IMAGE = "assets/maps/kcna26_venue_map.jpg"
START = "sp-entrance-200-south"
SHARED = [
    "sp-entrance-200-south",
    "sp-entrance-west-temple",
    "sp-hyatt-lobby-elevators",
    "hy-L2-elevators",
    "hy-L3-elevators",
    "hy-L4-elevators",
    "hy-L5-elevators",
]
REGIONS = {
    "sp-L1": "L1", "sp-L2": "L2", "sp-L3": "L3",
    "hy-L2": "H2", "hy-L3": "H3", "hy-L4": "H4", "hy-L5": "H5",
}
EDGE_KINDS = {"walk", "escalator", "elevator", "stairs"}


def load(name):
    with open(DATA / name, encoding="utf-8") as f:
        return json.load(f)


def image_size():
    data = (ROOT / IMAGE).read_bytes()
    # Walk JPEG markers to the SOFn segment.
    i = 2
    while i < len(data):
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        length = int.from_bytes(data[i + 2:i + 4], "big")
        if marker in (0xC0, 0xC1, 0xC2):
            h = int.from_bytes(data[i + 5:i + 7], "big")
            w = int.from_bytes(data[i + 7:i + 9], "big")
            return w, h
        i += 2 + length
    raise SystemExit("could not read image size")


def merge(parts, warnings):
    regions, rooms, nodes, edges = {}, {}, {}, []
    seen_edges = set()
    for src, part in parts:
        for r in part.get("regions", []):
            if r["id"] in regions:
                warnings.append(f"{src}: duplicate region {r['id']} ignored")
                continue
            regions[r["id"]] = r
        for rid, r in part.get("rooms", {}).items():
            if rid in rooms:
                warnings.append(f"{src}: duplicate room {rid} ignored")
                continue
            rooms[rid] = r
        for n in part.get("nodes", []):
            nid = n["id"]
            if nid in nodes:
                # Shared nodes: the file owning the panel wins.
                owner = "salt" if n.get("regionId", "").startswith("sp-") else "hyatt"
                if owner in src:
                    nodes[nid] = {**nodes[nid], **n}
                continue
            nodes[nid] = n
        for e in part.get("edges", []):
            key = tuple(sorted((e["from"], e["to"]))) + (e.get("kind", "walk"),)
            if key in seen_edges:
                continue
            seen_edges.add(key)
            edges.append({
                "from": e["from"],
                "to": e["to"],
                "kind": e.get("kind", "walk"),
                "hint": e.get("hint"),
            })
    return regions, rooms, nodes, edges


def validate(out, errors, warnings):
    venue = load("venue.json")
    nodes = {n["id"]: n for n in out["nodes"]}
    ids = [n["id"] for n in out["nodes"]]
    if len(ids) != len(set(ids)):
        errors.append("node ids are not unique")
    for r in out["regions"]:
        if r["id"] not in REGIONS:
            warnings.append(f"unexpected region {r['id']}")
        elif r["levelId"] != REGIONS[r["id"]]:
            errors.append(f"region {r['id']} has levelId {r['levelId']}")
    region_ids = {r["id"] for r in out["regions"]}
    for rid in REGIONS:
        if rid not in region_ids:
            errors.append(f"missing region {rid}")
    for n in out["nodes"]:
        if n.get("regionId") not in region_ids:
            errors.append(f"node {n['id']} has unknown region {n.get('regionId')}")
    for e in out["edges"]:
        for end in (e["from"], e["to"]):
            if end not in nodes:
                errors.append(f"edge {e['from']} -> {e['to']} references missing {end}")
        if e["kind"] not in EDGE_KINDS:
            errors.append(f"edge {e['from']} -> {e['to']} has kind {e['kind']}")
    for sid in SHARED:
        if sid not in nodes:
            errors.append(f"missing shared node {sid}")

    venue_rooms = {r["id"]: r for r in venue["rooms"]}
    alias = {}
    for r in venue["rooms"]:
        alias[r["id"].lower()] = r["id"]
        for a in r.get("aliases", []):
            alias.setdefault(a.lower(), r["id"])
    offsite = {o["id"].lower() for o in venue.get("offsite", [])}
    for rid in out["rooms"]:
        if rid not in venue_rooms:
            errors.append(f"map room {rid} is not a venue.json room id")
        elif out["rooms"][rid].get("regionId") not in region_ids:
            errors.append(f"map room {rid} has unknown region")

    def on_map(room_id):
        r = venue_rooms[room_id]
        return room_id in out["rooms"] or r.get("partOf") in out["rooms"]

    def door(room_id):
        r = venue_rooms[room_id]
        for cand in (room_id, r.get("partOf")):
            if cand and f"door-{cand}" in nodes:
                return f"door-{cand}"
        return None

    for rid in venue_rooms:
        if not on_map(rid):
            warnings.append(f"venue room {rid} has no box on the map")
        elif not door(rid):
            errors.append(f"venue room {rid} has no door node")

    sessions = load("sessions.json")
    sessions = sessions["sessions"] if isinstance(sessions, dict) else sessions
    happenings = load("happenings.json")
    if isinstance(happenings, dict):
        happenings = next((v for v in happenings.values() if isinstance(v, list)), [])
    used = {s.get("roomId") for s in sessions} | {
        h.get("roomId") for h in happenings if isinstance(h, dict)}
    used.discard(None)
    used.discard("")
    for rid in sorted(used):
        if rid.lower() in offsite:
            continue
        vid = alias.get(rid.lower())
        if vid is None:
            errors.append(f"roomId {rid} used in data does not resolve to a venue room")
        elif not on_map(vid):
            errors.append(f"roomId {rid} used in data has no box on the map")

    # Reachability from the main entrance.
    adj = {nid: [] for nid in nodes}
    for e in out["edges"]:
        if e["from"] in adj and e["to"] in adj:
            adj[e["from"]].append(e["to"])
            adj[e["to"]].append(e["from"])
    seen = {START} if START in adj else set()
    q = deque(seen)
    while q:
        u = q.popleft()
        for v in adj[u]:
            if v not in seen:
                seen.add(v)
                q.append(v)
    for rid in venue_rooms:
        d = door(rid)
        if d and d not in seen:
            errors.append(f"{d} is not reachable from {START}")
    for nid, n in nodes.items():
        if nid not in seen:
            warnings.append(f"node {nid} is unreachable")
        if n["id"].startswith("door-") and n["id"][5:] not in out["rooms"]:
            warnings.append(f"door node {nid} has no room box")


def debug_png(out, path):
    from PIL import Image, ImageDraw

    im = Image.open(ROOT / IMAGE).convert("RGB")
    d = ImageDraw.Draw(im)
    for r in out["regions"]:
        x, y, w, h = r["rect"]
        d.rectangle([x, y, x + w, y + h], outline=(0, 160, 0), width=4)
    for rid, r in out["rooms"].items():
        d.rectangle([r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"]],
                    outline=(0, 81, 255), width=3)
    nodes = {n["id"]: n for n in out["nodes"]}
    for e in out["edges"]:
        a, b = nodes.get(e["from"]), nodes.get(e["to"])
        if not a or not b:
            continue
        color = (255, 145, 0) if e["kind"] == "walk" else (254, 25, 255)
        d.line([a["x"], a["y"], b["x"], b["y"]], fill=color,
               width=3 if e["kind"] == "walk" else 2)
    for n in out["nodes"]:
        r = 6 if n["kind"] == "junction" else 9
        d.ellipse([n["x"] - r, n["y"] - r, n["x"] + r, n["y"] + r],
                  fill=(236, 12, 67))
    im.save(path)


def main():
    warnings, errors = [], []
    parts = []
    for name in ("map_salt_palace.json", "map_hyatt.json"):
        p = DATA / name
        if not p.exists():
            raise SystemExit(f"missing {p}")
        parts.append((name.replace("map_", "").replace(".json", ""), load(name)))
    regions, rooms, nodes, edges = merge(parts, warnings)
    w, h = image_size()
    order = list(REGIONS)
    out = {
        "image": IMAGE,
        "width": w,
        "height": h,
        "credit": "Venue map: KubeCon + CloudNativeCon / Linux Foundation",
        "sourceUrl": "https://events.linuxfoundation.org/kcna26-venue-map",
        "regions": sorted(regions.values(),
                          key=lambda r: order.index(r["id"]) if r["id"] in order else 99),
        "rooms": {k: rooms[k] for k in sorted(rooms)},
        "nodes": list(nodes.values()),
        "edges": edges,
    }
    validate(out, errors, warnings)
    for wmsg in warnings:
        print("warning:", wmsg)
    for emsg in errors:
        print("error:", emsg)
    with open(DATA / "official_map.json", "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(f"wrote official_map.json: {len(out['regions'])} regions, "
          f"{len(out['rooms'])} rooms, {len(out['nodes'])} nodes, {len(out['edges'])} edges")
    if "--debug" in sys.argv:
        debug_png(out, sys.argv[sys.argv.index("--debug") + 1])
    if errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
