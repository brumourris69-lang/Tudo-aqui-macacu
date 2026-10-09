'use strict';
const PUBLIC_COLLECTIONS = [
  'establishments', 'ads', 'offers', 'coupons', 'routes', 'jobs', 'events', 'news',
  'utilities', 'alerts', 'polls', 'links', 'health', 'transport', 'trash_collection',
  'useful_phones', 'pharmacy_duties', 'emergency_contacts', 'resolver_subjects', 'public_places',
  'notifications',
];
function publiclyVisible(collection, data, now, isTimestamp) {
  if (!PUBLIC_COLLECTIONS.includes(collection) || !data) return false;
  if (collection === 'utilities') {
    if (data.active !== true || (Object.hasOwn(data, 'published') && data.published !== true)) return false;
  } else if (data.published !== true) return false;
  if (Object.hasOwn(data, 'active') && data.active !== true) return false;
  if (Object.hasOwn(data, 'expiresAt') &&
      (!isTimestamp(data.expiresAt) || data.expiresAt.toMillis() <= now)) return false;
  if (collection === 'notifications' && data.targetEmail !== '') return false;
  // No publication scheduling field exists in the current app. startsAt and
  // eventDate describe an event; publishedAt is audit, not a publication window.
  return true;
}
module.exports = { PUBLIC_COLLECTIONS, publiclyVisible };
