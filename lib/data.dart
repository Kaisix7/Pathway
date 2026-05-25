import 'models.dart';

// ALMATY
const iinCentersAlmaty = <IinCenter>[
  IinCenter(
    id: 'bostandyk',
    name: 'PSC / ЦОН Bostandyk',
    address: 'Microdistrict Almagul, 9A, Almaty',
    district: 'Bostandyk',
    lat: 43.2349,
    lng: 76.9099,
  ),
  IinCenter(
    id: 'zhetysu',
    name: 'PSC / ЦОН Zhetysu',
    address: 'Serikova St, 6A, Almaty',
    district: 'Zhetysu',
    lat: 43.3082,
    lng: 76.9105,
  ),
  IinCenter(
    id: 'turksib',
    name: 'PSC / ЦОН Turksib',
    address: 'Richard Sorge St, 9, Almaty',
    district: 'Turksib',
    lat: 43.3525,
    lng: 77.0014,
  ),
];

// NUR-SULTAN
const iinCentersNurSultan = <IinCenter>[
  IinCenter(
    id: 'ns_saryarka',
    name: 'PSC / ЦОН Saryarka',
    address: 'Mangilik El Ave, Nur-Sultan',
    district: 'Saryarka',
    lat: 51.1694,
    lng: 71.4491,
  ),
  IinCenter(
    id: 'ns_akmola',
    name: 'PSC / ЦОН Akmola',
    address: 'Abai St, 11, Nur-Sultan',
    district: 'Akmola',
    lat: 51.1801,
    lng: 71.4475,
  ),
  IinCenter(
    id: 'ns_central',
    name: 'PSC / ЦОН Central',
    address: 'Ishim St, 5, Nur-Sultan',
    district: 'Central',
    lat: 51.1694,
    lng: 71.4700,
  ),
];

// SHYMKENT
const iinCentersShymkent = <IinCenter>[
  IinCenter(
    id: 'shym_abay',
    name: 'PSC / ЦОН Abay District',
    address: 'Abay Ave, 105, Shymkent',
    district: 'Abay',
    lat: 42.2996,
    lng: 69.5878,
  ),
  IinCenter(
    id: 'shym_alatau',
    name: 'PSC / ЦОН Alatau District',
    address: 'Maulenov St, 45, Shymkent',
    district: 'Alatau',
    lat: 42.3125,
    lng: 69.5680,
  ),
];

// KARAGANDA
const iinCentersKaraganda = <IinCenter>[
  IinCenter(
    id: 'kara_central',
    name: 'PSC / ЦОН Central',
    address: 'Bukhar Zhyrau St, 38, Karaganda',
    district: 'Central',
    lat: 49.8047,
    lng: 72.1348,
  ),
];

// Available cities map
const Map<String, List<IinCenter>> iinCentersByCity = {
  'Almaty': iinCentersAlmaty,
  'Nur-Sultan': iinCentersNurSultan,
  'Shymkent': iinCentersShymkent,
  'Karaganda': iinCentersKaraganda,
};

const List<String> kazakhCities = [
  'Almaty',
  'Nur-Sultan',
  'Shymkent',
  'Karaganda',
];

final housingItems = <HousingItem>[
  HousingItem(
    id: 'h1',
    title: 'Student Dormitory',
    address: 'Satbayev Street',
    district: 'Bostandyk',
    type: HousingType.dorm,
    priceKztMonthly: 50000,
    verified: true,
    rating: 4.3,
  ),
  HousingItem(
    id: 'h2',
    title: 'Budget Hotel',
    address: 'Abay Avenue',
    district: 'Almaly',
    type: HousingType.hotel,
    priceKztMonthly: 120000,
    verified: true,
    rating: 4.6,
  ),
  HousingItem(
    id: 'h3',
    title: '1-room Apartment',
    address: 'Tastak',
    district: 'Almaly',
    type: HousingType.apartment,
    priceKztMonthly: 180000,
    verified: false,
    rating: 4.1,
  ),
  HousingItem(
    id: 'h4',
    title: 'University Dorm',
    address: 'Al-Farabi Avenue',
    district: 'Bostandyk',
    type: HousingType.dorm,
    priceKztMonthly: 60000,
    verified: true,
    rating: 4.4,
  ),
];