#!/usr/bin/env python3
"""4B-8's offline reduction: the three pinned building/furniture/castle
answers, plus q4's residential ways and six place nodes, into buildings.json.
The 4B-7 landcover file deliberately DROPPED residential polygons; we recover
those exact q4 ways in its outer/inner schema, without rewriting landcover.
Selection means a residential polygon intersects an 800 m village disc, then
keeps every building whose area centroid is in that polygon (holes excluded).
Grandstands also qualify within 800 m of the Nordschleife or a named village.
Eifelstadion 429774835 is absent from all supplied answers: reported, not made up.

Projection is landcover.py's exact SkeletonLoader.wgs84_to_local port. Closed
rings retain their closing point; coordinates and area centroids round to mm.
Sorted keys/OSM ids, no generation clock, no network or third party packages.
Manifest answer hashes are verified before writing. Query hashes are calculated
from the pinned .ql files (q5/q6's manifest only holds the aggregate query_sha).
The independent rule-count header also reproduces the hash placements;
B-road grade-separated loop crossings are omitted like RoadBuilder's
right-of-way pass. These counts pin this snapshot, not a general bridge
solver (the runtime retains the existing height-based road ruling).
The audit measures footprint boundaries, not merely centres, against the frozen
fixtures; recorded OSM barriers NEVER choose the Ring's rule-placed F1 rails.
Run: python3 tools/world/buildings.py --snapshot <4B8 folder> --landcover-store
<4B2 folder> --out data/regions/eifel_ring/buildings.json
"""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import sys
sys.dont_write_bytecode = True
import landcover as lc

VILLAGES = ['Adenau', 'Nürburg', 'Breidscheid', 'Meuspath', 'Herschbroich', 'Quiddelbach']
RADIUS = 800.0  # 4B-8 brief's village selection

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def centroid(r):
    cross = [a[0]*b[1]-b[0]*a[1] for a,b in zip(r,r[1:])]
    area = sum(cross)
    if abs(area) < 1e-9:
        return [lc.rounded(sum(p[k] for p in r[:-1])/(len(r)-1)) for k in range(2)]
    return [lc.rounded(sum((a[k]+b[k])*c for a,b,c in zip(r,r[1:],cross))/(3*area)) for k in range(2)]

def inside(p,r):
    x,y=p; hit=False
    for a,b in zip(r,r[1:]):
        if (a[1]>y)!=(b[1]>y) and x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]: hit=not hit
    return hit

def point_segment(p,a,b):
    dx,dy=b[0]-a[0],b[1]-a[1]; den=dx*dx+dy*dy
    t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/den)) if den else 0
    return math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy)

def crosses(a,b,c,d):
    def orient(p,q,r): return (q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0])
    return orient(a,b,c)*orient(a,b,d)<0 and orient(c,d,a)*orient(c,d,b)<0

def line_distance(a,b,c,d):
    return 0 if crosses(a,b,c,d) else min(point_segment(a,c,d),point_segment(b,c,d),point_segment(c,a,b),point_segment(d,a,b))

def ring_distance(p,r):
    return 0 if inside(p,r) else min(point_segment(p,a,b) for a,b in zip(r,r[1:]))

def bounds(r): return [min(p[0] for p in r),min(p[1] for p in r),max(p[0] for p in r),max(p[1] for p in r)]
def in_box(p,b): return b[0]<=p[0]<=b[2] and b[1]<=p[1]<=b[3]
def ring_of(e):
    r=lc.way_ring(e)
    return lc.project_ring(r) if r else None

def validate_buildings(d):
    """One line per fault, also mirrored by the runtime loader."""
    faults=[]; seen=set(); counts=Counter()
    for r in d.get('buildings',[]):
        key=r.get('osm'); ring=r.get('polygon',[])
        if key in seen: faults.append(f'duplicate building {key}')
        seen.add(key)
        if len(ring)<4 or ring[0]!=ring[-1]: faults.append(f'building {key}: open/short polygon')
        if r.get('element') not in ['B0','B1','B2','B3','B4','B5']: faults.append(f'building {key}: invalid element')
        counts[r.get('element')]+=1
        for p in ring:
            if len(p)!=2 or any(not math.isfinite(v) or abs(v-round(v,3))>1e-8 for v in p): faults.append(f'building {key}: not a millimetre point')
    if dict(sorted(counts.items()))!=d.get('counts',{}).get('classes'): faults.append('counts.classes disagrees with records')
    if len(d.get('poles',[]))!=d.get('counts',{}).get('poles'): faults.append('counts.poles disagrees with records')
    return faults

def fnv1a(text):
    h=0x811c9dc5
    for c in text.encode(): h=((h^c)*0x01000193)&0xffffffff
    return h

def hash_unit(osm,purpose,index=0):
    return fnv1a(f'{fnv1a("eifel_ring")}:{osm}:{purpose}:{index}')/4294967296.0

def rule_counts(sk, residential, places):
    """Independent arithmetic for the runtime's catalogue/stone placement pins.
    Uses only drape-covered skeleton roads, and the runtime's stateless FNV.
    Geometry heights are not baked: they remain the profile's worker job.
    """
    catalogue={e['id']:e for f in ['F','R'] for e in json.load(open('configs/elements/'+f+'.json'))['elements']}
    drape=json.load(open('data/regions/eifel_ring/drape.json'))
    covered={s['id'] for s in drape['segments'] if s.get('covered')}
    # The existing road builder removes grade-separated crossings from
    # its single-valued profile. These three B-road bridge underpasses
    # are selected geometrically here, never by OSM id. Junctions that
    # actually join the loop are retained. This count pass only needs the
    # B-road subset; their differing layers certify the grade separation.
    loop_ids=set(next(l for l in sk['loops'] if l['id']=='nordschleife')['segments'])
    joined={i for j in sk['junctions'] if any(i in loop_ids for i in j['segments']) for i in j['segments']}
    loop_roads=[s for s in sk['segments'] if s['id'] in loop_ids]
    excluded=[]
    for road in sk['segments']:
        if road['class'] not in ['primary','secondary'] or road['id'] not in covered or road['id'] in joined:continue
        for circuit in loop_roads:
            if road.get('layer','0')==circuit.get('layer','0'):continue
            rb=bounds(road['points']);cb=bounds(circuit['points'])
            if max(rb[0],cb[0])>min(rb[2],cb[2]) or max(rb[1],cb[1])>min(rb[3],cb[3]):continue
            if any(crosses(a,b,c,d) for a,b in zip(road['points'],road['points'][1:]) for c,d in zip(circuit['points'],circuit['points'][1:])):
                excluded.append(road['id']);covered.remove(road['id']);break
    adenau=next(p['position'] for p in places if p['name']=='Adenau')
    rings=[(r['outer'][0],bounds(r['outer'][0])) for r in residential]
    result={'delineators':0,'kerb_segments':0,'parked_cars':0,'parking_ceiling':0}
    loop=set(next(l for l in sk['loops'] if l['id']=='nordschleife')['segments']); loop_length=0
    for segment in sk['segments']:
        if segment['id'] not in covered: continue
        pts=segment['points']; chain=[0.0]
        for a,b in zip(pts,pts[1:]): chain.append(chain[-1]+math.dist(a,b))
        length=chain[-1]
        if segment['id'] in loop: loop_length+=length
        def point(s):
            for i in range(1,len(chain)):
                if chain[i]>=s:
                    u=(s-chain[i-1])/(chain[i]-chain[i-1]);return [pts[i-1][k]+u*(pts[i][k]-pts[i-1][k]) for k in [0,1]]
            return pts[-1]
        if segment['class'] in ['primary','secondary']:
            spacing=catalogue['F9']['stone_parameters']['spacing_m'];s=spacing/2;index=0
            while s<length:
                at=max(0,min(length,s-10+20*hash_unit(segment['osm_way'],'delineator:'+segment['id'],index)))
                p=point(at)
                if not any(in_box(p,b) and inside(p,r) for r,b in rings):result['delineators']+=2
                s+=spacing;index+=1
        if segment['class']!='residential':continue
        if not any(math.dist(point((a+b)/2),adenau)<=RADIUS for a,b in zip(chain,chain[1:])):continue
        result['kerb_segments']+=1
        for slot in range(int(length//100)):
            if math.dist(point((slot+0.5)*100),adenau)>RADIUS:continue
            result['parking_ceiling']+=2
            mean=catalogue['F15']['varies']['count_per_100_m']['default']
            result['parked_cars']+=min(2,int(hash_unit(segment['osm_way'],'park_count:'+segment['id'],slot)*(2*mean+1)))
    result['guardrail_posts']=2*math.ceil(loop_length/catalogue['F1']['stone_parameters']['post_spacing_m'])
    result['guardrail_spans']=result['guardrail_posts']
    return result

def build(snapshot,store):
    manifest=json.loads((snapshot/'manifest.json').read_text()); answers={}; provenance={}
    for name in ['q5_buildings','q6_furniture','q7_castle']:
        f=snapshot/(name+'.json'); m=manifest.get(name,manifest['queries'].get(name))
        assert sha(f)==m['sha256'], f'{f}: manifest hash mismatch'
        q=snapshot/(name+'.ql'); qsha=sha(q)
        provenance[name]={'answer_file':f.name,'answer_sha256':m['sha256'],'query_file':q.name,'query_sha256':qsha,'elements':m['elements']}
        if 'query_sha256' in m:
            provenance[name]['manifest_query_sha256']=m['query_sha256']
            provenance[name]['query_hash_matches_manifest']=qsha==m['query_sha256']
        answers[name]=json.loads(f.read_text())['elements']
    places_file=store/'q4_landcover_part6_places.json'; residential_file=store/'q4_landcover_part1_landuse_ways.json'
    places=[]
    for e in json.loads(places_file.read_text())['elements']:
        if e.get('tags',{}).get('name') in VILLAGES:
            places.append({'osm':e['id'],'name':e['tags']['name'],'position':list(lc.project(e['lat'],e['lon']))})
    assert len(places)==6
    places.sort(key=lambda p:p['name']); residential=[]
    for e in json.loads(residential_file.read_text())['elements']:
        if e.get('tags',{}).get('landuse')!='residential': continue
        r=ring_of(e)
        if r:
            residential.append({'osm':e['id'],'type':'way','kind':'residential','outer':[r],'inner':[], 'villages':[p['name'] for p in places if ring_distance(p['position'],r)<=RADIUS]})
    residential.sort(key=lambda r:r['osm'])
    selected=[(r['outer'][0],bounds(r['outer'][0])) for r in residential if r['villages']]
    sk=json.loads(Path('data/regions/eifel_ring/skeleton.json').read_text())
    segs={s['id']:s for s in sk['segments']}; loop=next(l for l in sk['loops'] if l['id']=='nordschleife')
    chords=[(a,b) for sid in loop['segments'] for a,b in zip(segs[sid]['points'],segs[sid]['points'][1:])]
    all_buildings=[]; kept=[]
    for e in answers['q5_buildings']:
        r=ring_of(e)
        if not r: continue
        c=centroid(r); tags={k:v for k,v in e.get('tags',{}).items() if k in ['building','building:levels','roof:shape']}
        cls={'farm':'B1','barn':'B1','farm_auxiliary':'B1','church':'B2','grandstand':'B4','industrial':'B5','warehouse':'B5'}.get(tags.get('building'),'B0')
        rec={'osm':e['id'],'polygon':r,'centroid':c,'tags':tags,'element':cls}; all_buildings.append(rec)
        selected_house=any(in_box(c,b) and inside(c,ring) for ring,b in selected)
        grandstand=cls=='B4' and (any(math.dist(c,p['position'])<=RADIUS for p in places) or min(point_segment(c,a,b) for a,b in chords)<=RADIUS)
        if selected_house or grandstand: kept.append(rec)
    castle=next(e for e in answers['q7_castle'] if e['id']==31010481); r=ring_of(castle)
    kept.append({'osm':castle['id'],'polygon':r,'centroid':centroid(r),'element':'B3','tags':{}})
    poles=[]; barriers=Counter()
    for e in answers['q6_furniture']:
        tags=e.get('tags',{})
        if e['type']=='node' and tags.get('power')=='pole': poles.append({'osm':e['id'],'element':'F4','position':list(lc.project(e['lat'],e['lon']))})
        if e['type']=='way' and tags.get('barrier') in ['guard_rail','wall','fence','retaining_wall']: barriers[tags['barrier']]+=1
    approach=segs['683303211-0']['points']; grass=[6120,-2640]
    grass_dist=min(ring_distance(grass,b['polygon']) for b in all_buildings)
    approach_dist=min(min(line_distance(a,b,c,d) for a,b in zip(r['polygon'],r['polygon'][1:]) for c,d in zip(approach,approach[1:])) for r in all_buildings)
    # Rail-to-raceway distance: vertices to all raceway chords AND the reverse
    # endpoints, exact segment distances with bounding-box pruning.
    race_chords=[(a,b) for s in sk['segments'] if s['class']=='raceway' for a,b in zip(s['points'],s['points'][1:])]
    rail_min=math.inf
    loop_min=math.inf
    loop_rail=None
    for e in answers['q6_furniture']:
        if e.get('tags',{}).get('barrier')!='guard_rail': continue
        pts=[lc.project(p['lat'],p['lon']) for p in e.get('geometry',[])]
        for a,b in zip(pts,pts[1:]):
            box=bounds([a,b])
            for c,d in race_chords:
                other=bounds([c,d])
                dx=max(0,box[0]-other[2],other[0]-box[2]); dz=max(0,box[1]-other[3],other[1]-box[3])
                if math.hypot(dx,dz)<rail_min: rail_min=min(rail_min,line_distance(a,b,c,d))
        for a,b in zip(pts,pts[1:]):
            box=bounds([a,b])
            for c,d in chords:
                other=bounds([c,d]);dx=max(0,box[0]-other[2],other[0]-box[2]);dz=max(0,box[1]-other[3],other[1]-box[3])
                if math.hypot(dx,dz)<loop_min:
                    distance=line_distance(a,b,c,d)
                    if distance<loop_min:loop_min=distance;loop_rail=e['id']
    d={'region':'eifel_ring','pipeline_version':1,'provenance':{'osm_base':manifest['osm_base'],'query_sha':manifest['query_sha'],'answers':provenance,'q4_sources':{p.name:sha(p) for p in [places_file,residential_file]},'projection':'landcover.py: SkeletonLoader.wgs84_to_local, EPSG:25832, mm rounded','selection':'residential polygon intersects an 800 m named-place disc; footprint area centroid inside; grandstands additionally within 800 m of the Nordschleife','missing':['Eifelstadion way 429774835 absent from supplied q5/q6/q7 and q4 residential answers']},'counts':{'classes':dict(sorted(Counter(r['element'] for r in kept).items())),'buildings':len(kept),'poles':len(poles),'residential':len(residential),'selected_residential':len(selected),'recorded_barriers':dict(sorted(barriers.items()))},'audit':{'q5_ways':len(answers['q5_buildings']),'grass_footprint_min_m':round(grass_dist,3),'grass_within_120_m':sum(ring_distance(grass,b['polygon'])<=120 for b in all_buildings),'approach_footprint_min_m':round(approach_dist,3),'approach_within_15_m':sum(any(line_distance(a,b,c,d)<=15 for a,b in zip(r['polygon'],r['polygon'][1:]) for c,d in zip(approach,approach[1:])) for r in all_buildings),'osm_guardrail_raceway_min_m':round(rail_min,3),'osm_guardrail_loop_min_m':round(loop_min,3),'nearest_loop_guardrail_way':loop_rail},'places':places,'residential':residential,'buildings':sorted(kept,key=lambda b:b['osm']),'poles':sorted(poles,key=lambda p:p['osm'])}
    d['counts']['rule_placements']=rule_counts(sk,residential,places)
    d['provenance']['rule_inputs']={f:sha(Path(f)) for f in ['data/regions/eifel_ring/skeleton.json','data/regions/eifel_ring/drape.json','configs/elements/F.json','configs/elements/R.json']}
    assert not validate_buildings(d), validate_buildings(d)
    return d

def main():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('--snapshot',type=Path,required=True);p.add_argument('--landcover-store',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    a=p.parse_args(); d=build(a.snapshot,a.landcover_store)
    a.out.write_text(json.dumps(d,sort_keys=True,separators=(',',':'),ensure_ascii=False)+'\n')
    print(json.dumps({'counts':d['counts'],'audit':d['audit']},indent=2))
if __name__=='__main__': main()
