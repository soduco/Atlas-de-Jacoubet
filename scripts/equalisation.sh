#!/bin/bash

: '
This script is used to transform images so that their background color matches a target color.
The method is very naive and consists of finding out the background color of the image, then warping all colors so that the background color matches the target color.
In details, the process is as follows:
1. Find out the background color of the image. This is done by extracting the dominant colors of the image and selecting the closest one to a reference background color.
2. Compute the scaling factors to transform the background color to the target background color.
3. Apply the scaling factors to the image to transform all colors.

An optional contrast enhancement can be applied to the image using the sigmoidal-contrast function from ImageMagick.

Usage: see the display_help function below.

Examples:
  - Transform the background color of an image to white:
    ./equalisation.sh -t 255,255,255 image.jpg

  - Transform the background color of an image to white with a contrast enhancement of 10%:
    ./equalisation.sh -t 255,255,255 -c 10 image.jpg

  - Transform the background color of multiple images to white:
    ./equalisation.sh -t 255,255,255 image1.jpg image2.jpg

  - Transform the background color of an image to white with a verbose output:
    ./equalisation.sh -t 255,255,255 -v image.jpg

Notes:
  - All color calculations are done in the CIELAB color space in the hope of achieving better color matching.
  - You need to have ImageMagick 6.x or above installed to run this script.
'

# ---
# Preliminary checks
# ---

set -e

# Ensure that ImageMagick is installed and chose either convert or magick depending on the version.
if ! command -v convert &>/dev/null; then
  if ! command -v magick &>/dev/null; then
    echo "Error: ImageMagick is not installed. Please install it, then try again." >&2
    exit 1
  else
    convert="magick"
  fi
else
  convert="convert"
fi

source $(dirname $0)/colourutil.sh $convert

mkdir -p equalisation

# ---
# CLI arguments parsing
# ---
function display_help() {
  echo "Transform images so that their background color matches a target color." >&2
  echo "Usage: $0 [options] file1 [file2 ...]" >&2
  echo "" >&2
  echo "Required:" >&2
  echo "  -t, --target <r,g,b>                Target background color (default: 255,255,255)" >&2
  echo "" >&2
  echo "Optional:" >&2
  echo "  -v, --verbose                       Show more information about the process" >&2
  echo "  -c, --contrast <value>              Contrast enhancement value (default: 0). See ImageMagick's 'Sigmoidal Non-linearity Contrast'." >&2
  echo "  -b, --background-reference <r,g,b>  Reference background color (default: 255,255,255). You typically don't want to set this parameter manually unless you really know what you are doing." >&2
  echo "  -h, --help                          Display this help message" >&2
  exit 1
}

# Lecture des paramètres en ligne de commande
options=$(getopt -o t:hvc:b: --long target:,help,verbose,contrast:,background-reference: -- "$@")
if [ $? -ne 0 ]; then display_help; fi

eval set -- "$options"

# Main parameters
VERBOSE=false
TARGET_BACKGROUND_COLOR='255,255,255'
BACKGROUND_REFERENCE_COLOR='255,255,255'
CONTRAST_ENHANCEMENT=0
COLOR_QUANTIZATION=5

while true; do
  case "$1" in
  -h | --help)
    display_help
    ;;
  -v | --verbose)
    VERBOSE=true
    shift
    ;;
  -t | --target)
    TARGET_BACKGROUND_COLOR="$2"
    shift 2
    ;;
  -c | --contrast)
    CONTRAST_ENHANCEMENT="$2"
    shift 2
    ;;
  -b | --background-reference)
    BACKGROUND_REFERENCE_COLOR="$2"
    shift 2
    ;;
  --)
    shift
    break
    ;;
  *)
    echo "Error: Invalid argument $1"
    display_help
    ;;
  esac
done

# If no files are provided, display help and exit immediately
if [[ $# -eq 0 ]]; then
  display_help
fi

# ---
# Sanity checks and initialization
# ---

# Create a function to parse a 'r,g,b' string into an array and check that the values are in the [0, 255] range
function parse_rgb {
  IFS=',' read -r r g b <<<"$1"
  if [[ $r -lt 0 || $r -gt 255 || $g -lt 0 || $g -gt 255 || $b -lt 0 || $b -gt 255 ]]; then
    echo "Error: Invalid RGB triplet $1. Please provide a valid RGB triplet separated by commas." >&2
    exit 1
  fi
  echo "$r $g $b"
}

# Try to parse the target background color as an RGB triplet and convert it to CIELAB
IFS=' ' read -r -a target_bg <<<$(parse_rgb $TARGET_BACKGROUND_COLOR)
IFS=' ' read -r -a target_bg_cielab <<<$(rgb2lab ${target_bg[@]})
IFS=' ' read -r -a target_bg_cielab_norm <<<$(lab_norm ${target_bg_cielab[@]})

# Try to parse the background reference color as an RGB triplet and convert it to CIELAB
IFS=' ' read -r -a bg_ref <<<$(parse_rgb $BACKGROUND_REFERENCE_COLOR)
IFS=' ' read -r -a bg_ref_cielab <<<$(rgb2lab ${bg_ref[@]})

if [[ $VERBOSE == true ]]; then
  echo "Target background color RGB(${target_bg[@]}); CIELAB(${target_bg_cielab[@]})"
  echo "Background reference color RGB(${bg_ref[@]}); CIELAB(${bg_ref_cielab[@]})"
fi

# ---
# Main processing loop
# ---

for img in "$@"; do
  if [[ ! -f $img ]]; then
    echo "Error: File $img does not exist." >&2
    exit 1
  fi
  base_name=$(basename "$img")

  # Crop the image to remove a margin of $margin% around the image
  margin=30 # Example: 10%
  dimensions=$(identify -format "%wx%h" "$img")
  width=$(echo $dimensions | cut -d 'x' -f 1)
  height=$(echo $dimensions | cut -d 'x' -f 2)
  convert "$img" -shave $(($width * $margin / 100))x$(($height * $margin / 100)) /tmp/"$base_name"

  cropped="/tmp/$base_name"

  # Find out the background color of the image.
  # We first exact the dominant colors, and consider the closest one (in CIELAB) to the reference background color to be the actual background color of the image.
  # All colors in the image are then transformed so this background color matches the target background color.
  IFS=' ' read -r -a image_bg <<<$(n_closest ${bg_ref_cielab[@]} $cropped $COLOR_QUANTIZATION)

  # Normalize CIELAB values of the background color
  IFS=' ' read -r -a image_bg_norm <<<$(lab_norm ${image_bg[@]})

  scale=(1 1 1)
  for i in "${!target_bg_cielab_norm[@]}"; do
    # Use bc for floating-point division
    if [[ $(echo "${image_bg_norm[i]} == 0" | bc) -eq 1 ]]; then
      echo "Error: Division by zero at index $i" >&2
      scale[i]=0
    else
      # Perform floating-point division
      scale[i]=$(echo "scale=4; ${target_bg_cielab_norm[i]} / ${image_bg_norm[i]}" | bc)
    fi
  done

  # # DEBUG : save and transform the closest colors to the reference background color
  # # closest color is a list of 4*n elements, where n is the number of closest colors (in CIELAB space)
  # closest_colors_array=($(n_closest ${bg_ref_cielab[@]} $img $COLOR_QUANTIZATION))
  # for ((i = 0; i < ${#closest_colors_array[@]}; i += 4)); do
  #   $convert -size 100x100 xc:"lab(${closest_colors_array[i]},${closest_colors_array[i + 1]},${closest_colors_array[i + 2]})" color_$((i / 4)).jpg
  #   # Apply the color transformation to small "color_$i.jpg" images
  #   $convert "color_$((i / 4)).jpg" -colorspace LAB \
  #     -color-matrix "${scale[0]} 0 0 0 ${scale[1]} 0 0 0 ${scale[2]}" \
  #     -set colorspace LAB -colorspace sRGB \
  #     -sigmoidal-contrast "$CONTRAST_ENHANCEMENT" \
  #     "color_t_$((i / 4)).jpg"
  # done

  # Apply the color transformation to the image
  # Out-of-gamut colors will be clamped to the nearest valid color
  # Possible improvements: enable setting a ICC profile for a more accurate color transformation
  $convert "$img" -colorspace LAB \
    -color-matrix "${scale[0]} 0 0 0 ${scale[1]} 0 0 0 ${scale[2]}" \
    -set colorspace LAB -colorspace sRGB \
    -clamp \
    -sigmoidal-contrast "$CONTRAST_ENHANCEMENT" \
    "equalisation/$base_name"

    
  if [[ $VERBOSE == true ]]; then
    echo "Background color of $img: ${image_bg[@]}"
    echo "Scale factors: ${scale[@]}"
    echo "Contrast enhancement: $CONTRAST_ENHANCEMENT"
    echo "Output image saved to equalisation/$base_name"
  fi

done
