import { createGoogleAccessToken } from "./firebase_signing_keys.mjs";

const EXPECTED_PROJECT_ID = "tudo-aqui-macacu";
const EMULATOR_PROJECT_ID = "demo-universal-search";
const HOMOLOGATION_PROJECT_MARKER = /(?:^|-)staging(?:-|$)|(?:^|-)homologation(?:-|$)/u;
const DOCUMENT_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/u;
const COLLECTIONS = new Set([
  "admin_authorizations",
  "establishments",
  "catalog_outbox",
  "catalog_outbox_scan_state",
]);
const SERVER_TIMESTAMP_FIELDS = new Set([
  "createdAt",
  "updatedAt",
  "deletedAt",
]);
const MAX_OUTBOX_QUERY_PAGE_SIZE = 100;
const MAX_RECONCILIATION_QUERY_PAGE_SIZE = 200;
const DEFAULT_REQUEST_TIMEOUT_MS = 15_000;
const MIN_REQUEST_TIMEOUT_MS = 100;
const MAX_REQUEST_TIMEOUT_MS = 30_000;
const RECONCILIATION_SOURCE_FIELDS = new Set([
  "name",
  "title",
  "shortDescription",
  "description",
  "category",
  "subcategory",
  "location",
  "artwork",
  "imageUrl",
  "logoUrl",
  "galleryUrls",
  "featured",
  "open",
  "mapsUrl",
  "maps",
  "hours",
  "services",
  "products",
  "additionalInfo",
  "promotionTitle",
  "promotionDescription",
  "publicContactApproved",
  "phone",
  "whatsapp",
  "instagram",
  "published",
  "active",
  "expiresAt",
  "deletedAt",
  "catalogVersion",
  "outboxOperationId",
]);

export class FirestoreRestError extends Error {
  constructor(code) {
    const safeCode = code === "conflict"
      ? "conflict"
      : code === "invalid-request"
      ? "invalid-request"
      : "backend_unavailable";
    super(
      safeCode === "conflict"
        ? "Firestore transaction conflicted."
        : safeCode === "invalid-request"
        ? "Firestore request is invalid."
        : "Firestore is unavailable.",
    );
    this.name = "FirestoreRestError";
    this.code = safeCode;
  }
}

function validatePath(collection, id) {
  if (
    !COLLECTIONS.has(collection) || !isFirestoreDocumentId(id) ||
    (collection === "catalog_outbox" && !DOCUMENT_ID_PATTERN.test(id)) ||
    (collection === "catalog_outbox_scan_state" && id !== "consumer-v1")
  ) {
    throw new FirestoreRestError("invalid-request");
  }
}

function isFirestoreDocumentId(value) {
  if (
    typeof value !== "string" || value.length === 0 || value.includes("/") ||
    new TextEncoder().encode(value).byteLength > 1500 || value === "." ||
    value === ".."
  ) return false;
  return !value.startsWith("__") || !value.endsWith("__") ||
    /^__id\d+__$/u.test(value);
}

function encodeValue(value) {
  if (value === null) return { nullValue: null };
  if (value instanceof Date) {
    if (!Number.isFinite(value.getTime())) {
      throw new FirestoreRestError("invalid-request");
    }
    return { timestampValue: value.toISOString() };
  }
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    if (!Number.isFinite(value)) {
      throw new FirestoreRestError("invalid-request");
    }
    return Number.isSafeInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(encodeValue) } };
  }
  if (value && typeof value === "object") {
    return { mapValue: { fields: encodeFields(value) } };
  }
  throw new FirestoreRestError("invalid-request");
}

function encodeFields(value) {
  const fields = {};
  for (const [key, item] of Object.entries(value)) {
    if (!/^[A-Za-z][A-Za-z0-9_]{0,63}$/u.test(key) || item === undefined) {
      throw new FirestoreRestError("invalid-request");
    }
    fields[key] = encodeValue(item);
  }
  return fields;
}

function decodeValue(value) {
  if (Object.hasOwn(value, "stringValue")) return value.stringValue;
  if (Object.hasOwn(value, "booleanValue")) return value.booleanValue;
  if (Object.hasOwn(value, "integerValue")) return Number(value.integerValue);
  if (Object.hasOwn(value, "doubleValue")) return value.doubleValue;
  if (Object.hasOwn(value, "timestampValue")) return value.timestampValue;
  if (Object.hasOwn(value, "nullValue")) return null;
  if (Object.hasOwn(value, "arrayValue")) {
    return (value.arrayValue.values ?? []).map(decodeValue);
  }
  if (Object.hasOwn(value, "mapValue")) {
    return decodeFields(value.mapValue.fields ?? {});
  }
  return null;
}

function decodeFields(fields) {
  return Object.fromEntries(
    Object.entries(fields ?? {}).map((
      [key, value],
    ) => [key, decodeValue(value)]),
  );
}

async function readTextLimited(response, maximumBytes) {
  const reader = response.body?.getReader();
  if (!reader) return "";
  const chunks = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maximumBytes) {
        await reader.cancel();
        return "";
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return "";
  }
}

function encodeDocument(name, value, options, kind) {
  const transforms = options?.serverTimestampFields ?? [];
  const deleteFields = options?.deleteFields ?? [];
  if (
    !Array.isArray(transforms) ||
    transforms.some((field) =>
      !SERVER_TIMESTAMP_FIELDS.has(field) ||
      !/^[A-Za-z][A-Za-z0-9_]{0,63}$/u.test(field)
    )
  ) {
    throw new FirestoreRestError("invalid-request");
  }
  if (
    !Array.isArray(deleteFields) ||
    (kind === "create" && deleteFields.length > 0) ||
    deleteFields.some((field) =>
      !/^[A-Za-z][A-Za-z0-9_]{0,63}$/u.test(field) ||
      transforms.includes(field) || Object.hasOwn(value, field)
    )
  ) {
    throw new FirestoreRestError("invalid-request");
  }
  const data = { ...value };
  for (const field of transforms) delete data[field];
  if (
    Object.keys(data).length === 0 && transforms.length === 0 &&
    deleteFields.length === 0
  ) {
    throw new FirestoreRestError("invalid-request");
  }
  const write = {
    update: { name, fields: encodeFields(data) },
    ...(transforms.length
      ? {
        updateTransforms: transforms.map((field) => ({
          fieldPath: field,
          setToServerValue: "REQUEST_TIME",
        })),
      }
      : {}),
  };
  if (kind === "create") write.currentDocument = { exists: false };
  else {
    if (typeof options?.updateTime !== "string" || !options.updateTime) {
      throw new FirestoreRestError("invalid-request");
    }
    const fieldPaths = [...new Set([...Object.keys(data), ...deleteFields])]
      .sort();
    if (fieldPaths.length === 0) {
      throw new FirestoreRestError("invalid-request");
    }
    write.updateMask = { fieldPaths };
    write.currentDocument = { updateTime: options.updateTime };
  }
  return write;
}

function firestoreStatus(response, body) {
  if (
    [409, 412].includes(response.status) ||
    ["ABORTED", "ALREADY_EXISTS", "FAILED_PRECONDITION"].includes(
      body?.error?.status,
    )
  ) return "conflict";
  return "backend_unavailable";
}

/**
 * Minimal Firestore REST transaction adapter. Production remains fixed to the
 * configured project. Emulator mode is a separate explicit opt-in restricted
 * to the demo project, numeric loopback, and requests without credentials.
 * Hosted homologation can use a separate suffix-qualified project only when
 * the exact same ID is supplied through `homologationProjectId` together with
 * an explicit service-account credential source.
 * @param {{projectId: string, serviceAccountJson?: string | (() => string), homologationProjectId?: string, emulator?: {host: '127.0.0.1' | '::1', port: number}, fetchImpl?: typeof fetch, now?: () => number, requestTimeoutMs?: number, getAccessToken?: () => Promise<string | {accessToken: string}>}} options
 * @returns {{queryOutboxPage: (options: {limit: number, readTime?: string, startAfterDocumentId?: string}) => Promise<{documents: Array<{id: string, data: Record<string, unknown>, updateTime: string}>, readTime: string | null, nextDocumentId: string | null, hasMore: boolean}>, runTransaction: <T>(callback: (transaction: {get: (collection: string, id: string) => Promise<{data: Record<string, unknown>, updateTime: string} | null>, create: (collection: string, id: string, data: Record<string, unknown>, options?: {serverTimestampFields?: string[]}) => void, update: (collection: string, id: string, data: Record<string, unknown>, options?: {updateTime?: string, serverTimestampFields?: string[], deleteFields?: string[]}) => void}) => Promise<T>) => Promise<T>}}
 */
export function createFirebaseFirestoreRestStore({
  projectId,
  serviceAccountJson,
  homologationProjectId,
  emulator,
  fetchImpl = fetch,
  now = Date.now,
  requestTimeoutMs = DEFAULT_REQUEST_TIMEOUT_MS,
  getAccessToken: injectedTokenProvider,
}) {
  const emulatorMode = emulator !== undefined;
  const validEmulator = emulatorMode && emulator &&
    typeof emulator === "object" && !Array.isArray(emulator) &&
    Object.keys(emulator).length === 2 && Object.hasOwn(emulator, "host") &&
    Object.hasOwn(emulator, "port") &&
    ["127.0.0.1", "::1"].includes(emulator.host) &&
    Number.isSafeInteger(emulator.port) &&
    emulator.port >= 1 && emulator.port <= 65_535 &&
    projectId === EMULATOR_PROJECT_ID &&
    serviceAccountJson === undefined && injectedTokenProvider === undefined;
  const validHomologation = !emulatorMode &&
    typeof homologationProjectId === "string" &&
    homologationProjectId === projectId && projectId !== EXPECTED_PROJECT_ID &&
    projectId !== EMULATOR_PROJECT_ID &&
    HOMOLOGATION_PROJECT_MARKER.test(projectId) &&
    (serviceAccountJson !== undefined || injectedTokenProvider !== undefined);
  const validHostedProject = homologationProjectId === undefined
    ? projectId === EXPECTED_PROJECT_ID
    : validHomologation;
  if (
    (emulatorMode
      ? !validEmulator || homologationProjectId !== undefined
      : !validHostedProject) ||
    typeof fetchImpl !== "function" ||
    typeof now !== "function" || !Number.isSafeInteger(requestTimeoutMs) ||
    requestTimeoutMs < MIN_REQUEST_TIMEOUT_MS ||
    requestTimeoutMs > MAX_REQUEST_TIMEOUT_MS ||
    (injectedTokenProvider !== undefined &&
      typeof injectedTokenProvider !== "function")
  ) {
    throw new FirestoreRestError("invalid-request");
  }
  const resolvedProjectId = emulatorMode
    ? EMULATOR_PROJECT_ID
    : homologationProjectId ?? EXPECTED_PROJECT_ID;
  const documentsResource =
    `projects/${resolvedProjectId}/databases/(default)/documents`;
  const documentsRoot = emulatorMode
    ? `http://${
      emulator.host === "::1" ? "[::1]" : emulator.host
    }:${emulator.port}/v1/${documentsResource}`
    : `https://firestore.googleapis.com/v1/${documentsResource}`;
  let tokenCache;
  let tokenPromise;

  async function accessToken() {
    if (emulatorMode) return undefined;
    if (injectedTokenProvider) {
      const supplied = await injectedTokenProvider();
      const value = typeof supplied === "string"
        ? supplied
        : supplied?.accessToken;
      if (
        typeof value !== "string" || value.length < 20 || value.length > 8192
      ) {
        throw new FirestoreRestError("backend_unavailable");
      }
      return value;
    }
    if (tokenCache && tokenCache.expiresAt > now() + 60_000) {
      return tokenCache.accessToken;
    }
    if (tokenPromise) return tokenPromise;
    const credentials = typeof serviceAccountJson === "function"
      ? serviceAccountJson()
      : serviceAccountJson;
    tokenPromise = createGoogleAccessToken({
      serviceAccountJson: credentials,
      projectId: resolvedProjectId,
      fetchImpl,
      now,
    })
      .then((value) => {
        tokenCache = value;
        return value.accessToken;
      })
      .catch(() => {
        throw new FirestoreRestError("backend_unavailable");
      })
      .finally(() => {
        tokenPromise = undefined;
      });
    return tokenPromise;
  }

  async function call(
    url,
    { method = "GET", body, token, allowNotFound = false } = {},
  ) {
    let response;
    try {
      response = await fetchImpl(url, {
        method,
        headers: {
          accept: "application/json",
          ...(typeof token === "string"
            ? { authorization: `Bearer ${token}` }
            : {}),
          ...(body === undefined ? {} : { "content-type": "application/json" }),
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        signal: AbortSignal.timeout(requestTimeoutMs),
      });
    } catch {
      throw new FirestoreRestError("backend_unavailable");
    }
    if (allowNotFound && response.status === 404) return null;
    if (!response.ok) {
      const text = await readTextLimited(response, 8192);
      let parsed;
      try {
        if (text) parsed = JSON.parse(text);
      } catch {
        parsed = undefined;
      }
      throw new FirestoreRestError(firestoreStatus(response, parsed));
    }
    if (response.status === 204) return {};
    try {
      const text = await response.text();
      return text === "" ? {} : JSON.parse(text);
    } catch {
      throw new FirestoreRestError("backend_unavailable");
    }
  }

  function documentName(collection, id) {
    validatePath(collection, id);
    return `${documentsResource}/${collection}/${id}`;
  }

  return Object.freeze({
    /**
     * Reads one stable outbox page. The query shape is fixed to active states
     * and document-name ordering; callers cannot supply filters or collection
     * paths. Supplying the prior page's readTime pins subsequent pages to the
     * same Firestore snapshot.
     * @param {{limit: number, readTime?: string, startAfterDocumentId?: string}} options
     */
    async queryOutboxPage({ limit, readTime, startAfterDocumentId } = {}) {
      if (
        !Number.isSafeInteger(limit) || limit < 1 ||
        limit > MAX_OUTBOX_QUERY_PAGE_SIZE ||
        (readTime !== undefined && !validFirestoreTimestamp(readTime)) ||
        (startAfterDocumentId !== undefined &&
          !DOCUMENT_ID_PATTERN.test(startAfterDocumentId))
      ) {
        throw new FirestoreRestError("invalid-request");
      }
      const structuredQuery = {
        from: [{ collectionId: "catalog_outbox" }],
        where: {
          fieldFilter: {
            field: { fieldPath: "state" },
            op: "IN",
            value: {
              arrayValue: {
                values: [
                  { stringValue: "pending" },
                  { stringValue: "processing" },
                ],
              },
            },
          },
        },
        orderBy: [{ field: { fieldPath: "__name__" }, direction: "ASCENDING" }],
        limit,
        ...(startAfterDocumentId === undefined ? {} : {
          startAt: {
            before: false,
            values: [{
              referenceValue:
                `${documentsResource}/catalog_outbox/${startAfterDocumentId}`,
            }],
          },
        }),
      };
      const token = await accessToken();
      const response = await call(`${documentsRoot}:runQuery`, {
        method: "POST",
        token,
        body: {
          structuredQuery,
          ...(readTime === undefined ? {} : { readTime }),
        },
      });
      if (!Array.isArray(response)) {
        throw new FirestoreRestError("backend_unavailable");
      }

      const documents = [];
      const observedReadTimes = new Set();
      for (const item of response) {
        if (item?.readTime !== undefined) {
          if (!validFirestoreTimestamp(item.readTime)) {
            throw new FirestoreRestError("backend_unavailable");
          }
          observedReadTimes.add(item.readTime);
        }
        if (item?.document === undefined) continue;
        const document = item.document;
        const prefix = `${documentsResource}/catalog_outbox/`;
        if (
          typeof document?.name !== "string" ||
          !document.name.startsWith(prefix) ||
          !document.fields || typeof document.updateTime !== "string"
        ) {
          throw new FirestoreRestError("backend_unavailable");
        }
        const encodedId = document.name.slice(prefix.length);
        let id;
        try {
          id = decodeURIComponent(encodedId);
        } catch {
          throw new FirestoreRestError("backend_unavailable");
        }
        if (
          !DOCUMENT_ID_PATTERN.test(id) || encodeURIComponent(id) !== encodedId
        ) {
          throw new FirestoreRestError("backend_unavailable");
        }
        documents.push({
          id,
          data: decodeFields(document.fields),
          updateTime: document.updateTime,
        });
      }
      if (documents.length > limit || observedReadTimes.size > 1) {
        throw new FirestoreRestError("backend_unavailable");
      }
      const resolvedReadTime = observedReadTimes.values().next().value ??
        readTime;
      if (documents.length > 0 && typeof resolvedReadTime !== "string") {
        throw new FirestoreRestError("backend_unavailable");
      }
      const last = documents.at(-1)?.id ?? null;
      return Object.freeze({
        documents: Object.freeze(documents),
        readTime: resolvedReadTime ?? null,
        nextDocumentId: documents.length === limit ? last : null,
        hasMore: documents.length === limit,
      });
    },
    /**
     * Reads a bounded page of canonical establishment documents at one fixed
     * Firestore readTime. Only fields needed by the public V2 projector leave
     * this adapter; unapproved contact fields are removed even from memory.
     */
    async queryEstablishmentsSnapshotPage(
      { limit, readTime, startAfterDocumentId } = {},
    ) {
      if (
        !Number.isSafeInteger(limit) || limit < 1 ||
        limit > MAX_RECONCILIATION_QUERY_PAGE_SIZE ||
        (readTime !== undefined && !validFirestoreTimestamp(readTime)) ||
        (startAfterDocumentId !== undefined && startAfterDocumentId !== null &&
          !isFirestoreDocumentId(startAfterDocumentId))
      ) {
        throw new FirestoreRestError("invalid-request");
      }
      const structuredQuery = {
        from: [{ collectionId: "establishments" }],
        orderBy: [{ field: { fieldPath: "__name__" }, direction: "ASCENDING" }],
        limit,
        ...(startAfterDocumentId == null ? {} : {
          startAt: {
            before: false,
            values: [{
              referenceValue:
                `${documentsResource}/establishments/${startAfterDocumentId}`,
            }],
          },
        }),
      };
      const token = await accessToken();
      const response = await call(`${documentsRoot}:runQuery`, {
        method: "POST",
        token,
        body: {
          structuredQuery,
          ...(readTime === undefined ? {} : { readTime }),
        },
      });
      if (!Array.isArray(response)) {
        throw new FirestoreRestError("backend_unavailable");
      }

      const documents = [];
      const observedReadTimes = new Set();
      const prefix = `${documentsResource}/establishments/`;
      for (const item of response) {
        if (item?.readTime !== undefined) {
          if (!validFirestoreTimestamp(item.readTime)) {
            throw new FirestoreRestError("backend_unavailable");
          }
          observedReadTimes.add(item.readTime);
        }
        if (item?.document === undefined) continue;
        const document = item.document;
        if (
          typeof document?.name !== "string" ||
          !document.name.startsWith(prefix) ||
          !document.fields || !validFirestoreTimestamp(document.updateTime)
        ) {
          throw new FirestoreRestError("backend_unavailable");
        }
        const id = document.name.slice(prefix.length);
        if (
          !isFirestoreDocumentId(id) ||
          (startAfterDocumentId != null &&
            compareDocumentIds(id, startAfterDocumentId) <= 0)
        ) {
          throw new FirestoreRestError("backend_unavailable");
        }
        const decoded = decodeFields(document.fields);
        const data = Object.fromEntries(
          Object.entries(decoded).filter(([key]) =>
            RECONCILIATION_SOURCE_FIELDS.has(key)
          ),
        );
        if (data.publicContactApproved !== true) {
          delete data.phone;
          delete data.whatsapp;
          delete data.instagram;
        }
        documents.push({ id, data, updateTime: document.updateTime });
      }
      if (
        documents.length > limit || observedReadTimes.size > 1 ||
        documents.some((document, index) =>
          index > 0 &&
          compareDocumentIds(documents[index - 1].id, document.id) >= 0
        )
      ) {
        throw new FirestoreRestError("backend_unavailable");
      }
      const observedReadTime = observedReadTimes.values().next().value;
      if (
        readTime !== undefined && observedReadTime !== undefined &&
        observedReadTime !== readTime
      ) {
        throw new FirestoreRestError("backend_unavailable");
      }
      const resolvedReadTime = observedReadTime ?? readTime;
      if (documents.length > 0 && typeof resolvedReadTime !== "string") {
        throw new FirestoreRestError("backend_unavailable");
      }
      return Object.freeze({
        documents: Object.freeze(documents),
        readTime: resolvedReadTime ?? null,
        nextDocumentId: documents.length === limit ? documents.at(-1).id : null,
        hasMore: documents.length === limit,
      });
    },
    async runTransaction(callback) {
      if (typeof callback !== "function") {
        throw new FirestoreRestError("invalid-request");
      }
      const token = await accessToken();
      let transactionId;
      try {
        const begun = await call(`${documentsRoot}:beginTransaction`, {
          method: "POST",
          body: { options: { readWrite: {} } },
          token,
        });
        transactionId = begun?.transaction;
        if (
          typeof transactionId !== "string" || transactionId.length === 0 ||
          transactionId.length > 4096
        ) {
          throw new Error();
        }
      } catch {
        throw new FirestoreRestError("backend_unavailable");
      }
      const writes = [];
      const transaction = Object.freeze({
        async get(collection, id) {
          const name = documentName(collection, id);
          // Firestore REST accepts a transaction selector on GET, but the
          // Emulator's HTTP adapter cannot decode the bytes-form query value.
          // A key-only runQuery carries the same transaction token in JSON and
          // preserves the transaction's serializable read set.
          const response = await call(`${documentsRoot}:runQuery`, {
            method: "POST",
            token,
            body: {
              structuredQuery: {
                from: [{ collectionId: collection }],
                where: {
                  fieldFilter: {
                    field: { fieldPath: "__name__" },
                    op: "EQUAL",
                    value: { referenceValue: name },
                  },
                },
                limit: 1,
              },
              transaction: transactionId,
            },
          });
          if (!Array.isArray(response)) {
            throw new FirestoreRestError("backend_unavailable");
          }
          const documents = response.flatMap((item) =>
            item?.document ? [item.document] : []
          );
          if (documents.length === 0) return null;
          const document = documents[0];
          if (
            documents.length !== 1 || document.name !== name ||
            !document.fields ||
            typeof document.updateTime !== "string"
          ) {
            throw new FirestoreRestError("backend_unavailable");
          }
          return {
            data: decodeFields(document.fields),
            updateTime: document.updateTime,
          };
        },
        create(collection, id, data, options = {}) {
          writes.push(
            encodeDocument(
              documentName(collection, id),
              data,
              options,
              "create",
            ),
          );
        },
        update(collection, id, data, options = {}) {
          writes.push(
            encodeDocument(
              documentName(collection, id),
              data,
              options,
              "update",
            ),
          );
        },
      });

      let result;
      try {
        result = await callback(transaction);
      } catch (error) {
        try {
          await call(`${documentsRoot}:rollback`, {
            method: "POST",
            body: { transaction: transactionId },
            token,
          });
        } catch {
          // Rollback is best effort; transaction expiry and commit semantics remain server-enforced.
        }
        throw error;
      }
      try {
        if (writes.length > 0) {
          await call(`${documentsRoot}:commit`, {
            method: "POST",
            body: { writes, transaction: transactionId },
            token,
          });
        } else {
          await call(`${documentsRoot}:rollback`, {
            method: "POST",
            body: { transaction: transactionId },
            token,
          });
        }
        return result;
      } catch (error) {
        try {
          await call(`${documentsRoot}:rollback`, {
            method: "POST",
            body: { transaction: transactionId },
            token,
          });
        } catch {
          // A rejected or expired transaction cannot be committed afterward.
        }
        if (error instanceof FirestoreRestError) throw error;
        throw new FirestoreRestError("backend_unavailable");
      }
    },
  });
}

function validFirestoreTimestamp(value) {
  return typeof value === "string" &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/u
      .test(value) &&
    Number.isFinite(Date.parse(value));
}

function compareDocumentIds(left, right) {
  const leftPoints = Array.from(left, (character) => character.codePointAt(0));
  const rightPoints = Array.from(
    right,
    (character) => character.codePointAt(0),
  );
  for (
    let index = 0;
    index < Math.min(leftPoints.length, rightPoints.length);
    index += 1
  ) {
    if (leftPoints[index] !== rightPoints[index]) {
      return leftPoints[index] - rightPoints[index];
    }
  }
  return leftPoints.length - rightPoints.length;
}
