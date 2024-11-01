#######################################################################
### Process UPRNs into format required for deriving indicators from ###
#######################################################################


## Aim: To subset all UPRNs for Cheshire and Merseyside, aggregate them to TOIDs, create 300m buffers and then save into the format needed to generate satellite derived indicators from. 

# Libraries
library(data.table)
library(parallel)
library(arrow)
library(sf)


### If want to do this for just UPRNs ###

# # Load UPRNs
# uprn <- fread("./osopenuprn_202405_csv/osopenuprn_202405.csv") # All UPRNs for GB and their points, then load the following April 2024 data via https://geoportal.statistics.gov.uk/datasets/acd0dbf73c2849f2a45e15c4aa248805/about - gives UPRN IDs and their locational information (exact point)
# uprn_lkup <- fread("./NSUL_APR_2024_NW.csv") # This is a lookup file linking the UPRNs to spatial identifiers for the North West UPRNs for April 2024 https://geoportal.statistics.gov.uk/datasets/02d709e510804d67b16068b037cd72e6/about 
# uprn_lkup <- merge(uprn_lkup, uprn, by = "UPRN", all.x = TRUE) # Join on exact locations to NW dataset
# rm(uprn)
# 
# # Subset only Cheshire and Merseyside
# uprn_cm <- uprn_lkup[uprn_lkup$lad23cd == "E06000049" | uprn_lkup$lad23cd == "E06000050" | uprn_lkup$lad23cd == "E06000006" | uprn_lkup$lad23cd == "E08000011" | uprn_lkup$lad23cd == "E08000012" | uprn_lkup$lad23cd == "E08000014" | uprn_lkup$lad23cd == "E08000013" | uprn_lkup$lad23cd == "E06000007" | uprn_lkup$lad23cd == "E08000015",] # Local Authority Codes in order are: Cheshire East, Cheshire West and Chester, Halton, Knowsley, Liverpool, Sefton, St Helens, Warrington, Wirral
# rm(uprn_lkup)
# 
# # Edit variables to keep those needed
# names(uprn_cm)[names(uprn_cm) == "LATITUDE"] <- "latitude"
# names(uprn_cm)[names(uprn_cm) == "LONGITUDE"] <- "longitude"
# uprn_cm <- uprn_cm[, c("UPRN", "latitude", "longitude")] # drop variables not required
# uprn_cm <- uprn_cm[!is.na(uprn_cm$latitude)] # Drop missing data (76 with missing locations)
# write_parquet(uprn_cm, "./uprns_cm.parquet") # Save
# rm(uprn_cm)
# gc()

### Faster approach - use TOIDs for processing then link back to UPRNs ###

# Load TOIDs
toid <- fread("./osopentoid_202405_csv_sd/osopentoid_202405_sd.csv") # Download via https://www.ordnancesurvey.co.uk/products/os-open-toid (downloaded 2nd July 2024)
toid_sj <- fread("./osopentoid_202405_csv_sj/osopentoid_202405_sj.csv") # Select all relevant regions
toid <- rbind(toid, toid_sj) # Join together into a single file
toid <- toid[, c("TOID", "EASTING", "NORTHING")] # Keep only variables required
rm(toid_sj) # Save space
gc()

# Get information to subset TOIDs for Cheshire and Merseyside
lkup <- fread("./lids-2024-06_csv_BLPU-UPRN-TopographicArea-TOID-5/BLPU_UPRN_TopographicArea_TOID_5.csv") #  Load UPRN to TOID lookup (via https://www.ordnancesurvey.co.uk/products/os-open-linked-identifiers) - need the BLPU UPRN to Topographic TOID one (downloaded 2nd July 2024)
lkup <- lkup[, c("IDENTIFIER_1", "IDENTIFIER_2")] # Keep only variables required
names(lkup)[names(lkup) == "IDENTIFIER_1"] <- "UPRN" # Rename variables
names(lkup)[names(lkup) == "IDENTIFIER_2"] <- "TOID"
lkup2 <- fread("./NSUL_APR_2024/Data/NSUL_APR_2024_NW.csv") # UPRN lookup table to spatial identifiers - April 2024 dataset downloaded 2nd July 2024 via https://geoportal.statistics.gov.uk/datasets/02d709e510804d67b16068b037cd72e6/about 
lkup2 <- lkup2[, c("UPRN", "lad23cd")] # Keep only variables required
lkup <- merge(lkup, lkup2, by = "UPRN", all.x = TRUE) # Join together
lkup <- lkup[!is.na(hold$lad23cd)] # Drop TOIDs not in the North West
# Subset only Cheshire and Merseyside
uprn_cm <- lkup[lkup$lad23cd == "E06000049" | lkup$lad23cd == "E06000050" | lkup$lad23cd == "E06000006" | lkup$lad23cd == "E08000011" | lkup$lad23cd == "E08000012" | lkup$lad23cd == "E08000014" | lkup$lad23cd == "E08000013" | lkup$lad23cd == "E06000007" | lkup$lad23cd == "E08000015",] # Local Authority Codes in order are: Cheshire East, Cheshire West and Chester, Halton, Knowsley, Liverpool, Sefton, St Helens, Warrington, Wirral
write_parquet(unique_data <- unique(data, by = "TOID"), "./uprn_toid_cm_lkup.parquet") # Save lookup table
rm(lkup, lkup2) # Tidy
gc()

# Create a Cheshire and Merseyside TOID dataset
uprn_cm <- read_parquet("./uprn_toid_cm_lkup.parquet") # Load UPRN to TOID lookup
toid_cm <- unique(uprn_cm, by = "TOID") # Aggregate to unique TOID values (as duplicate values for each UPRN)
toid_cm <- toid_cm[, 2:3] # Delete the UPRN column
toid_cm <- merge(toid_cm, toid, by = "TOID", all.x = TRUE) # Join on the spatial locations of TOIDs
toid_cm <- toid_cm[!is.na(toid_cm$EASTING)] # Drop if missing location (n=20)
write_parquet(toid_cm, "./toids_cm_osgb.parquet") # Save
rm(toid, uprn_cm) # tidy
gc()

# Convert file into latitude and longitude (necessary for Google Earth Engine)
toid_sf <- st_as_sf(toid_cm, coords = c("EASTING", "NORTHING"), crs = 27700) # Convert to an sf object
toid_sf <- st_transform(toid_sf, crs = 4326) # Transform the coordinates to WGS84
toid_cm$latitude <- st_coordinates(toid_sf)[, 2] # Extract the latitude and longitude
toid_cm$longitude <- st_coordinates(toid_sf)[, 1]
write_parquet(toid_cm, "./toids_cm.parquet") # Save
rm(toid_sf, toid_cm) # Tidy
gc()

# Calculate buffers around the points
sf_use_s2(TRUE) # USe s2 for better buffers
toid_cm <- read_parquet("./toids_cm_osgb.parquet")
toid_sf <- st_as_sf(toid_cm, coords = c("EASTING", "NORTHING"), crs = 27700) # Convert to an sf object
toid_buffer <- st_buffer(toid_sf, dist = 300) # Generate 300m buffers (~70 seconds)
toid_buffer <- st_transform(toid_buffer, crs = 4326) # Convert to WGS84 for Google Earth Engine purposes (~60 seconds)
# Drop variables not required
# write_sf(toid_buffer, "./toids_cm_buffer.geojson") # Save
write_sf(toid_buffer, "./toids_cm_buffer.shp") # Save
rm(toid_sf, toid_cm, toid_buffer) # Tidy
gc()

# Split into Local Authorities
toid_buffer <- read_sf("./toids_cm_buffer.shp") # Load data
temp <- toid_buffer[toid_buffer$lad23cd == "E06000006",] # Split out data
write_sf(temp, "./toid_buffers_by_lad/toid_buffer_E06000006.shp") # Save
temp <- toid_buffer[toid_buffer$lad23cd == "E06000007",] # Repeat process one-by-one
write_sf(temp, "./toid_buffers_by_lad/toid_buffer_E06000007.shp")
temp <- toid_buffer[toid_buffer$lad23cd == "E06000049",] 
write_sf(temp, "./toid_buffers_by_lad/toid_buffer_E06000049.shp")
temp <- toid_buffer[toid_buffer$lad23cd == "E06000050",] 
write_sf(temp, "./toid_buffers_by_lad/toid_buffer_E06000050.shp")
temp <- toid_buffer[toid_buffer$lad23cd == "E08000011",] 
write_sf(temp, "./toid_buffers_by_lad/toid_buffer_E08000011.shp")
temp <- toid_buffer[toid_buffer$lad23cd == "E08000012",] 
write_sf(temp, "./toid_buffers_by_lad/toid_buffer_E08000012.shp")
temp <- toid_buffer[toid_buffer$lad23cd == "E08000013",] 
write_sf(temp, "./toid_buffers_by_lad/toid_buffer_E08000013.shp")
temp <- toid_buffer[toid_buffer$lad23cd == "E08000014",] 
write_sf(temp, "./toid_buffers_by_lad/toid_buffer_E08000014.shp")
temp <- toid_buffer[toid_buffer$lad23cd == "E08000015",] 
write_sf(temp, "./toid_buffers_by_lad/toid_buffer_E08000015.shp")
rm(toid_buffer, temp)
gc()

