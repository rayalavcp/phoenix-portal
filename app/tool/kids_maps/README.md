# Rebuilding the Kids Portal maps

`assets/maps/*.json` come from public map data (credits in
`assets/maps/SOURCES.md`). To rebuild them, in an empty folder:

```bash
npm i mapshaper@0.6
# Sources
curl -LO https://raw.githubusercontent.com/datameet/maps/master/website/docs/data/geojson/states.geojson   # India states (CC BY 4.0)
for e in shp dbf shx prj; do curl -LO https://raw.githubusercontent.com/datameet/maps/master/Districts/Census_2011/2011_Dist.$e; done
curl -LO https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries_ind.geojson
npm pack us-atlas@3 && tar xzf us-atlas-*.tgz
```

Then simplify (as used for the shipped maps):

```bash
M=node_modules/.bin/mapshaper
# India: Ladakh = Leh + Kargil + the unadministered area north of ~35.1°N;
# the rest of that area goes with Jammu and Kashmir.
$M 2011_Dist.shp -filter 'ST_NM=="Jammu & Kashmir"' -each 'name = (DISTRICT=="Leh (ladakh)"||DISTRICT=="Kargil") ? "Ladakh" : (DISTRICT=="Data Not Available" ? "NA" : "Jammu and Kashmir")' -o jk_tagged.geojson format=geojson
$M jk_tagged.geojson -filter 'name=="NA"' -clip bbox=72,35.1,79,38 -each 'name="Ladakh"' -o na_north.geojson format=geojson
$M jk_tagged.geojson -filter 'name=="NA"' -clip bbox=72,30,79,35.1 -each 'name="Jammu and Kashmir"' -o na_south.geojson format=geojson
$M jk_tagged.geojson -filter 'name!="NA"' -o jk_admin.geojson format=geojson
$M states.geojson -filter 'ST_NM!="Jammu & Kashmir"' -each 'var fix={"Andaman & Nicobar Island":"Andaman and Nicobar Islands","Arunanchal Pradesh":"Arunachal Pradesh","NCT of Delhi":"Delhi","Dadara & Nagar Havelli":"Dadra and Nagar Haveli and Daman and Diu","Daman & Diu":"Dadra and Nagar Haveli and Daman and Diu"}; name = fix[ST_NM] || ST_NM' -filter-fields name -o rest.geojson format=geojson
$M -i rest.geojson jk_admin.geojson na_north.geojson na_south.geojson combine-files -merge-layers force -filter-fields name -dissolve fields=name -simplify 1.2% keep-shapes -o india_s.geojson format=geojson precision=0.001
# World (India's point of view) and USA
$M ne_10m_admin_0_countries_ind.geojson -filter-fields NAME_LONG,CONTINENT,ISO_A2_EH,ADM0_A3 -simplify 1.5% keep-shapes -proj robinson -o world_s.geojson format=geojson precision=1
$M package/states-albers-10m.json -drop target=nation -simplify 18% keep-shapes -o usa_s.geojson format=geojson precision=0.1
python3 pack.py . <repo>/app/assets/maps
```

`pack.py` adds the capitals, regions and names, picks each place's label
point and writes the compact JSON the app reads.
