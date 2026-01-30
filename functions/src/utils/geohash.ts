const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

export function encodeGeohash(
  latitude: number,
  longitude: number,
  precision = 7
): string {
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    return "";
  }

  let minLat = -90.0;
  let maxLat = 90.0;
  let minLng = -180.0;
  let maxLng = 180.0;

  let bits = 0;
  let hashValue = 0;
  let isEven = true;
  let hash = "";

  while (hash.length < precision) {
    if (isEven) {
      const mid = (minLng + maxLng) / 2;
      if (longitude >= mid) {
        hashValue = (hashValue << 1) + 1;
        minLng = mid;
      } else {
        hashValue = (hashValue << 1);
        maxLng = mid;
      }
    } else {
      const mid = (minLat + maxLat) / 2;
      if (latitude >= mid) {
        hashValue = (hashValue << 1) + 1;
        minLat = mid;
      } else {
        hashValue = (hashValue << 1);
        maxLat = mid;
      }
    }

    isEven = !isEven;
    bits++;

    if (bits === 5) {
      hash += BASE32[hashValue];
      bits = 0;
      hashValue = 0;
    }
  }

  return hash;
}
