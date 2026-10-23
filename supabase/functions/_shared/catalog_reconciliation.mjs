import { projectCanonicalEstablishment } from './catalog_outbox_protocol.mjs';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

/**
 * Builds a read-only reconciliation report for one bounded snapshot page.
 * It never connects to either service and never applies the returned actions.
 * A destination tombstone is permanent: a live Firestore record is flagged for
 * manual review rather than being allowed to resurrect it.
 */
export function createCatalogReconciliationPlan({ canonicalDocuments, catalogRows, tombstones = [] }) {
  const canonical = indexById(canonicalDocuments, isCanonicalRecord);
  const catalog = indexById(catalogRows, isCatalogRow);
  const deleted = indexById(tombstones, isTombstone);
  assertUniqueCanonicalOperations(canonical.values());
  const ids = [...new Set([...canonical.keys(), ...catalog.keys(), ...deleted.keys()])].sort();
  const items = [];

  for (const id of ids) {
    const source = canonical.get(id);
    const row = catalog.get(id);
    const tombstone = deleted.get(id);
    if (!source) {
      items.push(item(id, 'canonical_missing', 'manual_review'));
      continue;
    }

    const version = source.data.catalogVersion;
    const operationId = source.data.outboxOperationId;
    const event = {
      schemaVersion: 2, operationId, entityType: 'establishment', entityId: id,
      authorUid: 'reconciliation-validation', version, operation: 'reconcile', state: 'pending', attemptCount: 0,
      workerId: null, leaseToken: null, leaseExpiresAt: null, nextAttemptAt: null,
      lastErrorCode: null, syncedAt: null, createdAt: new Date(0), updatedAt: new Date(0),
    };
    const projection = projectCanonicalEstablishment(id, source.data, event);
    if (!projection) {
      items.push(item(id, 'invalid_canonical', 'manual_review'));
      continue;
    }

    if (tombstone) {
      if (projection.deleted_at === null) {
        items.push(item(id, 'blocked_by_tombstone', 'manual_review'));
        continue;
      }
      if (tombstone.catalog_version > version) {
        items.push(item(id, 'destination_newer', 'manual_review'));
        continue;
      }
      const payload = tombstonePayload(projection);
      if (tombstone.catalog_version === version) {
        if (tombstone.outbox_operation_id !== operationId || tombstone.tombstoned_at !== projection.deleted_at) {
          items.push(item(id, 'version_conflict', 'manual_review'));
        } else if (row && (row.catalog_version !== version || row.outbox_operation_id !== operationId ||
          row.deleted_at !== projection.deleted_at)) {
          items.push(item(id, 'tombstone_projection_conflict', 'manual_review'));
        } else {
          items.push(item(id, 'in_sync_tombstone', 'none'));
        }
        continue;
      }
      items.push(item(id, 'tombstone_outdated', 'apply_tombstone', payload));
      continue;
    }

    if (projection.deleted_at !== null) {
      items.push(item(id, 'tombstone_missing', 'apply_tombstone', tombstonePayload(projection)));
      continue;
    }
    if (row?.deleted_at != null) {
      items.push(item(id, 'blocked_by_tombstone', 'manual_review'));
      continue;
    }
    if (!row) {
      items.push(item(id, 'projection_missing', 'apply_projection', projection));
      continue;
    }
    if (row.catalog_version > version) {
      items.push(item(id, 'destination_newer', 'manual_review'));
      continue;
    }
    if (row.catalog_version === version) {
      if (row.outbox_operation_id !== operationId || !sameProjection(row, projection)) {
        items.push(item(id, 'version_conflict', 'manual_review'));
      } else {
        items.push(item(id, 'in_sync', 'none'));
      }
      continue;
    }
    items.push(item(id, 'projection_outdated', 'apply_projection', projection));
  }

  const summary = {};
  for (const entry of items) summary[entry.status] = (summary[entry.status] ?? 0) + 1;
  return Object.freeze({
    items: Object.freeze(items.map((entry) => Object.freeze(entry))),
    summary: Object.freeze(Object.fromEntries(Object.entries(summary).sort(([a], [b]) => a.localeCompare(b)))),
  });
}

function tombstonePayload(projection) {
  return {
    id: projection.id,
    catalog_version: projection.catalog_version,
    outbox_operation_id: projection.outbox_operation_id,
    deleted_at: projection.deleted_at,
  };
}

function item(id, status, action, payload) {
  return { id, status, action, ...(payload ? { payload: structuredClone(payload) } : {}) };
}

function indexById(values, validate) {
  if (!Array.isArray(values)) throw reconciliationSnapshotError();
  const indexed = new Map();
  for (const value of values) {
    if (!validate(value) || indexed.has(value.id)) throw reconciliationSnapshotError();
    indexed.set(value.id, value);
  }
  return indexed;
}

function assertUniqueCanonicalOperations(records) {
  const operationIds = new Set();
  for (const record of records) {
    const operationId = record.data.outboxOperationId;
    if (typeof operationId !== 'string' || !UUID_PATTERN.test(operationId)) continue;
    if (operationIds.has(operationId)) throw reconciliationSnapshotError();
    operationIds.add(operationId);
  }
}

function isCanonicalRecord(value) {
  return plainObject(value) && typeof value.id === 'string' && value.id.length > 0 && plainObject(value.data);
}

function isCatalogRow(value) {
  return plainObject(value) && typeof value.id === 'string' && value.id.length > 0 &&
    Number.isSafeInteger(value.catalog_version) && value.catalog_version > 0 &&
    typeof value.outbox_operation_id === 'string' && UUID_PATTERN.test(value.outbox_operation_id);
}

function isTombstone(value) {
  return plainObject(value) && typeof value.id === 'string' && value.id.length > 0 &&
    Number.isSafeInteger(value.catalog_version) && value.catalog_version > 0 &&
    typeof value.outbox_operation_id === 'string' && UUID_PATTERN.test(value.outbox_operation_id) &&
    typeof value.tombstoned_at === 'string' && Number.isFinite(Date.parse(value.tombstoned_at));
}

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (plainObject(value)) {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function sameProjection(row, projection) {
  const selected = {};
  for (const key of Object.keys(projection)) {
    if (!Object.hasOwn(row, key)) return false;
    selected[key] = row[key];
  }
  return stableJson(selected) === stableJson(projection);
}

function plainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) &&
    (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
}

function reconciliationSnapshotError() {
  return Object.assign(new Error('Reconciliation snapshot is invalid.'), { code: 'invalid-reconciliation-snapshot' });
}
