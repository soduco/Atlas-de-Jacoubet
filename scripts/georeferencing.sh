#!/bin/bash

# Create the output directory if it doesn't exist
mkdir -p georef

# Loop through each JPG file in the current directory
for jpg_file in equalisation/*.jpg; do
    
    # Check if the file exists and is readable
    if [[ -f "$jpg_file" && -r "$jpg_file" ]]; then
        # Extract the base filename (e.g., "a" from "a.jpg")
        base_name=$(basename "$jpg_file" .jpg)

        # Define the corresponding GCP file path
        gcp_file="gcps/$base_name.jpg.points"

        # Check if the GCP file exists
        if [[ -f "$gcp_file" ]]; then
            echo "Processing $jpg_file with GCPs from $gcp_file"

            # Initialize an array to store GCP parameters
            gcp_params=()

            # Skip the first two lines of the GCP file (CRS and headers)
            # Read GCPs and populate gcp_params array
            {
                read # Skip first line (CRS)
                read # Skip second line (header)
                while IFS=',' read -r map_x map_y pixel_x pixel_y _; do
                    # Add each GCP as "-gcp pixel_x pixel_y map_x map_y 0" to the array
                    gcp_params+=("-gcp" "$pixel_x" "${pixel_y#-}" "$map_x" "$map_y" "0")
                done
            } <"$gcp_file"

            # Define the intermediate file path
            temp_file="georef/${base_name}_temp"
            output_file="georef/${base_name}_georef.tif"

            # Slightly brighten the image using gdal_calc.py to free 0 value for NoData
            gdal_calc -A "$jpg_file" --overwrite --calc="numpy.clip(numpy.ma.masked_greater(A, 255) + 1 , 0, 255)" --outfile="$temp_file"_0.tif --type=Byte --NoDataValue=0

            # Run gdal_translate to add GCPs to the image
            gdal_translate -of GTiff -a_nodata 0 "${gcp_params[@]}" "$temp_file"_0.tif "$temp_file"_1.tif

            #Double single quotes to escape the, ' becomes ''
            sheet_name_escaped=$(echo "$base_name" | sed "s/'/''/g")

            gdalwarp -r cubic -tps -co COMPRESS=LZW  \
                -t_srs '+proj=aeqd +lat_0=48.83635863 +lon_0=2.33652533 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +to_meter=1.94903631 +no_defs +type=crs' \
                -srcnodata 0 \
                -overwrite \
                -cutline cutlines/cutlines_with_bumps.geojson -cwhere "sheet='$sheet_name_escaped'" \
                "$temp_file"_1.tif "$output_file"

            # Clean up temporary files
            rm "$temp_file"_0.tif "$temp_file"_1.tif

            echo "Output saved to $output_file"
        else
            echo "GCP file for $jpg_file not found at $gcp_file"
        fi
    else
        echo "$jpg_file is not readable or does not exist."
    fi
done

echo "Georeferencing completed."
