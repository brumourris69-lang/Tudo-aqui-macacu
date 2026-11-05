/**
 * Resolve a loopback-only Firebase Emulator endpoint.
 * Defaults retain the SparkLocal-compatible ports used by the existing harness.
 */
export function resolveLoopbackEmulatorEndpoint(value, defaultPort, name) {
  const address = value == null || value.trim() === ''
    ? `127.0.0.1:${defaultPort}`
    : value.trim();
  const match = /^127\.0\.0\.1:(\d{1,5})$/.exec(address);
  if (!match) {
    throw new Error(`${name} must be bound to 127.0.0.1 with an explicit port.`);
  }

  const port = Number(match[1]);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`${name} must use a TCP port from 1 through 65535.`);
  }

  return Object.freeze({ host: '127.0.0.1', port, address });
}
