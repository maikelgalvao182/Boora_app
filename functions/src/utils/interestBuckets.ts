const INTEREST_BUCKETS: Record<string, string[]> = {
  food: [
    "japanese",
    "pizza",
    "burgers",
    "pasta",
    "beer_pub",
    "wines",
    "sweets_cafes",
    "mexican",
    "healthy_food",
    "bbq",
    "vegetarian",
    "vegan",
    "food_markets",
  ],
  nightlife: [
    "live_music_bar",
    "cocktails",
    "karaoke",
    "nightclub",
    "standup_theater",
    "cinema",
    "board_games",
    "gaming",
    "themed_parties",
    "samba",
    "shopping",
  ],
  culture: [
    "museums",
    "book_club",
    "photography",
    "workshops",
    "concerts",
    "language_exchange",
    "film_screenings",
    "street_art",
  ],
  outdoor: [
    "light_trails",
    "parks",
    "beach",
    "bike",
    "climbing",
    "outdoor_activities",
    "pets",
    "sunset",
    "pool",
    "camping",
  ],
  sports: [
    "soccer",
    "basketball",
    "tennis",
    "beach_tennis",
    "skating",
    "running",
    "cycling",
    "gym",
    "light_activities",
  ],
  work: [
    "remote_work",
    "content_creators",
    "career_talks",
    "tech_innovation",
  ],
  wellness: [
    "yoga",
    "meditation",
    "pilates",
    "spa",
    "cold_plunge",
    "healthy_lifestyle",
    "relaxing_walks",
  ],
  values: [
    "lgbtqia",
    "sustainability",
    "volunteering",
    "animal_cause",
  ],
};

const INTEREST_ID_TO_BUCKET: Record<string, string> = {};
for (const [bucket, interests] of Object.entries(INTEREST_BUCKETS)) {
  for (const interest of interests) {
    INTEREST_ID_TO_BUCKET[interest] = bucket;
  }
}

export function normalizeInterestId(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.trim().toLowerCase();
}

export function buildInterestBuckets(interests: unknown): string[] {
  if (!Array.isArray(interests)) return [];
  const buckets = new Set<string>();
  for (const interest of interests) {
    const normalized = normalizeInterestId(interest);
    const bucket = INTEREST_ID_TO_BUCKET[normalized];
    if (bucket) {
      buckets.add(bucket);
    }
  }
  return Array.from(buckets);
}
