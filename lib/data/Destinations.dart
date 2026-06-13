// lib/data/destinations.dart

class Destination {
  final String name;
  final String area;
  final double lat;
  final double lng;
  final String localTip;

  const Destination({
    required this.name,
    required this.area,
    required this.lat,
    required this.lng,
    required this.localTip,
  });
}

const List<Destination> kDestinations = [
  Destination(
    name: 'Marina Beach',
    area: 'Central Chennai',
    lat: 13.0500,
    lng: 80.2824,
    localTip: 'Visit before 8 AM or after 5 PM — gets extremely crowded midday on weekends. Evenings are magical.',
  ),
  Destination(
    name: 'T. Nagar Bus Terminus',
    area: 'T. Nagar',
    lat: 13.0418,
    lng: 80.2341,
    localTip: 'Shops open around 10 AM. Avoid Saturday evenings — the crowd on Pondy Bazaar is intense.',
  ),
  Destination(
    name: 'Chennai Central Station',
    area: 'Park Town',
    lat: 13.0827,
    lng: 80.2752,
    localTip: 'Platform numbers change last minute. Check the display boards near the entrance, not just the ticket.',
  ),
  Destination(
    name: 'Chennai Egmore Station',
    area: 'Egmore',
    lat: 13.0785,
    lng: 80.2613,
    localTip: 'Most south-bound trains leave from here. Auto stand right outside — negotiate the fare first.',
  ),
  Destination(
    name: 'Koyambedu Bus Terminus',
    area: 'Koyambedu',
    lat: 13.0694,
    lng: 80.1948,
    localTip: 'Largest bus terminal in Asia! Platforms are numbered — check the board near Gate 1 for your route.',
  ),
  Destination(
    name: 'Chennai Airport (MAA)',
    area: 'Tirusulam',
    lat: 12.9941,
    lng: 80.1709,
    localTip: 'Take Bus 70 or 70K from Koyambedu for cheap travel. Allow at least 90 mins during peak hours.',
  ),
  Destination(
    name: 'Anna Nagar Tower',
    area: 'Anna Nagar',
    lat: 13.0891,
    lng: 80.2094,
    localTip: 'The tower park is a peaceful spot. 2nd Avenue has the best bakeries — try Krispy\'s.',
  ),
  Destination(
    name: 'Adyar Signal',
    area: 'Adyar',
    lat: 13.0012,
    lng: 80.2565,
    localTip: 'Adyar Ananda Bhavan (A2B) nearby is a must for South Indian breakfast.',
  ),
  Destination(
    name: 'Velachery Bus Terminus',
    area: 'Velachery',
    lat: 12.9815,
    lng: 80.2209,
    localTip: 'Phoenix MarketCity is a 10-min walk. MRTS Velachery station is right next to the terminus.',
  ),
  Destination(
    name: 'Tambaram Bus Terminus',
    area: 'Tambaram',
    lat: 12.9249,
    lng: 80.1000,
    localTip: 'Busy hub — expect delays from 8-10 AM and 5-8 PM. SRM and Sathyabama college buses crowd this.',
  ),
  Destination(
    name: 'Guindy National Park',
    area: 'Guindy',
    lat: 13.0067,
    lng: 80.2206,
    localTip: 'Open Tuesday to Sunday. Entry is very cheap. Go early morning to spot deer and blackbucks.',
  ),
  Destination(
    name: 'Spencer Plaza',
    area: 'Anna Salai',
    lat: 13.0635,
    lng: 80.2623,
    localTip: 'One of India\'s oldest malls. Underground floor has budget shops. AC is heavenly on summer days.',
  ),
  Destination(
    name: 'Express Avenue Mall',
    area: 'Royapettah',
    lat: 13.0559,
    lng: 80.2639,
    localTip: 'Free parking on weekdays before 11 AM. Food court on 3rd floor is the best in the area.',
  ),
  Destination(
    name: 'Phoenix MarketCity',
    area: 'Velachery',
    lat: 12.9921,
    lng: 80.2209,
    localTip: 'Weekday afternoons are bliss — zero crowd. Weekends after 4 PM is parking nightmare.',
  ),
  Destination(
    name: 'VGP Universal Kingdom',
    area: 'ECR',
    lat: 12.9345,
    lng: 80.2523,
    localTip: 'Rides are fun but pricy. The beach section is free. Go on weekdays to avoid massive queues.',
  ),
  Destination(
    name: 'Kapaleeshwarar Temple',
    area: 'Mylapore',
    lat: 13.0334,
    lng: 80.2691,
    localTip: 'Remove footwear at the entrance. Best visited during early morning pooja (6–7 AM). Photography restricted inside.',
  ),
  Destination(
    name: 'Santhome Cathedral',
    area: 'Santhome',
    lat: 13.0338,
    lng: 80.2787,
    localTip: 'Beautiful Gothic architecture. Entry free. The underground museum of St. Thomas is worth visiting.',
  ),
  Destination(
    name: 'Ripon Building (Corporation)',
    area: 'Park Town',
    lat: 13.0839,
    lng: 80.2703,
    localTip: 'One of Chennai\'s most iconic colonial buildings. Snap photos from the outside — great architecture.',
  ),
  Destination(
    name: 'Government Museum',
    area: 'Egmore',
    lat: 13.0700,
    lng: 80.2586,
    localTip: 'Second oldest museum in India! The Bronze gallery is world-class. Closed on Fridays.',
  ),
  Destination(
    name: 'Valluvar Kottam',
    area: 'Nungambakkam',
    lat: 13.0573,
    lng: 80.2439,
    localTip: 'Peaceful monument. The 133-couplet stone inscription is stunning. Best for morning walks.',
  ),
  Destination(
    name: 'IIT Madras Main Gate',
    area: 'Adyar',
    lat: 12.9916,
    lng: 80.2337,
    localTip: 'Deer roam freely inside! Entry with ID during Research Park events. Saarang & Shaastra are public festivals.',
  ),
  Destination(
    name: 'Anna University Main Gate',
    area: 'Guindy',
    lat: 13.0105,
    lng: 80.2350,
    localTip: 'Nice campus for a walk. The lake inside is beautiful. TASMAC nearby if that\'s your thing.',
  ),
  Destination(
    name: 'Loyola College',
    area: 'Nungambakkam',
    lat: 13.0693,
    lng: 80.2406,
    localTip: 'Beautiful campus. Fest season (Jan–Feb) has great cultural shows open to public.',
  ),
  Destination(
    name: 'Sholinganallur Signal',
    area: 'Sholinganallur',
    lat: 12.9010,
    lng: 80.2279,
    localTip: 'IT corridor hub. Traffic is brutal 8:30–10 AM. Best to take the service road during peak hours.',
  ),
  Destination(
    name: 'Tidel Park',
    area: 'Taramani',
    lat: 12.9900,
    lng: 80.2439,
    localTip: 'Huge IT park. The food court inside is open to visitors. Good shortcut through OMR.',
  ),
  Destination(
    name: 'Perungudi Toll',
    area: 'Perungudi',
    lat: 12.9641,
    lng: 80.2390,
    localTip: 'Traffic peak is 9 AM and 7 PM. Buses on the IT corridor are fastest mid-morning.',
  ),
  Destination(
    name: 'Thiruvanmiyur Beach',
    area: 'Thiruvanmiyur',
    lat: 12.9827,
    lng: 80.2707,
    localTip: 'Less crowded than Marina. Locals come here for evening walks. Decent street food nearby.',
  ),
  Destination(
    name: 'Besant Nagar Beach (Elliot\'s)',
    area: 'Besant Nagar',
    lat: 13.0002,
    lng: 80.2700,
    localTip: 'Chennai\'s cleanest beach. The Ashtalakshmi Temple nearby is beautiful. Evenings get very crowded on weekends.',
  ),
  Destination(
    name: 'Porur Signal',
    area: 'Porur',
    lat: 13.0358,
    lng: 80.1573,
    localTip: 'Chennai\'s worst traffic junction. Avoid 8:30–10:30 AM and 6–8 PM. The lake nearby is lovely.',
  ),
  Destination(
    name: 'Chromepet Bus Stand',
    area: 'Chromepet',
    lat: 12.9516,
    lng: 80.1462,
    localTip: 'Well-connected to airport and Tambaram. Auto stand here is good for last-mile to Pallavaram.',
  ),
];

// ── Offline fallback: curated journeys for when API is unavailable ────────────

class JourneyStep {
  final String type; // 'walk', 'bus', 'train', 'metro'
  final String instruction;
  final String? lineName;

  const JourneyStep({
    required this.type,
    required this.instruction,
    this.lineName,
  });
}

class Journey {
  final List<JourneyStep> steps;
  final String totalTime;

  const Journey({required this.steps, required this.totalTime});
}

// Key format: "ORIGIN_AREA|DESTINATION_NAME"
const Map<String, Journey> kJourneys = {
  'Chromepet|Marina Beach': Journey(
    totalTime: '55 mins',
    steps: [
      JourneyStep(type: 'bus', instruction: 'Take Bus 21D from Chromepet Bus Stand', lineName: '21D'),
      JourneyStep(type: 'walk', instruction: 'Walk 300m to Marina Beach entrance'),
    ],
  ),
  'Velachery|Chennai Central Station': Journey(
    totalTime: '45 mins',
    steps: [
      JourneyStep(type: 'train', instruction: 'Take MRTS from Velachery to Chennai Beach', lineName: 'MRTS'),
      JourneyStep(type: 'bus', instruction: 'Take Bus 27 to Central Station', lineName: '27'),
    ],
  ),
  'Sholinganallur|Koyambedu Bus Terminus': Journey(
    totalTime: '60 mins',
    steps: [
      JourneyStep(type: 'bus', instruction: 'Take Bus M70 from Sholinganallur', lineName: 'M70'),
      JourneyStep(type: 'walk', instruction: 'Walk to Koyambedu Terminus main gate'),
    ],
  ),
};