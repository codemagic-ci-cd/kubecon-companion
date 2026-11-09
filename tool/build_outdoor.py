#!/usr/bin/env python3
"""Build assets/data/outdoor.json: a small walking graph of downtown Salt Lake City for
interactive outdoor directions from the Salt Palace to the off-site venues in venue.json.

Source: OpenStreetMap via the Overpass API (data (c) OpenStreetMap contributors, ODbL).
Raw responses are cached in tool/osm_raw/ (gitignored); pass --refresh to re-fetch.

Output (minified JSON):
  attribution  "(c) OpenStreetMap contributors"
  bbox         [minLat, minLng, maxLat, maxLng]
  nodes        [[lat, lng], ...]               index = node id, 6 decimals
  edges        [[a, b, nameIndex, kind], ...]  undirected; nameIndex -1 = unnamed;
               kind 0 street, 1 footway/path/pedestrian, 2 crossing, 3 steps
  names        street names referenced by edges
  labels       [{name, lat, lng, angle}]       angle in degrees, 0 = text runs west->east,
               positive = clockwise on a north-up map, range (-90, 90]
  buildings    [{name, kind: venue|destination|landmark, outline: [[lat, lng], ...]}]
  venueExits   [{id, label, lat, lng, node}]    id = official_map.json node id
  destinations {"<offsite id>": {node, lat, lng}}

Routing: weight each edge by length * KIND_COST[kind] (streets x3) so routes use sidewalks.

Unnamed sidewalks inherit the name of the parallel street; crossings take the name of the
street they cross. Chains of degree-2 nodes with the same name and kind are simplified
(Douglas-Peucker, 1.5 m); exits and destinations are spliced into the nearest suitable edge.

  python3 -I tool/build_outdoor.py [--refresh]
"""

import gzip
import json
import math
import sys
import urllib.parse
import urllib.request
from collections import defaultdict, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "assets" / "data"
RAW = ROOT / "tool" / "osm_raw"
OUT = DATA / "outdoor.json"
OVERPASS = "https://overpass-api.de/api/interpreter"
UA = "kubecon-companion-build/1.0"

MARGIN_M = 300
FAR_KM = 4.0
WALK_M_PER_MIN = 80.0
SIMPLIFY_M = 1.5
# Routing cost per metre by edge kind. Downtown sidewalks are mapped as separate footways, so
# road centrelines (kind 0) are penalised: routes follow sidewalks and crosswalks and only use
# a road where no footway exists. Clients should use the same weights.
KIND_COST = {0: 3.0, 1: 1.0, 2: 1.0, 3: 1.2}

# Salt Palace official map entrances (assets/data/official_map.json) linked to the street graph.
EXITS = [
    # id, label, snap street name (None = nearest footway)
    ("sp-entrance-200-south", "200 South entrance", None),
    ("sp-entrance-west-temple", "West Temple entrance", "West Temple"),
    ("sp-l2-east-entrance", "Level 2 West Temple entrance", "West Temple"),
    ("l1-hyatt-mid", "Hyatt Regency lobby", "West Temple"),
]
START = "sp-entrance-200-south"

# Off-site venue -> street its address is on (used to snap to the right frontage) and the
# OSM element of its footprint (None when OSM has no matching building).
DESTINATIONS = {
    "offsite-hyatt-regency": ("West Temple", None),  # footprint drawn as the venue building
    "offsite-ac-hotel-downtown": ("200 South", "way/638610273"),
    "offsite-pierpont-place": ("Pierpont Avenue", "way/227710673"),
    "offsite-hilton-city-center": ("West Temple", "way/33192533"),
    "offsite-kimpton-monaco": ("200 South", "way/172543265"),
    "offsite-edison-house": ("200 West", "way/1317711750"),
    "offsite-le-meridien": ("300 West", "way/1117261600"),  # unnamed hotel way shared with Element
    "offsite-utah-moca": ("West Temple", None),  # inside the Abravanel Hall block, node 2363167405
    "offsite-marriott-downtown-city-creek": ("West Temple", "way/31553521"),
    "offsite-gallivan-center": ("200 South", "way/33193654"),
    "offsite-marriott-city-center": ("State Street", "way/223923170"),
    "offsite-radisson-downtown": ("South Temple", "way/33195045"),
    "offsite-clark-planetarium": ("400 West", None),  # node 11141711596, inside The Gateway
}
VENUE_BUILDINGS = [("Salt Palace Convention Center", "way/33149360"),
                   ("Hyatt Regency Salt Lake City", "way/1150797303")]
LANDMARKS = [("Abravanel Hall", "way/152356335"), ("Delta Center", "way/23335190")]
CHECK_NODES = ["node/2363167405", "node/11032961093", "node/11141711596"]

LABEL_STREETS = ["South Temple", "100 South", "200 South", "300 South", "West Temple",
                 "Main Street", "State Street", "200 West", "300 West", "400 West"]

WALK_HIGHWAYS = ("footway|pedestrian|path|steps|living_street|residential|service|unclassified|"
                 "tertiary|tertiary_link|secondary|secondary_link|primary|primary_link|trunk|"
                 "trunk_link|cycleway|track")
SKIP_SERVICE = {"parking_aisle", "driveway", "drive-through"}


# ------------------------------------------------------------------------------------- geo
def dist(a, b):
    """Metres between (lat, lng) points (equirectangular, fine at city scale)."""
    k = math.cos(math.radians((a[0] + b[0]) / 2))
    dy = (a[0] - b[0]) * 111320.0
    dx = (a[1] - b[1]) * 111320.0 * k
    return math.hypot(dx, dy)


def xy(p, lat0):
    return (p[1] * 111320.0 * math.cos(math.radians(lat0)), p[0] * 111320.0)


def project(p, a, b):
    """Closest point to p on segment ab -> (t, point, distance)."""
    lat0 = p[0]
    px, py = xy(p, lat0)
    ax, ay = xy(a, lat0)
    bx, by = xy(b, lat0)
    dx, dy = bx - ax, by - ay
    L = dx * dx + dy * dy
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L))
    q = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
    return t, q, dist(p, q)


def bearing(a, b):
    """Screen angle of a->b on a north-up map: 0 = east, clockwise positive."""
    x0, y0 = xy(a, a[0])
    x1, y1 = xy(b, a[0])
    return math.degrees(math.atan2(-(y1 - y0), x1 - x0))


def axis_diff(a1, a2):
    d = abs(a1 - a2) % 180
    return min(d, 180 - d)


# --------------------------------------------------------------------------------- fetch
def overpass(query, name, refresh):
    RAW.mkdir(parents=True, exist_ok=True)
    path = RAW / f"{name}.json"
    if refresh or not path.exists():
        print(f"fetching {name} from Overpass ...", file=sys.stderr)
        req = urllib.request.Request(OVERPASS, data=urllib.parse.urlencode({"data": query}).encode(),
                                     headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=180) as r:
            path.write_bytes(r.read())
    return json.loads(path.read_text())


def bboxes_for(offsite, anchor):
    """One bbox around everything within FAR_KM of the venue, plus a small one per far venue."""
    near = [v for v in offsite if dist((v["lat"], v["lng"]), anchor) <= FAR_KM * 1000]
    far = [v for v in offsite if v not in near]
    pts = [(v["lat"], v["lng"]) for v in near] + [anchor]
    dlat = MARGIN_M / 111320.0
    dlng = MARGIN_M / (111320.0 * math.cos(math.radians(anchor[0])))
    boxes = [(min(p[0] for p in pts) - dlat, min(p[1] for p in pts) - dlng,
              max(p[0] for p in pts) + dlat, max(p[1] for p in pts) + dlng)]
    for v in far:
        boxes.append((v["lat"] - dlat, v["lng"] - dlng, v["lat"] + dlat, v["lng"] + dlng))
    return [tuple(round(x, 5) for x in b) for b in boxes], far


# --------------------------------------------------------------------------------- build
def main():
    refresh = "--refresh" in sys.argv
    venue = json.loads((DATA / "venue.json").read_text())
    offsite = venue["offsite"]
    official = json.loads((DATA / "official_map.json").read_text())
    anchors = {n["id"]: n for n in official["nodes"] if "lat" in n}
    start_pt = (anchors[START]["lat"], anchors[START]["lng"])

    missing = [v["id"] for v in offsite if v["id"] not in DESTINATIONS]
    if missing:
        sys.exit(f"no DESTINATIONS config for {missing}")

    boxes, far = bboxes_for(offsite, start_pt)
    for v in far:
        print(f"WARNING: {v['id']} is more than {FAR_KM} km away; separate bbox", file=sys.stderr)
    bstr = ["%.5f,%.5f,%.5f,%.5f" % b for b in boxes]

    q_streets = "[out:json][timeout:90];(" + "".join(
        f'way["highway"~"^({WALK_HIGHWAYS})$"]({s});' for s in bstr) + ");out body;>;out body qt;"
    ids = [o for _, o in DESTINATIONS.values() if o] + [o for _, o in VENUE_BUILDINGS + LANDMARKS] + CHECK_NODES
    q_feat = "[out:json][timeout:60];(" + "".join(
        f"{t}({i});" for t, i in (o.split("/") for o in ids)) + ");out tags geom;"
    streets = overpass(q_streets, "streets", refresh)
    feats = overpass(q_feat, "features", refresh)
    feat = {f"{e['type']}/{e['id']}": e for e in feats["elements"]}

    def in_box(p, pad=0.0):
        return any(b[0] - pad <= p[0] <= b[2] + pad and b[1] - pad <= p[1] <= b[3] + pad for b in boxes)

    # ---- filter ways -> raw edges between OSM node ids
    osm_nodes = {}
    osm_ntags = {}
    for e in streets["elements"]:
        if e["type"] == "node":
            osm_nodes[e["id"]] = (e["lat"], e["lon"])
            if e.get("tags"):
                osm_ntags[e["id"]] = e["tags"]

    def walkable(t):
        hw = t.get("highway")
        foot = t.get("foot")
        if foot == "no":
            return False
        if t.get("access") in ("private", "no") and foot not in ("yes", "designated", "permissive"):
            return False
        if t.get("indoor") == "yes":
            return False
        if hw == "service" and t.get("service") in SKIP_SERVICE:
            return False
        if hw in ("trunk", "trunk_link") and t.get("sidewalk") in ("no", "none"):
            return False
        return True

    def kind_of(t):
        hw = t["highway"]
        if hw == "steps":
            return 3
        if hw == "footway" and t.get("footway") == "crossing":
            return 2
        if hw in ("footway", "pedestrian", "path", "cycleway", "track"):
            return 1
        return 0

    ways = []
    for e in streets["elements"]:
        if e["type"] != "way" or not walkable(e["tags"]):
            continue
        ways.append({"id": e["id"], "nodes": e["nodes"], "tags": e["tags"], "kind": kind_of(e["tags"]),
                     "service": e["tags"]["highway"] == "service", "name": e["tags"].get("name")})

    # ---- names: sidewalks inherit the parallel street, crossings the crossed street
    named_roads = [w for w in ways if w["kind"] == 0 and w["name"]]
    road_segs = []
    for w in named_roads:
        for a, b in zip(w["nodes"], w["nodes"][1:]):
            road_segs.append((osm_nodes[a], osm_nodes[b], w["name"]))
    node_roads = defaultdict(set)
    for w in named_roads:
        for n in w["nodes"]:
            node_roads[n].add(w["name"])

    def nearest_parallel(p, ang, maxd=25.0):
        best = None
        for a, b, nm in road_segs:
            if abs(a[0] - p[0]) > 0.003 and abs(b[0] - p[0]) > 0.003:
                continue
            _, _, d = project(p, a, b)
            if d <= maxd and axis_diff(bearing(a, b), ang) < 20 and (best is None or d < best[0]):
                best = (d, nm)
        return best[1] if best else None

    for w in ways:
        if w["name"] or w["kind"] == 0:
            continue
        pts = [osm_nodes[n] for n in w["nodes"]]
        if w["kind"] == 2:
            crossed = [nm for n in w["nodes"] for nm in node_roads.get(n, ())]
            if crossed:
                w["name"] = max(set(crossed), key=crossed.count)
            continue
        if w["kind"] == 1 and w["tags"].get("footway") in ("sidewalk", None):
            votes = defaultdict(float)
            for a, b in zip(pts, pts[1:]):
                L = dist(a, b)
                if L < 1:
                    continue
                nm = nearest_parallel(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2), bearing(a, b))
                if nm:
                    votes[nm] += L
            total = sum(dist(a, b) for a, b in zip(pts, pts[1:]))
            if votes:
                nm, v = max(votes.items(), key=lambda kv: kv[1])
                if v >= 0.6 * total:
                    w["name"] = nm

    # ---- graph on OSM node ids, clipped to the bboxes (small pad)
    pad = 0.0003
    adj = defaultdict(dict)  # u -> {v: (name, kind, service)}
    for w in ways:
        for a, b in zip(w["nodes"], w["nodes"][1:]):
            if a == b or not (in_box(osm_nodes[a], pad) and in_box(osm_nodes[b], pad)):
                continue
            prev = adj[a].get(b)
            attr = (w["name"], w["kind"], w["service"])
            # keep the most specific attribute if two ways share a segment
            if prev is None or (prev[1] == 0 and attr[1] != 0) or (prev[0] is None and attr[0]):
                adj[a][b] = attr
                adj[b][a] = attr
    coords = dict(osm_nodes)

    def components():
        seen, comps = set(), []
        for s in adj:
            if s in seen:
                continue
            comp, dq = [], deque([s])
            seen.add(s)
            while dq:
                u = dq.popleft()
                comp.append(u)
                for v in adj[u]:
                    if v not in seen:
                        seen.add(v)
                        dq.append(v)
            comps.append(comp)
        return comps

    def keep_largest():
        comps = sorted(components(), key=len, reverse=True)
        main_c = set(comps[0])
        for u in list(adj):
            if u not in main_c:
                for v in list(adj[u]):
                    adj[v].pop(u, None)
                del adj[u]
        return len(comps)

    n_comps = keep_largest()

    # ---- prune dead-end service spurs (service roads only kept where they connect things)
    changed = True
    while changed:
        changed = False
        for u in list(adj):
            if u in adj and len(adj[u]) == 1:
                v, attr = next(iter(adj[u].items()))
                if attr[2]:
                    del adj[u]
                    adj[v].pop(u, None)
                    changed = True
    for u in [u for u in adj if not adj[u]]:
        del adj[u]

    # ---- splice exits and destinations into the nearest suitable edge
    protected = set()
    next_id = [-1]

    def splice(p, street=None, footway_only=False, maxd=150.0):
        best = None
        for u in adj:
            for v, attr in adj[u].items():
                if u > v:
                    continue
                if street and attr[0] != street:
                    continue
                if footway_only and attr[1] == 0:
                    continue
                if attr[1] == 2:  # never end on a crosswalk
                    continue
                t, q, d = project(p, coords[u], coords[v])
                if d <= maxd and (best is None or d < best[0]):
                    best = (d, u, v, t, q)
        if best is None:
            if street or footway_only:
                return splice(p, None, False, maxd * 2)
            raise SystemExit(f"nothing to snap {p} to")
        d, u, v, t, q = best
        if dist(q, coords[u]) < 3:
            n = u
        elif dist(q, coords[v]) < 3:
            n = v
        else:
            n = next_id[0]
            next_id[0] -= 1
            coords[n] = q
            attr = adj[u].pop(v)
            adj[v].pop(u)
            adj[u][n] = adj[n][u] = attr
            adj[v][n] = adj[n][v] = attr
        protected.add(n)
        return n, d

    exits = []
    for eid, label, street in EXITS:
        a = anchors[eid]
        p = (a["lat"], a["lng"])
        n, d = splice(p, street, footway_only=street is None)
        exits.append({"id": eid, "label": label, "lat": a["lat"], "lng": a["lng"], "_n": n, "_d": d})
    dests = {}
    for v in offsite:
        street, _ = DESTINATIONS[v["id"]]
        p = (v["lat"], v["lng"])
        n, d = splice(p, street)
        dests[v["id"]] = {"lat": v["lat"], "lng": v["lng"], "_n": n, "_d": d}

    # ---- simplify degree-2 chains with the same name+kind (Douglas-Peucker)
    def attr_key(a):
        return (a[0], a[1])

    def is_junction(u):
        if u in protected or len(adj[u]) != 2:
            return True
        (a1, a2) = list(adj[u].values())
        return attr_key(a1) != attr_key(a2)

    def rdp(pts, tol):
        if len(pts) < 3:
            return [0, len(pts) - 1]
        a, b = pts[0], pts[-1]
        dmax, imax = 0.0, 0
        for i in range(1, len(pts) - 1):
            _, _, d = project(pts[i], a, b)
            if d > dmax:
                dmax, imax = d, i
        if dmax <= tol:
            return [0, len(pts) - 1]
        left = rdp(pts[:imax + 1], tol)
        right = rdp(pts[imax:], tol)
        return left[:-1] + [i + imax for i in right]

    final_edges = set()
    visited = set()
    for u in list(adj):
        if not is_junction(u):
            continue
        for v in adj[u]:
            if (u, v) in visited:
                continue
            chain = [u, v]
            attr = adj[u][v]
            visited.add((u, v))
            visited.add((v, u))
            while not is_junction(chain[-1]):
                nxt = [w for w in adj[chain[-1]] if w != chain[-2]][0]
                visited.add((chain[-1], nxt))
                visited.add((nxt, chain[-1]))
                chain.append(nxt)
            keep = rdp([coords[n] for n in chain], SIMPLIFY_M)
            kept = [chain[i] for i in keep]
            for a, b in zip(kept, kept[1:]):
                if a != b:
                    final_edges.add((min(a, b), max(a, b), attr[0], attr[1]))
    # pure cycles without any junction are ignored (none expected in a street grid)

    # ---- index
    used = sorted({a for e in final_edges for a in e[:2]}, key=lambda n: (coords[n][0], coords[n][1]))
    idx = {n: i for i, n in enumerate(used)}
    names = sorted({e[2] for e in final_edges if e[2]})
    nidx = {nm: i for i, nm in enumerate(names)}
    nodes_out = [[round(coords[n][0], 6), round(coords[n][1], 6)] for n in used]
    edges_out = sorted([idx[a], idx[b], nidx[nm] if nm else -1, k] for a, b, nm, k in final_edges)
    edges_out = [e if e[0] < e[1] else [e[1], e[0], e[2], e[3]] for e in edges_out]
    edges_out.sort()

    # ---- labels: block-length street segments, one near the venue and one farther out
    g_adj = defaultdict(list)
    for a, b, nmi, k in edges_out:
        g_adj[a].append(b)
        g_adj[b].append(a)
    labels = []
    venue_c = (40.7672, -111.8962)
    for nm in LABEL_STREETS:
        if nm not in nidx:
            continue
        segs = [(e[0], e[1]) for e in edges_out if e[2] == nidx[nm] and e[3] == 0]
        segs = [(a, b) for a, b in segs if dist(nodes_out[a], nodes_out[b]) >= 40]
        if not segs:
            continue
        segs.sort(key=lambda s: dist(venue_c, ((nodes_out[s[0]][0] + nodes_out[s[1]][0]) / 2,
                                               (nodes_out[s[0]][1] + nodes_out[s[1]][1]) / 2)))
        picks = [segs[0]]
        for s in segs[1:]:
            m = ((nodes_out[s[0]][0] + nodes_out[s[1]][0]) / 2, (nodes_out[s[0]][1] + nodes_out[s[1]][1]) / 2)
            if all(dist(m, ((nodes_out[p[0]][0] + nodes_out[p[1]][0]) / 2,
                            (nodes_out[p[0]][1] + nodes_out[p[1]][1]) / 2)) > 450 for p in picks):
                picks.append(s)
            if len(picks) == 2:
                break
        for a, b in picks:
            pa, pb = nodes_out[a], nodes_out[b]
            ang = round(bearing(pa, pb))
            if ang > 90:
                ang -= 180
            elif ang <= -90:
                ang += 180
            labels.append({"name": nm, "lat": round((pa[0] + pb[0]) / 2, 6),
                           "lng": round((pa[1] + pb[1]) / 2, 6), "angle": ang})

    # ---- buildings
    def outline(ref):
        e = feat.get(ref)
        if not e:
            print(f"WARNING: {ref} missing from features", file=sys.stderr)
            return None
        geom = e.get("geometry") or []
        pts = [(g["lat"], g["lon"]) for g in geom]
        if len(pts) > 2 and pts[0] == pts[-1]:
            pts = pts[:-1]
        keep = rdp(pts + [pts[0]], 0.8)
        pts = [pts[i % len(pts)] for i in keep][:-1]
        return [[round(p[0], 6), round(p[1], 6)] for p in pts]

    buildings = []
    for nm, ref in VENUE_BUILDINGS:
        buildings.append({"name": nm, "kind": "venue", "outline": outline(ref)})
    by_id = {v["id"]: v for v in offsite}
    for oid, (_, ref) in DESTINATIONS.items():
        if ref:
            buildings.append({"name": by_id[oid]["name"], "kind": "destination", "outline": outline(ref)})
    for nm, ref in LANDMARKS:
        buildings.append({"name": nm, "kind": "landmark", "outline": outline(ref)})
    buildings = [b for b in buildings if b["outline"]]

    out = {
        "attribution": "© OpenStreetMap contributors",
        "bbox": [round(min(b[0] for b in boxes), 5), round(min(b[1] for b in boxes), 5),
                 round(max(b[2] for b in boxes), 5), round(max(b[3] for b in boxes), 5)],
        "nodes": nodes_out,
        "edges": edges_out,
        "names": names,
        "labels": labels,
        "buildings": buildings,
        "venueExits": [{"id": x["id"], "label": x["label"], "lat": x["lat"], "lng": x["lng"],
                        "node": idx[x["_n"]]} for x in exits],
        "destinations": {k: {"node": idx[d["_n"]], "lat": d["lat"], "lng": d["lng"]} for k, d in dests.items()},
    }
    raw = json.dumps(out, separators=(",", ":"), ensure_ascii=False).encode()
    OUT.write_bytes(raw)

    # ---- validate + report
    wadj = defaultdict(list)
    for a, b, nmi, k in edges_out:
        d = dist(nodes_out[a], nodes_out[b])
        wadj[a].append((b, d * KIND_COST[k], d))
        wadj[b].append((a, d * KIND_COST[k], d))

    import heapq

    def dijkstra(src):
        """Cheapest routes by KIND_COST -> {node: walked metres along that route}."""
        best = {src: 0.0}
        walked = {src: 0.0}
        pq = [(0.0, src)]
        while pq:
            d, u = heapq.heappop(pq)
            if d > best[u]:
                continue
            for v, w, m in wadj[u]:
                nd = d + w
                if nd < best.get(v, 1e18):
                    best[v] = nd
                    walked[v] = walked[u] + m
                    heapq.heappush(pq, (nd, v))
        return walked

    ok = True
    reach = {}
    for x in out["venueExits"]:
        reach[x["id"]] = dijkstra(x["node"])
        for k, d in out["destinations"].items():
            if d["node"] not in reach[x["id"]]:
                print(f"UNREACHABLE: {k} from {x['id']}", file=sys.stderr)
                ok = False
    print(f"bbox {out['bbox']}  ({len(boxes)} box(es); far venues: {[v['id'] for v in far]})")
    print(f"osm ways used {len(ways)}, raw components {n_comps}; nodes {len(nodes_out)}, edges {len(edges_out)}, "
          f"names {len(names)}, labels {len(labels)}, buildings {len(buildings)}")
    kinds = defaultdict(int)
    for e in edges_out:
        kinds[e[3]] += 1
    print(f"edge kinds {dict(sorted(kinds.items()))}; unnamed {sum(1 for e in edges_out if e[2] < 0)}")
    print(f"size raw {len(raw)} B, gzip {len(gzip.compress(raw, 9))} B")
    for x in exits:
        print(f"exit {x['id']}: snapped {x['_d']:.0f} m -> node {idx[x['_n']]}")
    print(f"{'destination':40s} {'snap':>5s} {'route':>7s} {'~min':>5s} {'json':>5s}")
    s = reach[START]
    for k, d in out["destinations"].items():
        m = s.get(d["node"])
        wm = by_id[k]["walkMinutes"]
        est = m / WALK_M_PER_MIN
        flag = "  <-- check" if abs(est - wm) > max(3, 0.5 * wm) else ""
        print(f"{k:40s} {dests[k]['_d']:4.0f}m {m:6.0f}m {est:5.1f} {wm:5d}{flag}")
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
