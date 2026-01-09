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

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_water_areas_z0_2` | 0-2 | 5000 | 100,000,000 | create_area_mview_from_mview | |
   | `mv_water_areas_z3_5` | 3-5 | 1000 | 50,000,000 | create_area_mview_from_mview | |
   | `mv_water_areas_z6_7` | 6-7 | 200 | 1,000,000 | create_area_mview_from_mview | |
   | `mv_water_areas_z8_9` | 8-9 | 100 | 10,000 | create_area_mview_from_mview | |
   | `mv_water_areas_z10_12` | 10-12 | 20 | 100 | create_area_mview_from_mview | |
   | `mv_water_areas_z13_15` | 13-15 | 5 | - | create_area_mview_from_mview | |
   | `mv_water_areas_z16_20` | 16-20 | 0 | - | create_areas_mview | Base view |


# Water Centroids (water_areas_centroids)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_water_areas_centroids_z8_9` | 8-9 | - | - | create_mview_centroid_from_mview | Derived |
   | `mv_water_areas_centroids_z10_12` | 10-12 | - | - | create_mview_centroid_from_mview | Derived |
   | `mv_water_areas_centroids_z13_15` | 13-15 | - | - | create_mview_centroid_from_mview | Derived |
   | `mv_water_areas_centroids_z14_20` | 14-20 | - | - | create_mview_centroid_from_mview | Derived |


# Water Lines (water_lines)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_water_lines_z16_20` | 16-20 | 0 | - | create_lines_mview | Base view |
   | `mv_water_lines_z13_15` | 13-15 | 5 | - | create_mview_line_from_mview | Derived |
   | `mv_water_lines_z10_12` | 10-12 | 20 | - | create_mview_line_from_mview | Derived |
   | `mv_water_lines_z8_9` | 8-9 | 100 | - | create_mview_line_from_mview | Derived |

# Administrative Boundaries - Areas (admin_boundaries_areas)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_admin_boundaries_areas_z0_2` | 0-2 | 5000 | - | create_areas_mview | |
   | `mv_admin_boundaries_areas_z3_5` | 3-5 | 1000 | - | create_areas_mview | |
   | `mv_admin_boundaries_areas_z6_7` | 6-7 | 200 | - | create_areas_mview | |
   | `mv_admin_boundaries_areas_z8_9` | 8-9 | 100 | - | create_areas_mview | |
   | `mv_admin_boundaries_areas_z10_12` | 10-12 | 20 | - | create_areas_mview | |
   | `mv_admin_boundaries_areas_z13_15` | 13-15 | 5 | - | create_areas_mview |  |
   | `mv_admin_boundaries_areas_z16_20` | 16-20 | 1 | - | create_areas_mview | |

# Administrative Boundaries - Centroids (admin_boundaries_centroids)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_admin_boundaries_centroids_z0_2` | 0-2 | - | - | create_admin_boundaries_centroids_mview | Derived |
   | `mv_admin_boundaries_centroids_z3_5` | 3-5 | - | - | create_admin_boundaries_centroids_mview | Derived |
   | `mv_admin_boundaries_centroids_z6_7` | 6-7 | - | - | create_admin_boundaries_centroids_mview | Derived |
   | `mv_admin_boundaries_centroids_z8_9` | 8-9 | - | - | create_admin_boundaries_centroids_mview | Derived |
   | `mv_admin_boundaries_centroids_z10_12` | 10-12 | - | - | create_admin_boundaries_centroids_mview | Derived |
   | `mv_admin_boundaries_centroids_z13_15` | 13-15 | - | - | create_admin_boundaries_centroids_mview | Derived |
   | `mv_admin_boundaries_centroids_z16_20` | 16-20 | - | - | create_admin_boundaries_centroids_mview | Derived |

# Administrative Boundaries - Lines (admin_boundaries_lines)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_admin_boundaries_lines_z0_2` | 0-2 | 5000 | - | ST_SimplifyPreserveTopology | |
   | `mv_admin_boundaries_lines_z3_5` | 3-5 | 1000 | - | ST_SimplifyPreserveTopology | |
   | `mv_admin_boundaries_lines_z6_7` | 6-7 | 200 | - | ST_SimplifyPreserveTopology | |
   | `mv_admin_boundaries_lines_z8_9` | 8-9 | 100 | - | ST_SimplifyPreserveTopology | |
   | `mv_admin_boundaries_lines_z10_12` | 10-12 | 20 | - | ST_SimplifyPreserveTopology | |
   | `mv_admin_boundaries_lines_z13_15` | 13-15 | 5 | - | ST_SimplifyPreserveTopology | |
   | `mv_admin_boundaries_lines_z16_20` | 16-20 | 1 | - | ST_SimplifyPreserveTopology | |

# Administrative Boundaries - Maritime (admin_boundaries_maritime)

TODO: fix according to schema

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_admin_maritime_lines_z0_5_v2` | 0-5 ⚠️ | 2000 | - | create_lines_mview | Should be z0_2 + z3_5 |
   | `mv_admin_maritime_lines_z6_9` | 6-9 ⚠️ | 500 | - | create_lines_mview | Should be z6_7 + z8_9 |
   | `mv_admin_maritime_lines_z10_15` | 10-15 ⚠️ | 10 | - | create_lines_mview | Should be z10_12 + z13_15 |


# Land Use - Areas (landuse_areas)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_landuse_areas_z6_7` | 6-7 | 200 | 10,000,000 | create_areas_mview | |
   | `mv_landuse_areas_z8_9` | 8-9 | 100 | 1,000,000 | create_areas_mview | |
   | `mv_landuse_areas_z10_12` | 10-12 | 20 | 50,000 | create_areas_mview | |
   | `mv_landuse_areas_z13_15` | 13-15 | 5 | 10,000 | create_areas_mview | |
   | `mv_landuse_areas_z16_20` | 16-20 | 0 | - | create_areas_mview | |

# Land Use - Centroids (landuse_points_centroids)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_landuse_points_centroids_z6_7` | 6-7 | - | - | create_points_centroids_mview | Derived |
   | `mv_landuse_points_centroids_z8_9` | 8-9 | - | - | create_points_centroids_mview | Derived |
   | `mv_landuse_points_centroids_z10_12` | 10-12 | - | - | create_points_centroids_mview | Derived |
   | `mv_landuse_points_centroids_z13_15` | 13-15 | - | - | create_points_centroids_mview | Derived |
   | `mv_landuse_points_centroids_z16_20` | 16-20 | - | - | create_points_centroids_mview | Derived |

# Land Use - Lines (landuse_lines)

   - Filtering only tree_row, since this is the only one used in the mapstyles
   
   | MView | Zoom Levels | Simplification (m) | Min Length (m) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_landuse_lines_z16_20` | 16-20 | 5 | 0 | create_lines_mview | Filter: type IN ('tree_row') |
   | `mv_landuse_lines_z14_15` | 14-15 | 5 | - | create_mview_line_from_mview | Derived from z16_20 |

# Transport - Areas (transport_areas)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_transport_areas_z10_12` | 10-12 | 20 | 50,000 | create_areas_mview |  |
   | `mv_transport_areas_z13_15` | 13_15 | 5 | 10,000 | create_areas_mview | |
   | `mv_transport_areas_z16_20` | 16-20 | 0 | - | create_areas_mview | |

# Transport - Centroids (transport_points_centroids)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_transport_points_centroids_z10_12` | 10-12 | - | - | create_points_centroids_mview |  |
   | `mv_transport_points_centroids_z13_15` | 13-15 | - | - | create_points_centroids_mview | |
   | `mv_transport_points_centroids_z16_20` | 16-20 | - | - | create_points_centroids_mview | Derived |


# Transport - Lines (transport_lines)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_transport_lines_z5` | 5 | 1000 | - | create_transport_lines_mview | |
   | `mv_transport_lines_z6_7` | 6-7 | 200 | - | create_transport_lines_mview | |
   | `mv_transport_lines_z8_9` | 8-9 | 100 | - | create_transport_lines_mview | |
   | `mv_transport_lines_z10_12` | 10-12 | 20 | - | create_transport_lines_mview | |
   | `mv_transport_lines_z13_15` | 13-15 | 5 | - | create_transport_lines_mview | |
   | `mv_transport_lines_z16_20` | 16-20 | 0 | - | create_transport_lines_mview | |

   

# Buildings - Areas (buildings_areas)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_buildings_areas_z14_15` | 14-15 | 5 | 5,000 | create_areas_mview | Starts showing at zoom 14|
   | `mv_buildings_areas_z16_20` | 16-20 | 0 | - | create_areas_mview | |


# Buildings - Centroids (buildings_points_centroids)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_buildings_points_centroids_z14_15` | 14-15 | - | - | create_points_centroids_mview | Derived |
   | `mv_buildings_points_centroids_z16_20` | 16-20 | - | - | create_points_centroids_mview | Derived |

# Amenities - Areas (amenity_areas)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_amenity_areas_z14_15` | 14-15 | 5 | 5,000 | create_areas_mview |  Starts showing at zoom 14 |
   | `mv_amenity_areas_z16_20` | 16-20 | 0 | - | create_areas_mview | |

# Amenities - Centroids (amenity_points_centroids)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_amenity_points_centroids_z14_15` | 14-15 | - | - | create_points_centroids_mview | Derived |
   | `mv_amenity_points_centroids_z16_20` | 16-20 | - | - | create_points_centroids_mview | Derived |

# Other - Areas (other_areas)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_other_areas_z8_9` | 8-9 | 100 | 1,000,000 | create_areas_mview | |
   | `mv_other_areas_z10_12` | 10-12 | 20 | 50,000 | create_areas_mview | |
   | `mv_other_areas_z13_15` | 13-15 | 5 | 5,000 | create_areas_mview | |
   | `mv_other_areas_z16_20` | 16-20 | 0 | - | create_areas_mview | |

# Other - Centroids (other_points_centroids)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_other_points_centroids_z8_9` | 8-9 | - | - | create_points_centroids_mview | Derived |
   | `mv_other_points_centroids_z10_12` | 10-12 | - | - | create_points_centroids_mview | Derived |
   | `mv_other_points_centroids_z13_15` | 13-15 | - | - | create_points_centroids_mview | Derived |
   | `mv_other_points_centroids_z16_20` | 16-20 | - | - | create_points_centroids_mview | Derived |

# Other - Lines (other_lines)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_other_lines_z14_15` | 14-15 | 5 | - | create_mview_line_from_mview | Derived |
   | `mv_other_lines_z16_20` | 16-20 | 0 | - | create_lines_mview | Base view |


# Places - Areas (place_areas)

TODO: fix according to schema

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_place_areas_z14_20` | 14-20 ⚠️ | - | - | create_place_areas_mview | Should be z14_15 + z16_20 |

# Places - Centroids (place_points_centroids) 
TODO: fix according to schema


   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_place_points_centroids_z0_2` | 0-2 | - | - | create_place_points_centroids_mview | |
   | `mv_place_points_centroids_z3_5` | 3-5 | - | - | create_place_points_centroids_mview | |
   | `mv_place_points_centroids_z6_10` | 6-10 ⚠️ | - | - | create_place_points_centroids_mview | Wide range |
   | `mv_place_points_centroids_z11_20` | 11-20 ⚠️ | - | - | create_place_points_centroids_mview | Very wide range |

   ### Routes - Lines (routes_indexed)

   | MView | Zoom Levels | Simplification (m) | Min Area (m²) | Function | Notes |
   |-------|-------------|-------------------|---------------|---------|-------|
   | `mv_routes_indexed_z5` | 5 | 1000 | - | create_mv_routes_by_length | |
   | `mv_routes_indexed_z6_7` | 6-7 | 200 | - | create_mv_routes_by_length | |
   | `mv_routes_indexed_z8_9` | 8-9 | 100 | - | create_mv_routes_by_length | |
   | `mv_routes_indexed_z10_12` | 10-12 | 20 | - | create_mv_routes_by_length | |
   | `mv_routes_indexed_z13_15` | 13-15 | 5 | - | create_mv_routes_by_length | |
   | `mv_routes_indexed_z16_20` | 16-20 | 0 | - | create_mv_routes_by_length | |

