#!/bin/bash

FILES=`pwd`/*.shp

for file in $FILES
do
    echo $(basename $file)
    filename=${file%.shp}
    base=`basename $filename`
    echo $base
    ogr2ogr -f "CSV" -overwrite -dialect sqlite -sql "select ST_X(geometry) AS X, -ST_Y(geometry) AS Y, numero FROM '$base'" $filename.csv $file 
done
