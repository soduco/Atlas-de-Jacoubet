# Atlas de Jacoubet

Ce dépot contient :
1. la numérisation des 54 feuilles de de l'atlas de Paris levé et dessiné au 1:2000e par l'architecte Théodore (Simon) Jacoubet entre 1827 et 1836. Les fichiers sont extraits des [planches numérisées par la Bibliothèque Historique de la Ville de Paris à partir de l'exemplaire FM AT 11](https://bibliotheques-specialisees.paris.fr/ark:/73873/pf0000858369).
2. les scripts et données support pour géoréférencer et assembler les feuilles aux format VRT et MBTILES.

## Source

| | |
|----|----|
|**Titre**|Atlas général de la Ville, des faubourgs et des monuments de Paris : 1836 / par Th. Jacoubet, architecte... ; gravé par Bonnet ; dédié et présenté à M. le Comte de Chabrol de Volvic, Conseiller d'Etat, Préfet du Département de la Seine ; écrit par Hacq. graveur du Dépot de la Guerre|
|**Temps valide**| 1827 - 1836|
|**Référence**|Bibliothèque Historique de la Ville de Paris, FM AT 11.|
|**Auteurs**|Théodore Simon Jacoubet (levé & dessin), Jacques Marie Hacq (lettre), V. Bonnet (gravure) |
|**Publication**|V. Bonnet|
|**Description**|1 atlas (54 f.) : non assemblées ; in-fol. (50 x 66,5 cm)|
|**Échelle**|1:2000 (cm)|

## Géoréférencer et assembler le plan de Jacoubet

Le dossiers `processing/` contient une suite de scripts pour construire le plan général de Paris complet et géoréférencé à partir des planches de l'atlas.

### Prérequis

Une fois le dépot téléchargé, autorisez l'exécution des fichiers de script dans le dossier `processing` :

```bash
cd ./Atlas-de-Jacoubet
chmod +x processing/georeference.sh processing/equalisation.sh processing/vrt.sh processing/mbtiles.sh
```

Les scripts nécessitent que les dépendances suivants sont installées sur  votre système :

|Dépendance|Motif|
|----|----|
|[ImageMagick](https://imagemagick.org/index.php)| Harmonisation colorimétrique des feuilles du plan |
|[GDAL](https://gdal.org)| Géoréférencement, construction des VRT et MBTiles|
|[Python](Python) + [Numpy](https://numpy.org)|Application de *pixel function* lors de la condtruction du VRT.|

Appliquez les traitements suivants dans l'ordre suivant. Il est possible de s'arrêter à n'importe quelle étape, par exemple après l'exécution de `vrt.sh`si l'on a pas besoin du plan assemblé au format MBTiles.

### 1. Égalisation colorimétrique des planches

Modifie les planches afin que le fond soit blanc.

```bash
scripts/equalisation.sh \
    -c 5,70% \
    -t 255,255,255 \
    -v *.jpg
```

### 2. Géoréférencement individuel des planches

```bash
scripts/georeferencing.sh
```

Notes :

- chaque planche sera découpée selon un fichier de masques dans de dossier `cutlines/`.
- pour réserver 0 comme valeur NODATA, les pixels sont légèrement décalés vers le blanc (+1 par défaut).
- le CRS des planches géoréférencé est le système de projection du plan de Verniquet, **en mètres et non en toises** :

```raw
+proj=aeqd +lat_0=48.83635863 +lon_0=2.33652533 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +no_defs +type=crs
```

### 3. Assemblage VRT

```bash
VRT='BHVP_FM_AT_11-Atlas_de_Jacoubet.vrt'

gdalbuildvrt $VRT -a_srs '+proj=aeqd +lat_0=48.83635863 +lon_0=2.33652533 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +no_defs +type=crs' georef/*.tif

# Insert the pixel blending function in the VRT
sed -i 's|<VRTRasterBand dataType="Byte" band="1">|<VRTRasterBand dataType="Byte" band="1" subClass="VRTDerivedRasterBand">\
<PixelFunctionLanguage>Python</PixelFunctionLanguage>\
<PixelFunctionType>blend_multiply</PixelFunctionType>\
<PixelFunctionCode><![CDATA[\
import numpy as np\
def blend_multiply(in_ar, out_ar, xoff, yoff, xsize, ysize, raster_xsize,raster_ysize, buf_radius, gt, **kwargs):\
  NODATA = 0\
  DATA_MIN = 1\
  DATA_MAX = 255\
  in_ar = np.ma.masked_equal(np.stack(in_ar, axis=1), NODATA)\
  blended = np.clip(np.prod(in_ar / DATA_MAX, axis=1) * DATA_MAX, DATA_MIN, DATA_MAX)\
  out_ar[:] = blended.filled(NODATA)\
]]></PixelFunctionCode>|' $VRT
```

Notes :

- en cas de superposition de plusieurs feuilles, un mélange multiplicatf est appliqué.

### 4. Assemblage MBTiles

```bash
MBTILES='BHVP_FM_AT_11-Atlas_de_Jacoubet.mbtiles'

GDAL_VRT_ENABLE_PYTHON=YES gdal_translate -of MBTiles -a_nodata 0 -a_srs '+proj=aeqd +lat_0=48.83635863 +lon_0=2.33652533 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +no_defs +type=crs' -co TILE_FORMAT=PNG $VRT $MBTILES

gdaladdo -r average $MBTILES 2 4 8 16 32
```

Notes :

- le CRS d'un fichier MBTile est toujours `EPSG:3857 WGS 84 / Pseudo-Mercator`