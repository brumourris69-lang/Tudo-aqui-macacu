'use strict';

const { PUBLIC_COLLECTIONS } = require('./content_visibility');

const JOB_FIELDS = new Set(('title name description shortDescription category subcategory location address ' +
  'artwork icon iconKey imageUrl logoUrl galleryUrls company type employmentType ' +
  'published active expiresAt').split(' '));

const COLLECTION_FIELDS = Object.freeze({
  establishments: new Set(('name title category subcategory description shortDescription location address ' +
    'artwork iconKey imageUrl logoUrl galleryUrls featured open hours services products additionalInfo ' +
    'promotionTitle promotionDescription published active expiresAt createdAt updatedAt maps mapsUrl ' +
    'phone whatsapp instagram').split(' ')),
  routes: new Set(('title name description shortDescription category type location address imageUrl galleryUrls ' +
    'additionalInfo maps mapsUrl link published active expiresAt createdAt updatedAt').split(' ')),
  utilities: new Set(('name title iconKey description category order destinationType destination active published ' +
    'expiresAt updatedAt').split(' ')),
  jobs: JOB_FIELDS,
});

const LEGACY_FIELDS = new Set(('title name description shortDescription category subcategory location address ' +
  'artwork icon iconKey imageUrl logoUrl galleryUrls link url maps mapsUrl whatsapp phone instagram ' +
  'hours services products additionalInfo promotionTitle promotionDescription featured open ' +
  'published active expiresAt updatedAt createdAt eventDate date startsAt contact company salary ' +
  'type employmentType options order destination destinationType discount price originalPrice ' +
  'code business businessId establishmentId validUntil rules buttonLabel label subtitle').split(' '));

const STRING_LIMITS = Object.freeze({
  title: 140, name: 140, category: 120, subcategory: 120, type: 64,
  description: 3000, shortDescription: 1000, location: 240, address: 240,
  imageUrl: 2048, logoUrl: 2048, maps: 2048, mapsUrl: 2048, link: 2048,
  icon: 64, iconKey: 64, hours: 500, additionalInfo: 3000,
  promotionTitle: 180, promotionDescription: 1000,
  destinationType: 32, destination: 2048, company: 160, employmentType: 120,
});

const BOOLEAN_FIELDS = new Set(['featured', 'open', 'published', 'active']);
const TIMESTAMP_FIELDS = new Set(['expiresAt', 'createdAt', 'updatedAt']);
const UTILITY_INTERNAL_DESTINATIONS = new Set([
  'waterEnergy', 'transport', 'trash', 'usefulPhones', 'coupons', 'alerts',
  'pharmacyDuty', 'emergency', 'resolver', 'publicPlaces', 'events', 'tourism',
  'map', 'news', 'polls', 'businessProposal', 'health', 'healthContent', 'cityHall',
  'water', 'energy',
]);

function encodedTimestamp(value) {
  return { _publicTimestamp: [value.seconds, value.nanoseconds] };
}

function validHttps(value) {
  if (typeof value !== 'string' || value.length > 2048) return false;
  try {
    const url = new URL(value.trim());
    return url.protocol === 'https:' && Boolean(url.hostname) && !url.username && !url.password;
  } catch { return false; }
}

function validMap(value) {
  if (validHttps(value)) return true;
  if (typeof value !== 'string' || value.length > 2048) return false;
  try {
    const url = new URL(value.trim());
    return url.protocol === 'geo:' && Boolean(url.pathname.trim()) && !url.username && !url.password;
  } catch { return false; }
}

function validPhone(value) {
  if (typeof value !== 'string' || !/^\+?[\d\s().-]+$/.test(value.trim())) return false;
  const digits = value.replace(/\D/g, '');
  return digits.length >= 8 && digits.length <= 15;
}

function validWhatsApp(value) {
  if (validPhone(value)) return true;
  if (typeof value !== 'string' || value.length > 2048) return false;
  try {
    const url = new URL(value.trim());
    return url.protocol === 'https:' && url.hostname.toLowerCase() === 'wa.me' &&
      !url.username && !url.password && /^\/\d{8,15}$/.test(url.pathname) &&
      !url.search && !url.hash;
  } catch { return false; }
}

function validInstagram(value) {
  if (typeof value !== 'string' || value.trim().length > 2048) return false;
  const text = value.trim();
  if (/^@?[A-Za-z0-9._]{1,30}$/.test(text)) return true;
  try {
    const url = new URL(text);
    return url.protocol === 'https:' && ['instagram.com', 'www.instagram.com'].includes(url.hostname.toLowerCase()) &&
      !url.username && !url.password && /^\/[A-Za-z0-9._]{1,30}\/?$/.test(url.pathname) &&
      !url.search && !url.hash;
  } catch { return false; }
}

function validUtilityDestination(type, destination) {
  if (typeof type !== 'string' || typeof destination !== 'string' || !destination.trim()) return false;
  const value = destination.trim();
  switch (type) {
    case 'internal': return UTILITY_INTERNAL_DESTINATIONS.has(value);
    case 'url': return validHttps(value);
    case 'phone': return validPhone(value);
    case 'whatsapp': return validWhatsApp(value);
    case 'map': return validMap(value);
    default: return false;
  }
}

function encodeLegacy(value, isTimestamp, depth = 0) {
  if (isTimestamp(value)) return encodedTimestamp(value);
  if (typeof value === 'string') return value.slice(0, 4096);
  if (typeof value === 'boolean' || (typeof value === 'number' && Number.isFinite(value))) return value;
  if (Array.isArray(value) && depth < 2) return value.slice(0, 40).map(item => encodeLegacy(item, isTimestamp, depth + 1));
  return null;
}

function projectLegacy(data, isTimestamp) {
  return Object.fromEntries(Object.entries(data).filter(([key]) => LEGACY_FIELDS.has(key))
    .map(([key, value]) => [key, encodeLegacy(value, isTimestamp)]));
}

function projectTarget(data, isTimestamp, collection) {
  if (collection === 'utilities' && !validUtilityDestination(data.destinationType, data.destination)) return null;
  const fields = COLLECTION_FIELDS[collection];
  const approvedContacts = collection === 'establishments' && data.publicContactApproved === true;
  const output = {};
  for (const [key, value] of Object.entries(data)) {
    if (!fields.has(key)) continue;
    if (['phone', 'whatsapp', 'instagram'].includes(key)) {
      if (!approvedContacts) continue;
      const valid = key === 'phone' ? validPhone(value) : key === 'whatsapp'
        ? validWhatsApp(value) : validInstagram(value);
      if (!valid) continue;
    }
    if (key === 'maps' || key === 'mapsUrl') {
      if (!validMap(value)) continue;
      output[key] = value.trim();
      continue;
    }
    if (key === 'link' && !validHttps(value)) continue;
    if (key === 'imageUrl' || key === 'logoUrl') {
      if (!validHttps(value)) continue;
      output[key] = value.trim();
      continue;
    }
    if (key === 'galleryUrls') {
      if (!Array.isArray(value)) continue;
      const limit = collection === 'routes' ? 3 : 20;
      const images = value.filter(validHttps).slice(0, limit).map(item => item.trim());
      if (images.length) output[key] = images;
      continue;
    }
    if (BOOLEAN_FIELDS.has(key)) {
      if (typeof value === 'boolean') output[key] = value;
      continue;
    }
    if (key === 'order' || key === 'artwork') {
      if (Number.isSafeInteger(value)) output[key] = value;
      continue;
    }
    if (TIMESTAMP_FIELDS.has(key)) {
      if (isTimestamp(value)) output[key] = encodedTimestamp(value);
      else if (typeof value === 'string' && value.length <= 64) output[key] = value;
      continue;
    }
    if (['services', 'products'].includes(key)) {
      if (Array.isArray(value)) {
        const items = value.filter(item => typeof item === 'string').slice(0, 40).map(item => item.slice(0, 160));
        if (items.length) output[key] = items;
      }
      continue;
    }
    if (typeof value === 'string') output[key] = value.slice(0, STRING_LIMITS[key] || 4096);
  }
  return output;
}

function projectPublic(data, isTimestamp, collection) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) return null;
  if (Object.hasOwn(COLLECTION_FIELDS, collection)) return projectTarget(data, isTimestamp, collection);
  return projectLegacy(data, isTimestamp);
}

module.exports = {
  COLLECTION_FIELDS,
  JOB_FIELDS,
  projectPublic,
  validHttps,
  validMap,
  validPhone,
  validWhatsApp,
  validInstagram,
  validUtilityDestination,
};
