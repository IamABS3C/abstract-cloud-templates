#!/usr/bin/env python3
"""The roles the Google Cloud setup needs, read from permissions.json (the one list the script, the app and the docs share).

usage:
  permissions.py roles SET SCOPE         one role per line, tab-separated: kind, role, need, why, steps, permissions
                                         (SET: setup, infra-manager or infra-manager-sa; SCOPE: organization, folder
                                         or project, which picks the roles for that scope and names its permissions)
  permissions.py verify                  asks Google (gcloud iam roles describe, read-only) for every role: that it
                                         exists, has the title written here, and includes every permission listed for
                                         it. Exits 1 on any difference, so a wrong row cannot ship.
"""
import json
import subprocess
import sys
from pathlib import Path

MATRIX = Path(__file__).resolve().with_name("permissions.json")
SCOPES = ("organization", "folder", "project")
SETS = ("setup", "infra-manager", "infra-manager-sa")


def load() -> dict:
    return json.loads(MATRIX.read_text(encoding="utf-8"))


def expand(text: str, scope: str) -> str:
    """{scope} is the resource-manager collection (resourcemanager.organizations), {scope_name} the word."""
    return text.replace("{scope}", f"resourcemanager.{scope}s").replace("{scope_name}", scope)


def roles(matrix: dict, set_: str, scope: str) -> list[dict]:
    out = []
    for r in matrix["roles"]:
        if r["set"] != set_ or scope not in r.get("scopes", SCOPES):
            continue
        out.append({**r, "why": expand(r["why"], scope), "permissions": [expand(p, scope) for p in r["permissions"]]})
    return out


def describe(role: str):
    r = subprocess.run(["gcloud", "iam", "roles", "describe", role, "--format=json"], capture_output=True, text=True)
    if r.returncode:
        return None, (r.stderr.strip().splitlines() or ["no answer"])[-1]
    return json.loads(r.stdout), ""


def verify(matrix: dict) -> int:
    seen, bad = {}, 0
    for r in matrix["roles"]:
        perms = {expand(p, s) for p in r["permissions"] for s in r.get("scopes", SCOPES)}
        seen.setdefault(r["role"], [r["title"], set()])[1].update(perms)
    for role, (title, perms) in sorted(seen.items()):
        d, err = describe(role)
        if d is None:
            print(f"✗ {role}: {err}")
            bad += 1
            continue
        have = set(d.get("includedPermissions", []))
        missing = sorted(perms - have)
        problems = []
        if d.get("title") != title:
            problems.append(f'title is "{d.get("title")}", not "{title}"')
        if missing:
            problems.append("does not include " + ", ".join(missing))
        if d.get("stage") not in (None, "GA"):
            problems.append(f"stage {d.get('stage')}")
        print(("✗ " if problems else "✓ ") + role + (": " + "; ".join(problems) if problems else f" ({title}, {len(perms)} permission(s) checked)"))
        bad += bool(problems)
    print(f"{len(seen) - bad} of {len(seen)} roles match Google")
    return 1 if bad else 0


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) == 3 and a[0] == "roles" and a[1] in SETS and a[2] in SCOPES:
        for r in roles(load(), a[1], a[2]):
            print("\t".join([r["kind"], r["role"], r["need"], r["why"], ",".join(map(str, r["steps"])), " ".join(r["permissions"])]))
    elif a == ["verify"]:
        sys.exit(verify(load()))
    else:
        sys.exit(__doc__)
