#!/bin/bash

set -e

# The name of the convert command is passed as an argument. Default is convert.
convert=$1 || convert="convert"

function asvars() {
  echo $1 | tr "," " "
}

function top_n_colors {
  image=$1
  n_colors=$2
  colors=$($convert $image -blur 0x8 -resize 100x100 -colors $n_colors -unique-colors -colorspace Lab txt:- | grep -oP 'cielab\(\K[^\)]+')
  for color in $colors; do echo $(asvars $color); done
}

function colordifference {
  # Compute the color difference between two colors in LAB space
  # The color difference is the Euclidean distance between the two colors in LAB space
  # The formula is: sqrt((L1 - L2)^2 + (a1 - a2)^2 + (b1 - b2)^2)
  # The function returns the color difference
  # Arguments: L1 a1 b1 L2 a2 b2
  echo "scale=4; sqrt(($1 - $4)^2 + ($2 - $5)^2 + ($3 - $6)^2)" | bc
}

function n_closest() {
  # Return the top closest colors in an image to a reference CIELAB color
  ref_lab="$1 $2 $3"

  # Image
  image=$4
  n=$5

  # Compute distances to the reference color and store it as a list of distances and colors
  declare -A top_colors

  while read color; do
    distance=$(colordifference $color $ref_lab)
    top_colors[$distance]=$color
  done < <(top_n_colors $image $n)

  # Sort by distances
  for distance in $(echo ${!top_colors[@]} | tr " " "\n" | sort -n); do
    echo ${top_colors[$distance]} $distance
  done
}

function rgb_norm {
  for param in "$@"; do
    echo "scale=10; $param / 255" | bc
  done
}

function rgb2lab {
  conversion_formula='%[fx:100*r],%[fx:256*(g-0.5)],%[fx:256*(b-0.5)]'
  srgb="srgb($1,$2,$3)"
  lab=$($convert -size 1x1 xc:$srgb -colorspace Lab -format $conversion_formula info:)
  echo $(asvars $lab)
}

function lab2rgb {
  conversion_formula='%[fx:round(255*u)],%[fx:round(255*(v/256+0.5))],%[fx:round(255*(w/256+0.5))]'
  lab="lab($1,$2,$3)"
  rgb=$($convert -size 1x1 xc:$lab -colorspace sRGB -format $conversion_formula info:)
  echo $(asvars $rgb)
}

function lab_denorm {
  # Denormalize a LAB color
  l=$(echo "scale=10; $1 * 100" | bc)
  a=$(echo "scale=10; $2 / 256 + 0.5" | bc)
  b=$(echo "scale=10; $3 / 256 + 0.5" | bc)
  echo "$l $a $b"
}

function lab_norm {
  # Normalize a LAB color
  l=$(echo "scale=10; $1 / 100" | bc)
  a=$(echo "scale=10; $2/ 256+0.5" | bc)
  b=$(echo "scale=10; $3/ 256+0.5" | bc)
  echo "$l $a $b"
}
