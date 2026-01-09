# Tables and Zoom Levels for Tiler - Documentation and Standardization

This document lists all materialized tables (mv_*) used in TOML configuration files and proposes a standard zoom level schema to unify the configuration.


### Standardize in gaps: 0‑2, 3‑5, 6‑7, 8‑9, 10‑12, 13‑15, 16‑20

### Simplification: 

### Large areas by zoom level
        - 0‑2: 5000
        - 3‑5: 1000
        - 6‑7: 200
        - 8‑9: 100
        - 10‑12: 20
        - 13‑15: 5–10 (choose one and be consistent between water/admin)
        - 16‑20: 0–1 (0 for clean polygons, 1 if there are very dense geometries)


### Transport lines / routes
        - 0‑2: 5000
        - 3‑5: 1000
        - 6‑7: 200
        - 8‑9: 100
        - 10‑12: 20
        - 13‑15: 5
        - 16‑20: 0


## Current MView Values by Category

These tables document all current simplification values and area filters for each materialized view, extracted from SQL files in `/images/tiler-imposm/queries/ohm_mviews/`.

**Legend:**
- `-` = Not applicable / No simplification / No area filter
- ⚠️ = Detected inconsistency that should be standardized
- **Derived** = View created from another mview (not directly from source table)

# Water Areas (water_areas)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_water_areas_z16_20` | 16-20 | 0 | - | `osm_water_areas` | - | Base view |
   | `mv_water_areas_z13_15` | 13-15 | 5 | - | `mv_water_areas_z16_20` | - | Derived |
   | `mv_water_areas_z10_12` | 10-12 | 20 | 100 | `mv_water_areas_z13_15` | type IN ('water','pond','basin','canal','mill_pond','riverbank') | Derived |
   | `mv_water_areas_z8_9` | 8-9 | 100 | 10,000 | `mv_water_areas_z10_12` | - | Derived |
   | `mv_water_areas_z6_7` | 6-7 | 200 | 1,000,000 | `mv_water_areas_z8_9` | - | Derived |
   | `mv_water_areas_z3_5` | 3-5 | 1000 | 50,000,000 | `mv_water_areas_z6_7` | - | Derived |
   | `mv_water_areas_z0_2` | 0-2 | 5000 | 100,000,000 | `mv_water_areas_z3_5` | type IN ('water','riverbank') | Derived |


# Water Centroids (water_areas_centroids)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_water_areas_centroids_z16_20` | 16-20 | - | - | `mv_water_areas_z16_20` | name IS NOT NULL AND name <> '' | Derived |
   | `mv_water_areas_centroids_z13_15` | 13-15 | - | - | `mv_water_areas_z13_15` | name IS NOT NULL AND name <> '' | Derived |
   | `mv_water_areas_centroids_z10_12` | 10-12 | - | - | `mv_water_areas_z10_12` | name IS NOT NULL AND name <> '' | Derived |
   | `mv_water_areas_centroids_z8_9` | 8-9 | - | - | `mv_water_areas_z8_9` | name IS NOT NULL AND name <> '' | Derived |


# Water Lines (water_lines)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_water_lines_z16_20` | 16-20 | 0 | - | `osm_water_lines` | type IN ('river','canal','cliff','dam','stream','ditch','drain') | Base view |
   | `mv_water_lines_z13_15` | 13-15 | 5 | - | `mv_water_lines_z16_20` | type IN ('river','canal','cliff','dam','stream') | Derived |
   | `mv_water_lines_z10_12` | 10-12 | 20 | - | `mv_water_lines_z13_15` | type IN ('river','canal','cliff','dam') | Derived |
   | `mv_water_lines_z8_9` | 8-9 | 100 | - | `mv_water_lines_z10_12` | type IN ('river','canal') | Derived |

# Administrative Boundaries - Areas (admin_boundaries_areas)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_admin_boundaries_areas_z16_20` | 16-20 | 1 | - | `osm_admin_areas` | admin_level IN (1,2,3,4,5,6,7,8,9,10,11) | Base view |
   | `mv_admin_boundaries_areas_z13_15` | 13-15 | 5 | - | `mv_admin_boundaries_areas_z16_20` | no-filters | Derived |
   | `mv_admin_boundaries_areas_z10_12` | 10-12 | 20 | - | `mv_admin_boundaries_areas_z13_15` | admin_level IN (1,2,3,4,5,6,7,8,9,10) | Derived |
   | `mv_admin_boundaries_areas_z8_9` | 8-9 | 100 | - | `mv_admin_boundaries_areas_z10_12` | admin_level IN (1,2,3,4,5,6,7,8,9) | Derived |
   | `mv_admin_boundaries_areas_z6_7` | 6-7 | 200 | - | `mv_admin_boundaries_areas_z8_9` | admin_level IN (1,2,3,4,5,6) | Derived |
   | `mv_admin_boundaries_areas_z3_5` | 3-5 | 1000 | - | `mv_admin_boundaries_areas_z6_7` | admin_level IN (1,2,3,4) | Derived |
   | `mv_admin_boundaries_areas_z0_2` | 0-2 | 5000 | - | `mv_admin_boundaries_areas_z3_5` | admin_level IN (1,2) | Derived |

# Administrative Boundaries - Centroids (admin_boundaries_centroids)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_admin_boundaries_centroids_z16_20` | 16-20 | - | - | `mv_admin_boundaries_areas_z16_20` | name IS NOT NULL AND name <> '' | Derived |
   | `mv_admin_boundaries_centroids_z13_15` | 13-15 | - | - | `mv_admin_boundaries_areas_z13_15` | name IS NOT NULL AND name <> '' | Derived |
   | `mv_admin_boundaries_centroids_z10_12` | 10-12 | - | - | `mv_admin_boundaries_areas_z10_12` | name IS NOT NULL AND name <> '' | Derived |
   | `mv_admin_boundaries_centroids_z8_9` | 8-9 | - | - | `mv_admin_boundaries_areas_z8_9` | name IS NOT NULL AND name <> '' | Derived |
   | `mv_admin_boundaries_centroids_z6_7` | 6-7 | - | - | `mv_admin_boundaries_areas_z6_7` | name IS NOT NULL AND name <> '' | Derived |
   | `mv_admin_boundaries_centroids_z3_5` | 3-5 | - | - | `mv_admin_boundaries_areas_z3_5` | name IS NOT NULL AND name <> '' | Derived |
   | `mv_admin_boundaries_centroids_z0_2` | 0-2 | - | - | `mv_admin_boundaries_areas_z0_2` | name IS NOT NULL AND name <> '' | Derived |

# Administrative Boundaries - Lines (admin_boundaries_lines)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_admin_boundaries_lines_z16_20` | 16-20 | 1 | - | `mv_admin_boundaries_relations_ways` | admin_level IN (1,2,3,4,5,6,7,8,9,10,11) | `mv_relation_members_boundaries` + `osm_admin_lines` |
   | `mv_admin_boundaries_lines_z13_15` | 13-15 | 5 | - | `mv_admin_boundaries_lines_z16_20` | admin_level IN (1,2,3,4,5,6,7,8,9,10) | Derived |
   | `mv_admin_boundaries_lines_z10_12` | 10-12 | 20 | - | `mv_admin_boundaries_lines_z13_15` | no-filters | Derived |
   | `mv_admin_boundaries_lines_z8_9` | 8-9 | 100 | - | `mv_admin_boundaries_lines_z10_12` | admin_level IN (1,2,3,4,5,6,7,8,9) | Derived |
   | `mv_admin_boundaries_lines_z6_7` | 6-7 | 200 | - | `mv_admin_boundaries_lines_z8_9` | admin_level IN (1,2,3,4,5,6) | Derived |
   | `mv_admin_boundaries_lines_z3_5` | 3-5 | 1000 | - | `mv_admin_boundaries_lines_z6_7` | admin_level IN (1,2,3,4) | Derived |
   | `mv_admin_boundaries_lines_z0_2` | 0-2 | 5000 | - | `mv_admin_boundaries_lines_z3_5` | admin_level IN (1,2) | Derived |

# Administrative Boundaries - Maritime (admin_boundaries_maritime)

TODO: fix according to schema

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_admin_maritime_lines_z0_5_v2` | 0-5 ⚠️ | 2000 | - | `osm_admin_lines` | maritime = 'yes' | Should be z0_2 + z3_5 |
   | `mv_admin_maritime_lines_z6_9` | 6-9 ⚠️ | 500 | - | `osm_admin_lines` | maritime = 'yes' | Should be z6_7 + z8_9 |
   | `mv_admin_maritime_lines_z10_15` | 10-15 ⚠️ | 10 | - | `osm_admin_lines` | maritime = 'yes' | Should be z10_12 + z13_15 |


# Land Use - Areas (landuse_areas)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_landuse_areas_z16_20` | 16-20 | 0 | - | `osm_landuse_areas` | NOT (type = 'water' AND class = 'natural') | Base view |
   | `mv_landuse_areas_z13_15` | 13-15 | 5 | 10,000 | `mv_landuse_areas_z16_20` | - | Derived |
   | `mv_landuse_areas_z10_12` | 10-12 | 20 | 50,000 | `mv_landuse_areas_z13_15` | - | Derived |
   | `mv_landuse_areas_z8_9` | 8-9 | 100 | 1,000,000 | `mv_landuse_areas_z10_12` | - | Derived |
   | `mv_landuse_areas_z6_7` | 6-7 | 200 | 10,000,000 | `mv_landuse_areas_z8_9` | - | Derived |

# Land Use - Centroids (landuse_points_centroids)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_landuse_points_centroids_z16_20` | 16-20 | - | - | `mv_landuse_areas_z16_20` + `mv_landuse_points` | - | Derived (points from `osm_landuse_points`) |
   | `mv_landuse_points_centroids_z13_15` | 13-15 | - | - | `mv_landuse_areas_z13_15` | - | Derived |
   | `mv_landuse_points_centroids_z10_12` | 10-12 | - | - | `mv_landuse_areas_z10_12` | - | Derived |
   | `mv_landuse_points_centroids_z8_9` | 8-9 | - | - | `mv_landuse_areas_z8_9` | - | Derived |
   | `mv_landuse_points_centroids_z6_7` | 6-7 | - | - | `mv_landuse_areas_z6_7` + `mv_landuse_points` | - | Derived |

# Land Use - Lines (landuse_lines)

   - Filtering only tree_row, since this is the only one used in the mapstyles
   
   | MView | Zoom Levels | Simplification (m) | Min Length (m) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_landuse_lines_z16_20` | 16-20 | 5 | 0 | `osm_landuse_lines` | type IN ('tree_row') | Base view |
   | `mv_landuse_lines_z14_15` | 14-15 | 5 | - | `mv_landuse_lines_z16_20` | - | Derived |

# Transport - Areas (transport_areas)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_transport_areas_z16_20` | 16-20 | 0 | - | `osm_transport_areas` | NOT (class = 'highway' AND type IN ('motorway','motorway_link','trunk','trunk_link','primary','primary_link','secondary','secondary_link','tertiary','tertiary_link','unclassified','residential','service','living_street','cycleway','bridleway')) | Base view |
   | `mv_transport_areas_z13_15` | 13-15 | 5 | - | `mv_transport_areas_z16_20` | - | Derived |
   | `mv_transport_areas_z10_12` | 10-12 | 20 | 100 | `mv_transport_areas_z13_15` | type IN ('aerodrome','apron','terminal') | Derived |

# Transport - Centroids (transport_points_centroids)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_transport_points_centroids_z16_20` | 16-20 | - | - | `mv_transport_areas_z16_20` + `mv_transport_points` | - | Derived (points from `osm_transport_points`) |
   | `mv_transport_points_centroids_z13_15` | 13-15 | - | - | `mv_transport_areas_z13_15` + `mv_transport_points` | - | Derived (points from `osm_transport_points`) |
   | `mv_transport_points_centroids_z10_12` | 10-12 | - | - | `mv_transport_areas_z10_12` | - | Derived |


# Transport - Lines (transport_lines)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_transport_lines_z16_20` | 16-20 | 0 | - | `osm_transport_lines` + `osm_transport_multilines` | type = ANY(['*']) OR class IN ('railway','route') | Base view (merged) |
   | `mv_transport_lines_z13_15` | 13-15 | 5 | - | `mv_transport_lines_z16_20` | type IN ('motorway','motorway_link','trunk','trunk_link','construction','primary','primary_link','rail','secondary','secondary_link','tertiary','tertiary_link','miniature','narrow_gauge','dismantled','abandoned','disused','razed','light_rail','preserved','proposed','tram','funicular','monorail','taxiway','runway','raceway','residential','service','unclassified') OR class IN ('railway') | Derived |
   | `mv_transport_lines_z10_12` | 10-12 | 20 | - | `mv_transport_lines_z13_15` | type IN ('motorway','motorway_link','trunk','trunk_link','construction','primary','primary_link','rail','secondary','secondary_link','tertiary','tertiary_link','miniature','narrow_gauge','dismantled','abandoned','disused','razed','light_rail','preserved','proposed','tram','funicular','monorail','taxiway','runway') OR class IN ('railway') | Derived |
   | `mv_transport_lines_z8_9` | 8-9 | 100 | - | `mv_transport_lines_z10_12` | - | Derived |
   | `mv_transport_lines_z6_7` | 6-7 | 200 | - | `mv_transport_lines_z8_9` | type IN ('motorway','motorway_link','trunk','trunk_link','construction','primary','primary_link','rail','secondary','secondary_link') OR class IN ('railway') | Derived |
   | `mv_transport_lines_z5` | 5 | 1000 | - | `mv_transport_lines_z6_7` | - | Derived |

   

# Buildings - Areas (buildings_areas)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_buildings_areas_z16_20` | 16-20 | 0 | - | `osm_buildings` | - | Base view |
   | `mv_buildings_areas_z14_15` | 14-15 | 5 | 5,000 | `osm_buildings` | - | Starts showing at zoom 14 |


# Buildings - Centroids (buildings_points_centroids)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_buildings_points_centroids_z16_20` | 16-20 | - | - | `mv_buildings_areas_z16_20` + `mv_buildings_points` | - | Derived (points from `osm_buildings_points`) |
   | `mv_buildings_points_centroids_z14_15` | 14-15 | - | - | `mv_buildings_areas_z14_15` + `mv_buildings_points` | - | Derived (points from `osm_buildings_points`) |

# Amenities - Areas (amenity_areas)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_amenity_areas_z16_20` | 16-20 | 0 | - | `osm_amenity_areas` | - | Base view |
   | `mv_amenity_areas_z14_15` | 14-15 | 5 | 5,000 | `osm_amenity_areas` | - | Starts showing at zoom 14 |

# Amenities - Centroids (amenity_points_centroids)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_amenity_points_centroids_z16_20` | 16-20 | - | - | `mv_amenity_areas_z16_20` + `mv_amenity_points` | - | Derived (points from `osm_amenity_points`) |
   | `mv_amenity_points_centroids_z14_15` | 14-15 | - | - | `mv_amenity_areas_z14_15` + `mv_amenity_points` | - | Derived (points from `osm_amenity_points`) |

# Other - Areas (other_areas)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_other_areas_z16_20` | 16-20 | 0 | - | `osm_other_areas` | - | Base view |
   | `mv_other_areas_z13_15` | 13-15 | 5 | 5,000 | `osm_other_areas` | - | Base view |
   | `mv_other_areas_z10_12` | 10-12 | 20 | 50,000 | `osm_other_areas` | - | Base view |
   | `mv_other_areas_z8_9` | 8-9 | 100 | 1,000,000 | `osm_other_areas` | - | Base view |

# Other - Centroids (other_points_centroids)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_other_points_centroids_z16_20` | 16-20 | - | - | `mv_other_areas_z16_20` + `mv_other_points` | - | Derived (points from `osm_other_points`) |
   | `mv_other_points_centroids_z13_15` | 13-15 | - | - | `mv_other_areas_z13_15` + `mv_other_points` | - | Derived (points from `osm_other_points`) |
   | `mv_other_points_centroids_z10_12` | 10-12 | - | - | `mv_other_areas_z10_12` | - | Derived |
   | `mv_other_points_centroids_z8_9` | 8-9 | - | - | `mv_other_areas_z8_9` | - | Derived |

# Other - Lines (other_lines)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_other_lines_z16_20` | 16-20 | 0 | - | `osm_other_lines` | - | Base view |
   | `mv_other_lines_z14_15` | 14-15 | 5 | - | `mv_other_lines_z16_20` | - | Derived |


# Places - Areas (place_areas)

TODO: fix according to schema

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_place_areas_z14_20` | 14-20 ⚠️ | - | - | `osm_place_areas` | type IN ('plot','square','islet') | Should be z14_15 + z16_20 |

# Places - Centroids (place_points_centroids) 
TODO: fix according to schema

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_place_points_centroids_z0_2` | 0-2 | - | - | `osm_place_areas` + `osm_place_points` | Areas: type IN ('island'); Points: type IN ('ocean','sea','archipelago','country','territory','unorganized territory') | Merged from areas and points |
   | `mv_place_points_centroids_z3_5` | 3-5 | - | - | `osm_place_areas` + `osm_place_points` | Areas: type IN ('island'); Points: type IN ('ocean','sea','archipelago','country','territory','unorganized territory','state','province','region') | Merged from areas and points |
   | `mv_place_points_centroids_z6_10` | 6-10 ⚠️ | - | - | `osm_place_areas` + `osm_place_points` | Areas: type IN ('island'); Points: type IN ('ocean','sea','archipelago','country','territory','unorganized territory','state','province','region','county','municipality','city','town') | Wide range - Merged from areas and points |
   | `mv_place_points_centroids_z11_20` | 11-20 ⚠️ | - | - | `osm_place_areas` + `osm_place_points` | Areas: type IN ('plot','square','islet'); Points: type IN ('state','province','region','county','municipality','city','town','village','suburb','locality','hamlet','islet','neighbourhood','district','borough','quarter','isolated_dwelling','farm') | Very wide range - Merged from areas and points |

# Routes - Lines (routes_indexed)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Source | Filters | Notes |
   |-------|-------------|-------------------|---------------|--------|---------|-------|
   | `mv_routes_indexed_z16_20` | 16-20 | 0 | - | `mv_routes_indexed` | - | Base view |
   | `mv_routes_indexed_z13_15` | 13-15 | 5 | - | `mv_routes_indexed_z16_20` | - | Derived |
   | `mv_routes_indexed_z10_12` | 10-12 | 20 | - | `mv_routes_indexed_z13_15` | - | Derived |
   | `mv_routes_indexed_z8_9` | 8-9 | 100 | - | `mv_routes_indexed_z10_12` | - | Derived |
   | `mv_routes_indexed_z6_7` | 6-7 | 200 | - | `mv_routes_indexed_z8_9` | - | Derived |
   | `mv_routes_indexed_z5` | 5 | 1000 | - | `mv_routes_indexed_z6_7` | - | Derived |

