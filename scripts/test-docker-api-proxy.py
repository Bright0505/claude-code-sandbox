#!/usr/bin/env python3
"""Rule-layer tests for scripts/docker-api-proxy.py.

Runs on the host with no docker and no root: the daemon lookup is injected, and
the only filesystem the tests touch is a temporary directory standing in for the
read-only workspace copy.

The tests assert on the *reason string* as well as allow/deny, because "refused
for the wrong reason" is the failure mode that a boolean assertion cannot see -
an endpoint that falls through to the catch-all instead of being caught by its
own rule still looks like a pass.
"""

import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.util

spec = importlib.util.spec_from_file_location(
    "docker_api_proxy",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "docker-api-proxy.py"))
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)

import json

PROJECT = "demo"
FAILURES = []
RUN = []


def check(name, condition, detail=""):
    RUN.append(name)
    if not condition:
        FAILURES.append("%s%s" % (name, (": " + detail) if detail else ""))


def make_policy(root, containers=None):
    containers = containers or {}

    def inspect(cid):
        return containers.get(cid)

    return proxy.Policy(project=PROJECT, mount_root="/host/proj",
                        mount_root_local=root, inspect=inspect)


def container(project=PROJECT, name="demo-app-1", is_proxy=False):
    labels = {"com.docker.compose.project": project}
    if is_proxy:
        labels["sandbox.docker-api-proxy"] = "1"
    return {"Name": "/" + name, "Config": {"Labels": labels}}


def create_body(**host):
    return json.dumps({"Image": "demo:latest", "HostConfig": host}).encode()


def main():
    root = tempfile.mkdtemp(prefix="proxy-test-")
    try:
        os.makedirs(os.path.join(root, "src"))
        os.symlink("/", os.path.join(root, "escape"))
        run_tests(root)
    finally:
        shutil.rmtree(root, ignore_errors=True)

    # A test file that silently stops exercising anything still exits 0. Assert
    # the count so "parsed nothing, found nothing" cannot pass as green.
    expected = 52
    if len(RUN) != expected:
        FAILURES.append("test count is %d, expected %d - did a case get lost?"
                        % (len(RUN), expected))

    if FAILURES:
        print("FAIL (%d/%d)" % (len(FAILURES), len(RUN)))
        for f in FAILURES:
            print("  - " + f)
        return 1
    print("ok - %d checks passed" % len(RUN))
    return 0


def run_tests(root):
    owned = container()
    others = {
        "mine": container(),
        "theirs": container(project="somebody-else", name="other-app-1"),
        "proxyself": container(name="sandbox-docker-proxy", is_proxy=True),
    }
    p = make_policy(root, others)

    # --- endpoint allowlist -------------------------------------------------
    for method, path in [
        ("GET", "/_ping"),
        ("HEAD", "/v1.51/_ping"),
        ("GET", "/v1.51/version"),
        ("GET", "/v1.51/containers/json"),
        ("GET", "/v1.51/images/json"),
        ("GET", "/v1.51/images/demo:latest/json"),
        ("GET", "/v1.51/networks"),
        ("GET", "/v1.51/volumes"),
        ("POST", "/v1.51/build"),
    ]:
        check("allow %s %s" % (method, path),
              p.check(method, path) is None,
              str(p.check(method, path)))

    # --- endpoints that must never be reachable -----------------------------
    for method, path in [
        ("POST", "/v1.51/grpc"),
        ("POST", "/v1.51/session"),
        ("POST", "/v1.51/images/create"),
        ("POST", "/v1.51/networks/create"),
        ("POST", "/v1.51/volumes/create"),
        ("POST", "/v1.51/containers/mine/commit"),
        ("GET", "/v1.51/info"),
        ("GET", "/v1.51/secrets"),
        ("POST", "/v1.51/containers/prune"),
    ]:
        reason = p.check(method, path)
        check("deny %s %s" % (method, path),
              reason is not None and "endpoint not allowed" in reason,
              str(reason))

    # A method that is not on the rule's list must not slip through on the
    # strength of a matching path.
    check("deny DELETE /build",
          (p.check("DELETE", "/v1.51/build") or "").startswith("endpoint not allowed"))

    # --- ownership ----------------------------------------------------------
    check("allow exec into own project",
          p.check("POST", "/v1.51/containers/mine/exec") is None,
          str(p.check("POST", "/v1.51/containers/mine/exec")))
    check("deny exec into another project",
          "belongs to project" in (p.check("POST", "/v1.51/containers/theirs/exec") or ""),
          str(p.check("POST", "/v1.51/containers/theirs/exec")))
    check("deny operating on the proxy itself",
          "api proxy itself" in (p.check("POST", "/v1.51/containers/proxyself/restart") or ""),
          str(p.check("POST", "/v1.51/containers/proxyself/restart")))
    check("deny unresolvable container",
          "not resolvable" in (p.check("GET", "/v1.51/containers/ghost/json") or ""),
          str(p.check("GET", "/v1.51/containers/ghost/json")))
    check("deny delete of another project's container",
          "belongs to project" in (p.check("DELETE", "/v1.51/containers/theirs") or ""))

    # Containers this proxy created have no compose labels but are still ours.
    p.note_created("fresh")
    check("allow start of a container we created",
          p.check("POST", "/v1.51/containers/fresh/start") is None,
          str(p.check("POST", "/v1.51/containers/fresh/start")))

    check("allow attach into own project",
          p.check("POST", "/v1.51/containers/mine/attach") is None,
          str(p.check("POST", "/v1.51/containers/mine/attach")))
    check("deny attach into another project",
          "belongs to project" in (p.check("POST", "/v1.51/containers/theirs/attach") or ""))

    # exec ids are not re-checked: approval happened at /containers/{id}/exec.
    check("allow exec start", p.check("POST", "/v1.51/exec/abc123/start") is None)

    # With no project configured, container access must fail closed.
    noproj = proxy.Policy(project="", mount_root="/host/proj",
                          mount_root_local=root, inspect=lambda c: others.get(c))
    check("deny container access with no project configured",
          "container access is off" in (noproj.check("GET", "/v1.51/containers/mine/json") or ""),
          str(noproj.check("GET", "/v1.51/containers/mine/json")))

    # --- connection handling ------------------------------------------------
    # The allowlist is worthless if a second request can ride through on an
    # already-approved connection, so the rewrite that prevents it is asserted
    # here rather than left to the integration run.
    head = (b"GET /v1.51/containers/json HTTP/1.1\r\n"
            b"Host: docker\r\n"
            b"Connection: keep-alive\r\n"
            b"Keep-Alive: timeout=60\r\n"
            b"User-Agent: docker\r\n\r\n")
    out = proxy.force_close(head)
    check("force_close appends Connection: close",
          b"\r\nConnection: close\r\n\r\n" in out, repr(out))
    check("force_close drops keep-alive headers",
          b"keep-alive" not in out.lower().replace(b"connection: close", b""),
          repr(out))
    check("force_close keeps the request line and other headers",
          out.startswith(b"GET /v1.51/containers/json HTTP/1.1\r\n")
          and b"User-Agent: docker" in out, repr(out))

    # --- create payload -----------------------------------------------------
    ok = p.check("POST", "/v1.51/containers/create",
                 create_body(Binds=["/host/proj/src:/app:rw"]))
    check("allow create with bind inside the workspace", ok is None, str(ok))

    ok = p.check("POST", "/v1.51/containers/create",
                 create_body(Binds=["named-volume:/data"]))
    check("allow create with a named volume", ok is None, str(ok))

    ok = p.check("POST", "/v1.51/containers/create",
                 create_body(Mounts=[{"Type": "volume", "Source": "v", "Target": "/d"}]))
    check("allow create with a volume-type mount", ok is None, str(ok))

    # A real sample project sets cap_add: [SYS_PTRACE] for its debugger; a
    # blanket CapAdd refusal made `docker compose up` unusable on it.
    ok = p.check("POST", "/v1.51/containers/create", create_body(CapAdd=["SYS_PTRACE"]))
    check("allow create with a harmless added capability", ok is None, str(ok))

    for label, body, needle in [
        ("bind outside the workspace",
         create_body(Binds=["/:/host"]), "is outside"),
        ("bind escaping via parent",
         create_body(Binds=["/host/proj/../../etc:/etc"]), "is outside"),
        ("bind escaping via symlink",
         create_body(Binds=["/host/proj/escape:/host"]), "(symlink)"),
        ("Mounts bind outside the workspace",
         create_body(Mounts=[{"Type": "bind", "Source": "/etc", "Target": "/etc"}]),
         "is outside"),
        ("privileged", create_body(Privileged=True), "Privileged"),
        ("dangerous capability", create_body(CapAdd=["SYS_ADMIN"]), "CapAdd"),
        ("dangerous capability, CAP_ prefixed",
         create_body(CapAdd=["CAP_SYS_MODULE"]), "CapAdd"),
        ("dangerous capability, lowercase",
         create_body(CapAdd=["net_admin"]), "CapAdd"),
        ("all capabilities", create_body(CapAdd=["ALL"]), "CapAdd"),
        ("device passthrough",
         create_body(Devices=[{"PathOnHost": "/dev/sda"}]), "Devices"),
        ("security options", create_body(SecurityOpt=["seccomp=unconfined"]),
         "SecurityOpt"),
        ("volumes-from", create_body(VolumesFrom=["other"]), "VolumesFrom"),
        ("host network", create_body(NetworkMode="host"), "NetworkMode"),
        ("host pid namespace", create_body(PidMode="host"), "PidMode"),
    ]:
        reason = p.check("POST", "/v1.51/containers/create", body)
        check("deny create: " + label,
              reason is not None and needle in reason, str(reason))

    check("deny create with no body",
          "inspectable body" in (p.check("POST", "/v1.51/containers/create", b"") or ""))
    check("deny create with non-JSON body",
          "not valid JSON" in (p.check("POST", "/v1.51/containers/create", b"nope") or ""))


if __name__ == "__main__":
    sys.exit(main())
