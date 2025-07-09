import numpy as np

def multiply(in_ar, out_ar, xoff, yoff, xsize, ysize, raster_xsize,raster_ysize, buf_radius, gt, **kwargs):
  NODATA = 0
  DATA_MIN = 1
  DATA_MAX = 255
  in_ar = np.ma.masked_equal(np.stack(in_ar, axis=1), NODATA)
  blended = np.clip(np.prod(in_ar / DATA_MAX, axis=1) * DATA_MAX, DATA_MIN, DATA_MAX)
  out_ar[:] = blended.filled(NODATA)
