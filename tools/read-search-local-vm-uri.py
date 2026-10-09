"""Read the existing debug VM URI; no invocation, suspension or auth bypass.

Uses only JDWP read commands for FlutterJNI.vmServiceUri in the debug local app.
Stdout is the local debugger URI (not intended for saved logs).
"""
import os
import socket
import struct
import subprocess
from pathlib import Path
from urllib.parse import urlparse

ADB = Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk/platform-tools/adb.exe'
DEVICE = '127.0.0.1:21503'
PACKAGE = 'br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal'


def adb(*args):
    return subprocess.check_output([str(ADB), '-s', DEVICE, *args],
                                   timeout=8, text=True).strip()


def read_uri():
    pid = adb('shell', 'pidof', PACKAGE)
    if not pid.isdigit():
        raise RuntimeError('Expected exactly one local application PID')
    if 'tun0:' not in adb('shell', 'ip', 'addr', 'show', 'tun0'):
        raise RuntimeError('Local isolation VPN must remain active')
    if 'uid=' not in adb('shell', 'run-as', PACKAGE, 'id'):
        raise RuntimeError('Expected debuggable local package')
    port = int(adb('forward', 'tcp:0', 'jdwp:' + pid))
    sock = None
    sequence = 0

    def read(count):
        result = b''
        while len(result) < count:
            part = sock.recv(count - len(result))
            if not part:
                raise RuntimeError('Debugger connection closed')
            result += part
        return result

    def command(group, number, payload=b''):
        nonlocal sequence
        sequence += 1
        sock.sendall(struct.pack('>IIBBB', 11 + len(payload), sequence, 0,
                                 group, number) + payload)
        while True:
            header = read(11)
            length, reply_id, flags = struct.unpack('>IIB', header[:9])
            if length < 11 or length > 1000000:
                raise RuntimeError('Invalid debugger response')
            body = read(length - 11)
            if flags & 128:
                error = struct.unpack('>H', header[9:])[0]
                if error:
                    raise RuntimeError('Debugger error ' + str(error))
                if reply_id == sequence:
                    return body

    def string(value):
        data = value.encode()
        return struct.pack('>I', len(data)) + data

    try:
        sock = socket.create_connection(('127.0.0.1', port), timeout=5)
        sock.settimeout(5)
        sock.sendall(b'JDWP-Handshake')
        if read(14) != b'JDWP-Handshake':
            raise RuntimeError('Invalid debugger handshake')
        field_size, _, object_size, reference_size, _ = struct.unpack('>IIIII', command(1, 7))
        classes = command(1, 2, string('Lio/flutter/embedding/engine/FlutterJNI;'))
        if struct.unpack('>I', classes[:4])[0] != 1:
            raise RuntimeError('Expected exactly one FlutterJNI class')
        clazz = classes[5:5 + reference_size]
        fields = command(2, 4, clazz)
        count = struct.unpack('>I', fields[:4])[0]
        position = 4
        selected = None
        for _ in range(count):
            field_id = fields[position:position + field_size]
            position += field_size
            length = struct.unpack('>I', fields[position:position + 4])[0]
            position += 4
            name = fields[position:position + length].decode()
            position += length
            length = struct.unpack('>I', fields[position:position + 4])[0]
            position += 4
            signature = fields[position:position + length].decode()
            position += length
            modifiers = struct.unpack('>I', fields[position:position + 4])[0]
            position += 4
            if name == 'vmServiceUri' and signature == 'Ljava/lang/String;' and modifiers & 8:
                selected = field_id
        if selected is None:
            raise RuntimeError('Flutter debug URI field not available in this engine')
        value = command(2, 6, clazz + struct.pack('>I', 1) + selected)
        if value[4:5] != b's':
            raise RuntimeError('Expected string VM URI')
        raw = command(10, 1, value[5:5 + object_size])
        length = struct.unpack('>I', raw[:4])[0]
        uri = raw[4:4 + length].decode()
        parsed = urlparse(uri)
        if parsed.scheme != 'http' or parsed.hostname != '127.0.0.1' or not parsed.port or not parsed.path.strip('/'):
            raise RuntimeError('Expected authenticated loopback VM service')
        command(1, 6)  # Dispose debugger, not the application.
        return uri
    finally:
        if sock is not None:
            sock.close()
        adb('forward', '--remove', 'tcp:' + str(port))


if __name__ == '__main__':
    print(read_uri())
