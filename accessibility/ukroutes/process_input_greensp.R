########################################
### Processing inputs - green spaces ###
########################################

## Aim: To subset all green spaces for Cheshire and Merseyside, estimate access points, and save them in the required format for accessibility processing.

# Libraries
library(data.table)
library(arrow)
library(sf)

## Load and clean datasets ##

# Load ordnance survey green space layer (OSGSL) datasets (all of Great Britain)
osgsl <- read_sf("../data/raw/osgsl/opgrsp_essh_gb/OS Open Greenspace (ESRI Shape File) GB/data/GB_AccessPoint.shp") # Access points
osgsl_ext <- read_sf("../data/raw/osgsl/opgrsp_essh_gb/OS Open Greenspace (ESRI Shape File) GB/data/GB_GreenspaceSite.shp") # Spatial extents

# Load open access land file
openland <- read_sf("../data/raw/osgsl/CRoW_Act_2000_Access_Layer_5470121843372739158.geojson") # 2023 data accessed via https://naturalengland-defra.opendata.arcgis.com/datasets/6ce15f2cd06c4536983d315694dad16b/explore?location=53.419183%2C-2.773053%2C10.73

# Calculate size of each polygon (m2)
osgsl_ext$size <- st_area(osgsl_ext) # Estimates the size of each OSGSL spatial extent
osgsl_extdf <- data.frame(osgsl_ext) # Convert format to allow next step
osgsl <- merge(osgsl, osgsl_extdf[, c("id", "size")], by.x = "refToGSite", by.y = "id", all.x = TRUE) # Join onto the access points file
openland$size <- st_area(openland) # open access land
rm(osgsl_extdf)

# Subset C&M points
cm_lsoas <- read_sf("../spatial_files/cm_lsoas.shp") # Load in C&M shapefile
dissolved_areas <- st_union(cm_lsoas) # Dissolve all boundaries so a single area extent
cm_buffer <- st_buffer(dissolved_areas, dist = 2000) # Add buffer around border - 2km
osgsl_cm <- st_intersection(osgsl, cm_buffer) # Subset only points within the spatial extent of above buffer - osgsl access points
osgsl_ext_cm <- st_intersection(osgsl_ext, cm_buffer) # osgsl spatial extent
openland_cm <- st_intersection(openland, cm_buffer) # open access land
rm(osgsl, openland, cm_buffer, dissolved_areas, cm_lsoas, osgsl_ext)

## Define access points as N,S,E,W points to supplement formal access points ##

# Create a function to get the north, south, east, and west points via a bounding box
get_extreme_points <- function(geometry) {
  bbox <- st_bbox(geometry)
  
  # Create points for north, south, east, and west
  north_point <- st_point(c((bbox["xmin"] + bbox["xmax"]) / 2, bbox["ymax"]))
  south_point <- st_point(c((bbox["xmin"] + bbox["xmax"]) / 2, bbox["ymin"]))
  east_point  <- st_point(c(bbox["xmax"], (bbox["ymin"] + bbox["ymax"]) / 2))
  west_point  <- st_point(c(bbox["xmin"], (bbox["ymin"] + bbox["ymax"]) / 2))
  
  # Combine into a list
  points <- list(
    north = north_point,
    south = south_point,
    east = east_point,
    west = west_point
  )
  
  return(points)
}

# Apply the function to each geometry in the datasets
osgsl_newaccess_list <- lapply(osgsl_ext_cm$geometry, get_extreme_points) # osgsl - spatial extent
openland_newaccess_list <- lapply(openland_cm$geometry, get_extreme_points) # open access land
rm(get_extreme_points)

# Convert the list of points into a single sf object
# osgsl spatial extent (takes just over 1 min to run)
osgsl_newaccess_sf <- do.call(rbind, lapply(osgsl_newaccess_list, function(points) {
  data.frame(
    north = st_sfc(points$north),
    south = st_sfc(points$south),
    east  = st_sfc(points$east),
    west  = st_sfc(points$west)
  )
}))
# open access land (faster)
openland_newaccess_sf <- do.call(rbind, lapply(openland_newaccess_list, function(points) {
  data.frame(
    north = st_sfc(points$north),
    south = st_sfc(points$south),
    east  = st_sfc(points$east),
    west  = st_sfc(points$west)
  )
}))

# Combine the original sf data with the extreme points sf data
osgsl_newaccess <- cbind(osgsl_ext_cm[, c("id")], osgsl_newaccess_sf) # osgsl spatial extent
openland_newaccess <- cbind(openland_cm[, c("OBJECTID")], openland_newaccess_sf) # open access land
rm(openland_newaccess_sf, osgsl_newaccess_sf, openland_newaccess_list, osgsl_newaccess_list)

# Convert sf objects to data.table for next step
dt_osgsl <- as.data.table(osgsl_newaccess) # osgsl - spatial extent
dt_osgsl$geometry <- NULL # Delete column as will give too responses
dt_openland <- as.data.table(openland_newaccess) # open access land
dt_openland$geometry <- NULL # Delete column as will give too responses
setnames(dt_openland, old = "OBJECTID", new = "id") # Rename variable for next steps
rm(osgsl_newaccess, openland_newaccess) # Tidy

# Define a function to extract coordinates and reshape into long format
extract_coordinates <- function(dt, id_col = "id") {
  # Initialize empty list to store results
  result <- list()
  
  # Loop through each geometry column
  for (col in grep("^geometry", names(dt), value = TRUE)) {
    # Extract coordinates and reshape into long format
    coords <- st_coordinates(dt[[col]])
    coords_long <- data.table(id = dt$id,
                              #point_type = c("north", "south", "east", "west"),
                              EASTING = coords[, 1],
                              NORTHING = coords[, 2])
    
    # Add to result list
    result[[col]] <- coords_long
  }
  
  # Combine results into a single data.table
  final_dt <- rbindlist(result)
  
  return(final_dt)
}

# Call the function to get the long format data.table
long_dt_osgsl <- extract_coordinates(dt_osgsl)
long_dt_openland <- extract_coordinates(dt_openland) # open access 
rm(dt_osgsl, dt_openland, extract_coordinates) # Tidy

# Join back on size of each green space
long_dt_osgsl <- merge(long_dt_osgsl, osgsl_ext_cm[, c("id", "size")], by = "id", all.x = TRUE) # osgsl spatial extent
long_dt_osgsl$geometry <- NULL # delete
long_dt_openland <- merge(long_dt_openland, openland_cm[, c("OBJECTID", "size")], by.x = "id", by.y = "OBJECTID", all.x = TRUE) # open access land
long_dt_openland$geometry <- NULL # delete
rm(osgsl_ext_cm, openland_cm) # Tidy


## Create output files for access metrics ##

# Get key information for defined access points from OSGSL
coordinates <- st_coordinates(osgsl_cm) # Get easting and northing
coordinates_df <- as.data.frame(coordinates) # Convert the coordinates to a data frame 
colnames(coordinates_df) <- c("easting", "northing") # Rename columns
osgsl_cm$easting <- coordinates_df$easting # Append the coordinates to the original object
osgsl_cm$northing <- coordinates_df$northing
osgsl_cm <- data.frame(osgsl_cm) # Convert format
osgsl_new <- osgsl_cm[, c("id", "size", "easting", "northing")] # Subset vars needed
setnames(osgsl_new, old = "easting", new = "EASTING") # Rename variable for consistency when rbind later
setnames(osgsl_new, old = "northing", new = "NORTHING")
rm(coordinates, coordinates_df, osgsl_cm)

# Join together all three objects with access points into a single file
accesspoints <- rbind(osgsl_new, long_dt_osgsl, long_dt_openland) # Join all files together
rm(osgsl_new, long_dt_osgsl, long_dt_openland) # Tidy


## Save the relevant files relating to each of Natural England's defined green space types ##

# Convert to hectares
accesspoints$size <- as.numeric(gsub("\\[m\\^2\\]", "", accesspoints$size)) / 10000

# Change variable names for routing processing
setnames(accesspoints, old = "EASTING", new = "easting") # Rename variable for consistency when rbind later
setnames(accesspoints, old = "NORTHING", new = "northing")

# All green spaces
temp <- accesspoints # Create temp file (n = 37465 access points)
temp$size <- NULL # Drop variables not required
write_parquet(temp, "../data/processed/osgsl/osgsl_all.parquet") # Save

# Doorstep green space
temp <- accesspoints[accesspoints$size >= 0.5,] # Subset those which meet the size threshold (0.5ha) - n = 18759 (50%) 
temp$size <- NULL # Drop variables not required
write_parquet(temp, "../data/processed/osgsl/osgsl_doorstop.parquet") # Save

# Local green space
temp <- accesspoints[accesspoints$size >= 2,] # Subset those which meet the size threshold (2ha) - n = 10653 (28%)
temp$size <- NULL # Drop variables not required
write_parquet(temp, "../data/processed/osgsl/osgsl_local.parquet") # Save

# Neighbourhood green space
temp <- accesspoints[accesspoints$size >= 10,] # Subset those which meet the size threshold (10ha) - n = 3850 (10%)
temp$size <- NULL # Drop variables not required
write_parquet(temp, "../data/processed/osgsl/osgsl_neighbourhood.parquet") # Save

# Wider green space
temp <- accesspoints[accesspoints$size >= 20,] # Subset those which meet the size threshold (20ha) - n = 2486 (7%)
temp$size <- NULL # Drop variables not required
write_parquet(temp, "../data/processed/osgsl/osgsl_wider.parquet") # Save

# District green space
temp <- accesspoints[accesspoints$size >= 100,] # Subset those which meet the size threshold (100ha) - n = 306 (1%)
temp$size <- NULL # Drop variables not required
write_parquet(temp, "../data/processed/osgsl/osgsl_district.parquet") # Save

# Sub-regional green space
temp <- accesspoints[accesspoints$size >= 500,] # Subset those which meet the size threshold (500ha) - n = 32 (0.01%)
temp$size <- NULL # Drop variables not required
write_parquet(temp, "../data/processed/osgsl/osgsl_subregional.parquet") # Save

# Tidy
rm(temp, accesspoints)
gc()
