#!/usr/bin/env python3
"""Which services' Data Access audit events a Cloud Logging sink filter lets through.

usage: sink_routes.py FILTER SERVICE...
Prints, space-separated, the services whose Data Access events the filter drops (nothing when it
routes them all). Used by audit-gcp-estate.sh and abstract-gcp-setup.sh so both read a filter alike.

A filter is a set of alternatives joined by top-level OR. A service is routed when ONE alternative
selects Data Access logs and either names no serviceName (every service) or names that service
itself - a name that only appears in some other alternative routes nothing. An empty filter routes
every log entry.
"""
import re
import sys

DATA_ACCESS = re.compile(r'logName\s*[:=]\s*"[^"]*cloudaudit\.googleapis\.com(?:%2F|/)data_access"'
                         r'|log_id\(\s*"cloudaudit\.googleapis\.com/data_access"\s*\)')
OR = re.compile(r"\s+OR\s+")


def split_or(f: str) -> list[str]:
    """Top-level OR alternatives: not inside parentheses or quotes."""
    parts, depth, start, i, quoted = [], 0, 0, 0, False
    while i < len(f):
        c = f[i]
        if quoted:
            if c == "\\":
                i += 2
                continue
            quoted = c != '"'
        elif c == '"':
            quoted = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        elif depth == 0 and (m := OR.match(f, i)):
            parts.append(f[start:i])
            i = start = m.end()
            continue
        i += 1
    parts.append(f[start:])
    return [p.strip() for p in parts if p.strip()]


def unwrap(p: str) -> str:
    """Strip parentheses that enclose the whole expression."""
    while p.startswith("(") and p.endswith(")"):
        depth, quoted = 0, False
        for i, c in enumerate(p):
            if quoted:
                quoted = c != '"'
            elif c == '"':
                quoted = True
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0 and i < len(p) - 1:
                    return p        # the first group closes early: "(a) OR (b)"
        p = p[1:-1].strip()
    return p


def routes(f: str, service: str) -> bool:
    f = unwrap(f.strip())
    if not f:
        return True
    alternatives = split_or(f)
    if len(alternatives) > 1:
        return any(routes(a, service) for a in alternatives)
    if not DATA_ACCESS.search(f):
        return False
    return "serviceName" not in f or f'"{service}"' in f


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    print(" ".join(s for s in sys.argv[2:] if not routes(sys.argv[1], s)))
