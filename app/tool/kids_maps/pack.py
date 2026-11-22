"""Packs simplified GeoJSON into the Kids Portal's map assets.

Each region: name, extra fields, its rings as flat [x, y, x, y, ...]
integers in a box 1000 wide, a label point and its area."""
import json, math, sys

RAW = sys.argv[1]
OUT = sys.argv[2]

US = {  # abbreviation, capital, region
 'Alabama':('AL','Montgomery','South'),'Alaska':('AK','Juneau','West'),'Arizona':('AZ','Phoenix','West'),
 'Arkansas':('AR','Little Rock','South'),'California':('CA','Sacramento','West'),'Colorado':('CO','Denver','West'),
 'Connecticut':('CT','Hartford','Northeast'),'Delaware':('DE','Dover','South'),'Florida':('FL','Tallahassee','South'),
 'Georgia':('GA','Atlanta','South'),'Hawaii':('HI','Honolulu','West'),'Idaho':('ID','Boise','West'),
 'Illinois':('IL','Springfield','Midwest'),'Indiana':('IN','Indianapolis','Midwest'),'Iowa':('IA','Des Moines','Midwest'),
 'Kansas':('KS','Topeka','Midwest'),'Kentucky':('KY','Frankfort','South'),'Louisiana':('LA','Baton Rouge','South'),
 'Maine':('ME','Augusta','Northeast'),'Maryland':('MD','Annapolis','South'),'Massachusetts':('MA','Boston','Northeast'),
 'Michigan':('MI','Lansing','Midwest'),'Minnesota':('MN','Saint Paul','Midwest'),'Mississippi':('MS','Jackson','South'),
 'Missouri':('MO','Jefferson City','Midwest'),'Montana':('MT','Helena','West'),'Nebraska':('NE','Lincoln','Midwest'),
 'Nevada':('NV','Carson City','West'),'New Hampshire':('NH','Concord','Northeast'),'New Jersey':('NJ','Trenton','Northeast'),
 'New Mexico':('NM','Santa Fe','West'),'New York':('NY','Albany','Northeast'),'North Carolina':('NC','Raleigh','South'),
 'North Dakota':('ND','Bismarck','Midwest'),'Ohio':('OH','Columbus','Midwest'),'Oklahoma':('OK','Oklahoma City','South'),
 'Oregon':('OR','Salem','West'),'Pennsylvania':('PA','Harrisburg','Northeast'),'Rhode Island':('RI','Providence','Northeast'),
 'South Carolina':('SC','Columbia','South'),'South Dakota':('SD','Pierre','Midwest'),'Tennessee':('TN','Nashville','South'),
 'Texas':('TX','Austin','South'),'Utah':('UT','Salt Lake City','West'),'Vermont':('VT','Montpelier','Northeast'),
 'Virginia':('VA','Richmond','South'),'Washington':('WA','Olympia','West'),'West Virginia':('WV','Charleston','South'),
 'Wisconsin':('WI','Madison','Midwest'),'Wyoming':('WY','Cheyenne','West'),
 'District of Columbia':('DC','Washington','South'),
}
INDIA = {  # capital, kind
 'Andhra Pradesh':('Amaravati','State'),'Arunachal Pradesh':('Itanagar','State'),'Assam':('Dispur','State'),
 'Bihar':('Patna','State'),'Chhattisgarh':('Raipur','State'),'Goa':('Panaji','State'),'Gujarat':('Gandhinagar','State'),
 'Haryana':('Chandigarh','State'),'Himachal Pradesh':('Shimla','State'),'Jharkhand':('Ranchi','State'),
 'Karnataka':('Bengaluru','State'),'Kerala':('Thiruvananthapuram','State'),'Madhya Pradesh':('Bhopal','State'),
 'Maharashtra':('Mumbai','State'),'Manipur':('Imphal','State'),'Meghalaya':('Shillong','State'),'Mizoram':('Aizawl','State'),
 'Nagaland':('Kohima','State'),'Odisha':('Bhubaneswar','State'),'Punjab':('Chandigarh','State'),'Rajasthan':('Jaipur','State'),
 'Sikkim':('Gangtok','State'),'Tamil Nadu':('Chennai','State'),'Telangana':('Hyderabad','State'),'Tripura':('Agartala','State'),
 'Uttar Pradesh':('Lucknow','State'),'Uttarakhand':('Dehradun','State'),'West Bengal':('Kolkata','State'),
 'Andaman and Nicobar Islands':('Sri Vijaya Puram','Union territory'),'Chandigarh':('Chandigarh','Union territory'),
 'Dadra and Nagar Haveli and Daman and Diu':('Daman','Union territory'),'Delhi':('New Delhi','Union territory'),
 'Jammu and Kashmir':('Srinagar','Union territory'),'Ladakh':('Leh','Union territory'),
 'Lakshadweep':('Kavaratti','Union territory'),'Puducherry':('Puducherry','Union territory'),
}
WORLD_NAMES = {
 'Antigua and Barb.':'Antigua and Barbuda','Bosnia and Herz.':'Bosnia and Herzegovina','Central African Rep.':'Central African Republic',
 'Dem. Rep. Korea':'North Korea','Republic of Korea':'South Korea','Democratic Republic of the Congo':'DR Congo',
 'Republic of the Congo':'Congo','Dominican Rep.':'Dominican Republic','Eq. Guinea':'Equatorial Guinea',
 'Marshall Is.':'Marshall Islands','S. Sudan':'South Sudan','Solomon Is.':'Solomon Islands',
 'St. Vin. and Gren.':'Saint Vincent and the Grenadines','eSwatini':'Eswatini','Faeroe Islands':'Faroe Islands',
}
# Drawn but not asked about: territories, disputed or tiny places.
NOT_ASKED = set('''Akrotiri|Dhekelia|American Samoa|Anguilla|Aruba|Ashmore and Cartier Is.|Bermuda|Bir Tawil|Br. Indian Ocean Ter.|Brazilian Island|British Virgin Is.|Cayman Is.|Clipperton I.|Cook Is.|Coral Sea Is.|Curaçao|Faeroe Islands|Falkland Is.|Fr. Polynesia|Fr. S. and Antarctic Lands|Gibraltar|Guam|Guantanamo Bay USNB|Guernsey|Heard I. and McDonald Is.|Hong Kong|Indian Ocean Ter.|Isle of Man|Jersey|Macao|Montserrat|N. Mariana Is.|New Caledonia|Niue|Norfolk Island|Pitcairn Is.|Puerto Rico|Saint Helena|Saint-Martin|Scarborough Reef|Sint Maarten|Spratly Is.|St-Barthélemy|St. Pierre and Miquelon|Turks and Caicos Is.|U.S. Minor Outlying Is.|U.S. Virgin Is.|Wallis and Futuna Islands|Åland|S. Geo. and the Is.|Antarctica|Taiwan|Palestine|Greenland'''.split('|'))

def rings_of(geom):
    if geom is None: return []
    if geom['type'] == 'Polygon': return geom['coordinates']
    if geom['type'] == 'MultiPolygon': return [r for p in geom['coordinates'] for r in p]
    return []

def area(r):
    a = 0
    for i in range(len(r) - 1):
        a += r[i][0] * r[i + 1][1] - r[i + 1][0] * r[i][1]
    return a / 2

def centroid(r):
    a = area(r) or 1e-9
    cx = cy = 0
    for i in range(len(r) - 1):
        f = r[i][0] * r[i + 1][1] - r[i + 1][0] * r[i][1]
        cx += (r[i][0] + r[i + 1][0]) * f
        cy += (r[i][1] + r[i + 1][1]) * f
    return cx / (6 * a), cy / (6 * a)

def inside(pt, ring):
    x, y = pt
    c = False
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]; x2, y2 = ring[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c

def edge_dist(pt, ring):
    best = 1e18
    n = len(ring)
    for i in range(n):
        (x1, y1), (x2, y2) = ring[i], ring[(i + 1) % n]
        dx, dy = x2 - x1, y2 - y1
        t = 0 if dx == dy == 0 else max(0, min(1, ((pt[0] - x1) * dx + (pt[1] - y1) * dy) / (dx * dx + dy * dy)))
        px, py = x1 + t * dx, y1 + t * dy
        best = min(best, (pt[0] - px) ** 2 + (pt[1] - py) ** 2)
    return best ** 0.5

def inner_point(ring):
    # The point deepest inside the ring (on a fine grid): where to tap.
    xs = [p[0] for p in ring]; ys = [p[1] for p in ring]
    best, bd = None, -1
    n = 24
    for i in range(n + 1):
        for j in range(n + 1):
            pt = (min(xs) + (max(xs) - min(xs)) * i / n, min(ys) + (max(ys) - min(ys)) * j / n)
            if inside(pt, ring):
                d = edge_dist(pt, ring)
                if d > bd: best, bd = pt, d
    return best if best else centroid(ring + [ring[0]])

def pack(features, project, extra, title, credit, flip_y):
    pts = []
    regions = []
    for f in features:
        rings = [[project(x, y) for x, y in r] for r in rings_of(f['geometry'])]
        if flip_y:
            rings = [[(x, -y) for x, y in r] for r in rings]
        regions.append((f, rings))
        for r in rings:
            pts += r
    minx = min(p[0] for p in pts); maxx = max(p[0] for p in pts)
    miny = min(p[1] for p in pts); maxy = max(p[1] for p in pts)
    k = 1000 / (maxx - minx)
    h = round((maxy - miny) * k)
    out = []
    for f, rings in regions:
        e = extra(f['properties'])
        if e is None: continue
        q = []
        for r in rings:
            rr = [(round((x - minx) * k), round((y - miny) * k)) for x, y in r]
            # Drop repeats and rings too small to see.
            ded = [rr[0]] + [p for i, p in enumerate(rr[1:], 1) if p != rr[i - 1]]
            if len(ded) < 4 or abs(area(ded + [ded[0]])) < 1.5: continue
            q.append(ded)
        if not q: continue
        big = max(q, key=lambda r: abs(area(r + [r[0]])))
        cx, cy = inner_point(big)
        e['p'] = [[c for p in r for c in p] for r in q]
        e['c'] = [round(cx), round(cy)]
        e['a'] = round(sum(abs(area(r + [r[0]])) for r in q))
        out.append(e)
    out.sort(key=lambda e: e['n'])
    return {'title': title, 'credit': credit, 'w': 1000, 'h': h, 'regions': out}

def load(name):
    return json.load(open(f'{RAW}/{name}'))['features']

usa = pack(load('usa_s.geojson'), lambda x, y: (x, y),
    lambda p: {'n': p['name'], 'id': US[p['name']][0], 'cap': US[p['name']][1], 'g': US[p['name']][2], 'q': p['name'] != 'District of Columbia'},
    'United States', 'U.S. Census Bureau state boundaries, via us-atlas (ISC licence).', False)

lat0 = math.cos(math.radians(22))
india = pack(load('india_s.geojson'), lambda x, y: (x * lat0, y),
    lambda p: {'n': p['name'], 'cap': INDIA[p['name']][0], 'g': INDIA[p['name']][1], 'q': True},
    'India', 'India boundaries by the DataMeet India community (CC BY 4.0), updated for the states and union territories since 2019.', True)

def world_extra(p):
    raw = p['NAME_LONG']
    name = WORLD_NAMES.get(raw, raw)
    cont = p['CONTINENT']
    if cont.startswith('Seven seas'): cont = 'Africa' if raw in ('Seychelles', 'Mauritius', 'Saint Helena') else 'Asia' if raw == 'Maldives' else cont
    return {'n': name, 'iso': p['ISO_A2_EH'], 'g': cont, 'q': raw not in NOT_ASKED}
world = pack(load('world_s.geojson'), lambda x, y: (x, y), world_extra,
    'World', 'Natural Earth (public domain), country boundaries as India shows them.', True)

for name, data in [('usa', usa), ('india', india), ('world', world)]:
    s = json.dumps(data, separators=(',', ':'), ensure_ascii=False)
    open(f'{OUT}/{name}.json', 'w').write(s)
    print(name, len(data['regions']), 'regions', len(s), 'bytes', 'h', data['h'], 'asked', sum(1 for r in data['regions'] if r['q']))
