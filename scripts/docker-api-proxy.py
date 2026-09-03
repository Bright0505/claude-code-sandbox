#!/usr/bin/env python3
"""Filtering proxy for the Docker Engine API.

Why this exists: mounting docker.sock into the sandbox hands out the ability to
start a sibling container with any bind mount, which is equivalent to handing
out the host filesystem - the firewall and the non-root user both stop meaning
anything. But the sandbox genuinely needs to drive the project's own containers
(exec into them, rebuild them, restart them), and pushing that back to a human
stops the edit/test loop on every iteration.

So: this process holds the socket, and the sandbox talks to it over TCP. Two
layers of filtering, because one is not enough:

  1. Endpoint allowlist. Everything that is not explicitly listed is refused.
     This is what keeps `POST /images/create` (pull), `/commit`, and BuildKit's
     `/grpc` + `/session` tunnels out of reach.
  2. Payload validation on `POST /containers/create`. Endpoint filtering alone
     is NOT sufficient there - an off-the-shelf prefix-matching proxy that
     allows the `/containers/` prefix also allows `create`, and create's body is
     where `Binds: ["/:/host"]` lives. Measured against
     tecnativa/docker-socket-proxy on 2026-09-02: with CONTAINERS=1 POST=1 a
     container binding the host home directory was created and started
     successfully.

The compose file that describes the project's services lives in the workspace
and is therefore writable by the model, so the policy cannot be "whatever the
compose file asks for" - it has to live here, out of reach. Same reason this
script is COPYed into an image rather than bind-mounted.

Connection handling: exactly one HTTP request is parsed per client connection,
after which the connection is either relayed raw (hijacked exec/attach streams)
or closed. Never attempt to keep a connection alive after the request has been
forwarded - a second request arriving on an already-approved connection would
ride through unfiltered, which is the whole ballgame.
"""

import json
import os
import posixpath
import re
import socket
import socketserver
import sys
import threading

DOCKER_SOCK = os.environ.get("DOCKER_SOCK", "/var/run/docker.sock")
# Compose project whose containers may be operated on. Anything else is refused
# even though the daemon would happily serve it.
PROJECT = os.environ.get("SANDBOX_DOCKER_PROJECT", "")
# Host-side directory that bind mount sources must stay inside.
MOUNT_ROOT = os.environ.get("SANDBOX_DOCKER_MOUNT_ROOT", "")
# The same directory, mounted read-only into this container, so symlinks in the
# requested source path can actually be resolved. A lexical prefix check is not
# enough: the model can create `<workspace>/escape -> /` and the daemon would
# resolve it host-side.
MOUNT_ROOT_LOCAL = os.environ.get("SANDBOX_DOCKER_MOUNT_ROOT_LOCAL", "/mountroot")
LISTEN_PORT = int(os.environ.get("SANDBOX_DOCKER_PORT", "2375"))

API_PREFIX = re.compile(r"^/v[0-9]+\.[0-9]+")
ID = r"[A-Za-z0-9_.-]+"


def _p(pattern):
    return re.compile(r"^" + pattern + r"$")


# (methods, path pattern, owner-checked, body-checked)
#
# Derived from what `docker compose exec/logs/ps/restart/up -d` and
# `DOCKER_BUILDKIT=0 docker build` were measured to actually call. Endpoints are
# added when a real command needs them, never speculatively - every entry here
# is reachable by the model.
RULES = [
    (("GET", "HEAD"), _p(r"/_ping"), False, False),
    (("GET",), _p(r"/version"), False, False),
    (("GET",), _p(r"/containers/json"), False, False),
    (("GET",), _p(r"/containers/(?P<id>%s)/json" % ID), True, False),
    (("GET",), _p(r"/containers/(?P<id>%s)/logs" % ID), True, False),
    (("GET",), _p(r"/images/json"), False, False),
    (("GET",), _p(r"/images/%s/json" % r"[^/]+"), False, False),
    (("GET",), _p(r"/networks"), False, False),
    (("GET",), _p(r"/networks/%s" % ID), False, False),
    (("GET",), _p(r"/volumes"), False, False),
    (("GET",), _p(r"/exec/(?P<exec_id>%s)/json" % ID), False, False),
    # Lifecycle. `up -d` needs create/stop/delete/rename/start; restart is for
    # the common "pick up a config change" case.
    (("POST",), _p(r"/containers/create"), False, True),
    (("POST",), _p(r"/containers/(?P<id>%s)/start" % ID), True, False),
    (("POST",), _p(r"/containers/(?P<id>%s)/stop" % ID), True, False),
    (("POST",), _p(r"/containers/(?P<id>%s)/restart" % ID), True, False),
    (("POST",), _p(r"/containers/(?P<id>%s)/kill" % ID), True, False),
    (("POST",), _p(r"/containers/(?P<id>%s)/rename" % ID), True, False),
    (("POST",), _p(r"/containers/(?P<id>%s)/wait" % ID), True, False),
    (("POST",), _p(r"/containers/(?P<id>%s)/resize" % ID), True, False),
    (("DELETE",), _p(r"/containers/(?P<id>%s)" % ID), True, False),
    # Exec. `/exec/{id}/start` is not owner-checked against the daemon: the exec
    # id can only exist because this proxy approved the `/containers/{id}/exec`
    # that created it, so the ownership decision was already made there.
    (("POST",), _p(r"/containers/(?P<id>%s)/exec" % ID), True, False),
    # `docker run` (not detached) attaches instead of exec-ing. Same power as
    # exec on a container we already own, so it is gated the same way.
    (("POST",), _p(r"/containers/(?P<id>%s)/attach" % ID), True, False),
    (("POST",), _p(r"/exec/(?P<exec_id>%s)/start" % ID), False, False),
    (("POST",), _p(r"/exec/(?P<exec_id>%s)/resize" % ID), False, False),
    # Legacy builder only. BuildKit does not use this endpoint at all - it
    # tunnels over /grpc and /session, which cannot be reasoned about per
    # endpoint and are therefore not on this list. Sandbox sets
    # DOCKER_BUILDKIT=0 so `docker build` lands here.
    (("POST",), _p(r"/build"), False, False),
]

# HostConfig fields that grant capabilities the sandbox is specifically not
# supposed to have. Refused whenever set to anything truthy.
FORBIDDEN_TRUTHY = (
    "Privileged",
    "Devices",
    "DeviceRequests",
    "DeviceCgroupRules",
    "SecurityOpt",
    "VolumesFrom",
    "Sysctls",
    "CgroupParent",
    "Runtime",
    "PidsLimit",
)
# Capabilities are handled by denylist rather than by refusing CapAdd outright:
# real projects legitimately add things like SYS_PTRACE for a debugger, and
# blanket refusal means `docker compose up` simply cannot be used on them. What
# is refused is the set that changes what the container can do to the machine
# rather than to itself.
FORBIDDEN_CAPS = frozenset((
    "ALL", "SYS_ADMIN", "SYS_MODULE", "SYS_RAWIO", "SYS_BOOT", "SYS_TIME",
    "DAC_READ_SEARCH", "MAC_ADMIN", "MAC_OVERRIDE", "NET_ADMIN",
))

# Namespace-sharing fields: "host" hands over the host's namespace.
NAMESPACE_FIELDS = ("PidMode", "IpcMode", "UTSMode", "UsernsMode", "CgroupnsMode",
                    "NetworkMode")


class Denied(Exception):
    pass


class Policy:
    """Pure decision layer. Kept free of sockets so it can be tested directly."""

    def __init__(self, project=None, mount_root=None, mount_root_local=None,
                 inspect=None):
        self.project = PROJECT if project is None else project
        self.mount_root = MOUNT_ROOT if mount_root is None else mount_root
        self.mount_root_local = (MOUNT_ROOT_LOCAL if mount_root_local is None
                                 else mount_root_local)
        # Injected so tests do not need a daemon.
        self._inspect = inspect or self._inspect_via_daemon
        # Containers created through this proxy already passed payload
        # validation, so later operations on them are allowed even before
        # compose labels exist (a plain `docker run` never gets those labels).
        self.created_ids = set()
        self._owner_cache = {}

    # -- entry point ------------------------------------------------------
    def check(self, method, path, body=b""):
        """Return None to allow, or a string reason to refuse."""
        try:
            norm = API_PREFIX.sub("", path.split("?", 1)[0]) or "/"
            for methods, pattern, owner_checked, body_checked in RULES:
                m = pattern.match(norm)
                if not m:
                    continue
                if method not in methods:
                    continue
                if owner_checked:
                    self._check_owner(m.group("id"))
                if body_checked:
                    self._check_create_body(body)
                return None
            raise Denied("endpoint not allowed: %s %s" % (method, norm))
        except Denied as e:
            return str(e)

    def note_created(self, container_id):
        if container_id:
            self.created_ids.add(container_id)

    # -- ownership --------------------------------------------------------
    def _inspect_via_daemon(self, container_id):
        conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        conn.connect(DOCKER_SOCK)
        try:
            conn.sendall(("GET /containers/%s/json HTTP/1.1\r\n"
                          "Host: docker\r\nConnection: close\r\n\r\n"
                          % container_id).encode())
            buf = b""
            while True:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                buf += chunk
        finally:
            conn.close()
        head, _, body = buf.partition(b"\r\n\r\n")
        if b" 200 " not in head.split(b"\r\n")[0]:
            return None
        # The daemon may answer chunked; find the JSON object rather than
        # implementing dechunking for a body we only read one field out of.
        start = body.find(b"{")
        end = body.rfind(b"}")
        if start < 0 or end < 0:
            return None
        try:
            return json.loads(body[start:end + 1])
        except ValueError:
            return None

    def _check_owner(self, container_id):
        if container_id in self.created_ids:
            return
        if container_id in self._owner_cache:
            owner = self._owner_cache[container_id]
        else:
            info = self._inspect(container_id)
            if info is None:
                # Unknown container: refuse rather than forward. A 404 from the
                # daemon would be harmless, but "cannot resolve" and "not
                # allowed" must not produce different observable behaviour, or
                # the proxy becomes an existence oracle for other projects.
                raise Denied("container not resolvable: %s" % container_id)
            labels = (info.get("Config") or {}).get("Labels") or {}
            owner = {
                "project": labels.get("com.docker.compose.project", ""),
                "name": (info.get("Name") or "").lstrip("/"),
                "self": labels.get("sandbox.docker-api-proxy") == "1",
            }
            self._owner_cache[container_id] = owner
        if owner["self"]:
            raise Denied("refusing to operate on the api proxy itself")
        if not self.project:
            raise Denied("no compose project configured; container access is off")
        if owner["project"] != self.project:
            raise Denied("container %s belongs to project %r, not %r"
                         % (container_id, owner["project"], self.project))

    # -- create payload ---------------------------------------------------
    def _check_create_body(self, body):
        if not body:
            raise Denied("containers/create requires an inspectable body")
        try:
            spec = json.loads(body)
        except ValueError:
            raise Denied("containers/create body is not valid JSON")
        if not isinstance(spec, dict):
            raise Denied("containers/create body is not an object")
        host = spec.get("HostConfig") or {}
        if not isinstance(host, dict):
            raise Denied("HostConfig is not an object")

        for field in FORBIDDEN_TRUTHY:
            if host.get(field):
                raise Denied("HostConfig.%s is not allowed" % field)
        for cap in host.get("CapAdd") or []:
            if not isinstance(cap, str):
                raise Denied("CapAdd entry is not a string")
            name = cap.upper()
            if name.startswith("CAP_"):
                name = name[4:]
            if name in FORBIDDEN_CAPS:
                raise Denied("HostConfig.CapAdd %s is not allowed" % cap)

        for field in NAMESPACE_FIELDS:
            value = host.get(field) or ""
            if isinstance(value, str) and value.split(":")[0] == "host":
                raise Denied("HostConfig.%s=host is not allowed" % field)

        for bind in host.get("Binds") or []:
            self._check_mount_source(self._bind_source(bind), "Binds")
        for mount in host.get("Mounts") or []:
            if not isinstance(mount, dict):
                raise Denied("Mounts entry is not an object")
            if (mount.get("Type") or "volume") == "bind":
                self._check_mount_source(mount.get("Source") or "", "Mounts")

    @staticmethod
    def _bind_source(bind):
        if not isinstance(bind, str):
            raise Denied("Binds entry is not a string")
        source = bind.split(":", 1)[0]
        if not source:
            raise Denied("Binds entry has an empty source")
        return source

    def _check_mount_source(self, source, where):
        # A named volume (no leading slash) never reaches the host filesystem
        # outside docker's own storage, so it needs no containment check.
        if not source.startswith("/"):
            return
        if not self.mount_root:
            raise Denied("%s: host bind mounts are disabled (no mount root)"
                         % where)
        root = posixpath.normpath(self.mount_root)
        norm = posixpath.normpath(source)
        if norm != root and not norm.startswith(root + "/"):
            raise Denied("%s: %s is outside %s" % (where, source, root))
        # Resolve symlinks through the read-only copy of the same tree. Without
        # this the check is lexical only, and `<root>/escape -> /` defeats it.
        rel = os.path.relpath(norm, root)
        local_root = os.path.realpath(self.mount_root_local)
        if not os.path.isdir(local_root):
            raise Denied("%s: mount root not available for symlink resolution"
                         % where)
        local = os.path.realpath(os.path.join(local_root, rel))
        if local != local_root and not local.startswith(local_root + os.sep):
            raise Denied("%s: %s resolves outside %s (symlink)"
                         % (where, source, root))


# -- HTTP plumbing --------------------------------------------------------

def read_head(sock):
    """Read one HTTP head. Returns (head_bytes, first_line, headers, leftover)."""
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            return None
        buf += chunk
        if len(buf) > 1 << 20:
            return None
    head, _, rest = buf.partition(b"\r\n\r\n")
    lines = head.split(b"\r\n")
    headers = {}
    for line in lines[1:]:
        name, _, value = line.partition(b":")
        headers[name.strip().lower().decode("latin1")] = \
            value.strip().decode("latin1")
    return head + b"\r\n\r\n", lines[0].decode("latin1"), headers, rest


# Connection-scoped headers. Dropped so the upstream exchange cannot be kept
# alive: see force_close.
HOP_BY_HOP = (b"connection", b"keep-alive", b"proxy-connection")


def force_close(head_bytes):
    """Rewrite a request head so the exchange ends after one response.

    This is a load-bearing guardrail, not an optimisation. The docker CLI
    reuses one TCP connection for several requests, and a proxy that approves
    the first request and then relays the socket raw will carry every
    subsequent request through unfiltered - measured on 2026-09-02, that is how
    `docker pull` and an inspect of another project's container both succeeded
    against an earlier version of this file that had the allowlist right.
    """
    lines = head_bytes.split(b"\r\n")
    out = [lines[0]]
    for line in lines[1:]:
        if not line:
            continue
        if line.split(b":", 1)[0].strip().lower() in HOP_BY_HOP:
            continue
        out.append(line)
    out.append(b"Connection: close")
    return b"\r\n".join(out) + b"\r\n\r\n"


def stream_length(src, dst, buf, remaining):
    """Forward exactly `remaining` bytes, starting with whatever is in buf."""
    take = min(len(buf), remaining)
    if take:
        dst.sendall(buf[:take])
    remaining -= take
    buf = buf[take:]
    while remaining > 0:
        chunk = src.recv(min(65536, remaining))
        if not chunk:
            break
        dst.sendall(chunk)
        remaining -= len(chunk)
    return buf


def stream_chunked(src, dst, buf):
    """Forward a chunked body, stopping at the terminating zero-length chunk."""
    while True:
        while b"\r\n" not in buf:
            more = src.recv(65536)
            if not more:
                if buf:
                    dst.sendall(buf)
                return b""
            buf += more
        line, _, buf = buf.partition(b"\r\n")
        dst.sendall(line + b"\r\n")
        try:
            size = int(line.split(b";")[0].strip() or b"0", 16)
        except ValueError:
            return buf
        need = size + 2
        while len(buf) < need:
            more = src.recv(65536)
            if not more:
                dst.sendall(buf)
                return b""
            buf += more
        dst.sendall(buf[:need])
        buf = buf[need:]
        if size == 0:
            return buf


def forward_request_body(src, dst, headers, buf):
    encoding = headers.get("transfer-encoding", "").lower()
    if "chunked" in encoding:
        return stream_chunked(src, dst, buf)
    length = headers.get("content-length")
    if length:
        try:
            return stream_length(src, dst, buf, int(length))
        except ValueError:
            return buf
    return buf


def deny(sock, reason):
    payload = json.dumps({"message": "sandbox docker proxy: " + reason}).encode()
    sock.sendall(b"HTTP/1.1 403 Forbidden\r\n"
                 b"Content-Type: application/json\r\n"
                 b"Content-Length: " + str(len(payload)).encode() + b"\r\n"
                 b"Connection: close\r\n\r\n" + payload)
    sys.stderr.write("docker-api-proxy: DENY %s\n" % reason)
    sys.stderr.flush()


def relay(src, dst):
    try:
        while True:
            chunk = src.recv(65536)
            if not chunk:
                break
            dst.sendall(chunk)
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


class Handler(socketserver.BaseRequestHandler):
    policy = None

    def handle(self):
        client = self.request
        parsed = read_head(client)
        if parsed is None:
            return
        head_bytes, request_line, headers, rest = parsed
        parts = request_line.split(" ")
        if len(parts) < 2:
            return
        method, path = parts[0], parts[1]
        norm = API_PREFIX.sub("", path.split("?", 1)[0])

        # Only the one body that gets inspected is buffered; the build context
        # tarball is streamed straight through.
        needs_body = method == "POST" and norm == "/containers/create"
        body = b""
        if needs_body:
            length = int(headers.get("content-length") or 0)
            body = rest[:length]
            rest = rest[length:]
            while len(body) < length:
                chunk = client.recv(min(65536, length - len(body)))
                if not chunk:
                    break
                body += chunk

        reason = self.policy.check(method, path, body)
        if reason is not None:
            deny(client, reason)
            return

        up = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            up.connect(DOCKER_SOCK)
        except OSError as exc:
            deny(client, "cannot reach docker socket: %s" % exc)
            return
        try:
            self._exchange(client, up, head_bytes, headers, rest, body,
                           needs_body)
        finally:
            up.close()

    def _exchange(self, client, up, head_bytes, headers, rest, body, needs_body):
        # An exec/attach stream is upgraded and then carries stdin, so its
        # Connection header has to survive. Every other request is forced to
        # close, and its client->daemon direction is never relayed: those two
        # together are what make request pipelining impossible.
        wants_upgrade = "upgrade" in headers
        up.sendall(head_bytes if wants_upgrade else force_close(head_bytes))
        if needs_body:
            up.sendall(body)
        else:
            forward_request_body(client, up, headers, rest)

        parsed = read_head(up)
        if parsed is None:
            return
        resp_head, status_line, resp_headers, resp_rest = parsed
        client.sendall(resp_head)

        if needs_body and " 201 " in status_line:
            resp_rest = self._note_created(up, resp_headers, resp_rest)

        if resp_rest:
            client.sendall(resp_rest)

        if " 101 " in status_line:
            # Hijacked: from here it is an opaque byte stream in both
            # directions, and no further HTTP request can appear on it.
            t = threading.Thread(target=relay, args=(client, up), daemon=True)
            t.start()
            relay(up, client)
            t.join(timeout=1)
            return

        # Response only. Not relaying client->daemon here is deliberate.
        relay(up, client)

    def _note_created(self, up, resp_headers, resp_rest):
        """Read the create response body to learn the new container's id.

        Needed because the id is how later lifecycle calls are recognised as
        ours - a plain `docker run` produces no compose labels, so without this
        the container this proxy just approved could not then be started.
        """
        length = int(resp_headers.get("content-length") or 0)
        while length and len(resp_rest) < length:
            chunk = up.recv(min(65536, length - len(resp_rest)))
            if not chunk:
                break
            resp_rest += chunk
        start = resp_rest.find(b"{")
        end = resp_rest.rfind(b"}")
        if start >= 0 and end > start:
            try:
                self.policy.note_created(
                    json.loads(resp_rest[start:end + 1]).get("Id"))
            except ValueError:
                pass
        return resp_rest


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    Handler.policy = Policy()
    sys.stderr.write(
        "docker-api-proxy: listening on :%d  project=%r  mount-root=%r\n"
        % (LISTEN_PORT, PROJECT, MOUNT_ROOT))
    sys.stderr.flush()
    Server(("0.0.0.0", LISTEN_PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
