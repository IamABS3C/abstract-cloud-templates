#!/usr/bin/env python3
"""What a Cloud Logging sink filter routes, read one top-level OR alternative at a time.

usage:
  sink_routes.py FILTER SERVICE...      the services whose Data Access events FILTER drops, space-separated
                                        (nothing when it routes them all)
  sink_routes.py --missing HAVE WANT    the alternatives of WANT that HAVE does not route, joined by OR, each
                                        in parentheses: append them to HAVE as "(HAVE) OR <output>". A Data
                                        Access alternative is cut down to the services HAVE drops. Nothing
                                        when HAVE routes all of WANT; an empty HAVE routes every log entry.
  sink_routes.py --tfvars HAVE WANT     the same gap as Terraform variables of the abstract-cloud-templates
                                        audit roots (log_categories, data_access_services), one per line, and
                                        only ever as additions: the identity services as identity_access,
                                        other services as data_access_services next to data_access_all
  sink_routes.py --non-audit FILTER     the top-level alternatives that select logs other than Cloud Audit Logs
                                        (firewall, DNS, ..., or a negated audit clause such as
                                        NOT logName:"cloudaudit...", which selects everything else), joined
                                        by OR; nothing when every one selects audit logs only

Used by audit-gcp-estate.sh and abstract-gcp-setup.sh so both read a filter alike.

A filter is a set of alternatives joined by top-level OR. An alternative routes a log only when every
condition in it is understood: a logName test for one Cloud Audit log and, optionally, a serviceName list.
Anything else in it (NOT, a resource or severity test, a logName with a path prefix or "=") can only narrow
it, so it is read as routing nothing. A wrong "routed" loses logs for good, with no backfill; a wrong
"missing" only adds a clause the sink already had. A service is routed when ONE alternative selects Data
Access logs and either names no serviceName (every service) or names that service itself. "allServices"
(the audit-config wildcard, not a serviceName any entry carries) is routed only by a Data Access
alternative that names no service.
"""
import re
import sys

AUDIT = "cloudaudit.googleapis.com"
# logName:"cloudaudit.googleapis.com%2F<id>" (the ":" has-test the Terraform catalog writes), log_id(...), or
# logName:"cloudaudit.googleapis.com" for every audit log. "=" needs the full resource path, so it is not read.
LOG_TEST = re.compile(r'logName\s*:\s*"cloudaudit\.googleapis\.com(?:%2F([a-z_]+))?"'
                      r'|log_id\(\s*"cloudaudit\.googleapis\.com/([a-z_]+)"\s*\)')
SERVICE_TEST = re.compile(r'protoPayload\.serviceName\s*[:=]\s*(\(\s*"[^"]*"(?:\s+OR\s+"[^"]*")*\s*\)|"[^"]*")')
ALL = "*"                                           # every audit log
TF_CATEGORY = {"activity": "admin_activity", "system_event": "system_event", "policy": "policy_denied"}
TF_IDENTITY = {"iamcredentials.googleapis.com", "sts.googleapis.com", "login.googleapis.com", "iap.googleapis.com"}


def _split(f: str, word: str) -> list[str]:
    """Top-level alternatives (word OR) or conditions (word AND): not inside parentheses or quotes."""
    sep = re.compile(rf"\s+{word}\s+")
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
        elif depth == 0 and (m := sep.match(f, i)):
            parts.append(f[start:i])
            i = start = m.end()
            continue
        i += 1
    parts.append(f[start:])
    return [p.strip() for p in parts if p.strip()]


def split_or(f: str) -> list[str]:
    return _split(f, "OR")


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


def alternatives(f: str) -> list[str]:
    """Every top-level alternative, with nested "(a OR b)" groups flattened."""
    out = []
    for p in split_or(unwrap(f.strip())):
        u = unwrap(p)
        out += alternatives(u) if len(split_or(u)) > 1 else [u]
    return out


def classify(alt: str):
    """(audit log id or ALL, services or None for every service), or None when the alternative is not
    understood and so routes nothing."""
    log, services = None, None
    for cond in _split(alt, "AND"):
        cond = unwrap(cond)
        m = LOG_TEST.fullmatch(cond)
        if m and log is None:
            log = m.group(1) or m.group(2) or ALL
            continue
        m = SERVICE_TEST.fullmatch(cond)
        if m and services is None:
            services = set(re.findall(r'"([^"]*)"', m.group(1)))
            continue
        return None             # NOT, a second logName, resource.type, an implicit AND, ...: narrows it
    return (log, services) if log else None


# A positive test for a Cloud Audit log, in any spelling: "=" with the full path narrows it but still selects
# only audit logs, which is all the --non-audit question asks.
AUDIT_LOG_ANY = re.compile(r'logName\s*[:=]\s*"[^"]*cloudaudit\.googleapis\.com[^"]*"'
                           r'|log_id\(\s*"cloudaudit\.googleapis\.com/[a-z_]+"\s*\)')


def selects_only_audit(expr: str) -> bool:
    """Does EXPR select Cloud Audit Logs only? An OR does when every branch does; an AND when any one of its
    conditions does (the others only narrow it); a single condition when it holds a cloudaudit logName test
    that is not negated by NOT or "-". Naming cloudaudit is not enough: NOT logName:"cloudaudit..." selects
    every OTHER log, which Abstract's managed parser then discards."""
    e = unwrap(expr.strip())
    ors = split_or(e)
    if len(ors) > 1:
        return all(selects_only_audit(o) for o in ors)
    ands = _split(e, "AND")
    if len(ands) > 1:
        return any(selects_only_audit(a) for a in ands)
    for m in AUDIT_LOG_ANY.finditer(e):
        before = e[:m.start()]
        if before.endswith("-") or re.search(r"\bNOT\s*$", before):
            continue
        return True
    return False


def routes(f: str, service: str) -> bool:
    if not f.strip():
        return True
    for alt in alternatives(f):
        c = classify(alt)
        if not c or c[0] not in ("data_access", ALL):
            continue
        if c[1] is None or (service != "allServices" and service in c[1]):
            return True
    return False


def _covers_log(have: str, log: str) -> bool:
    """Does an alternative of HAVE route every entry of this audit log?"""
    for alt in alternatives(have):
        c = classify(alt)
        if c and c[1] is None and c[0] in (log, ALL):
            return True
    return False


def _norm(x: str) -> str:
    return re.sub(r"\s+", " ", unwrap(x.strip()))


def gaps(have: str, want: str):
    """[(wanted alternative, services HAVE drops or None)] for every part of WANT that HAVE misses."""
    if not have.strip():
        return []
    out = []
    for w in alternatives(want):
        c = classify(w)
        if c and c[0] == "data_access" and c[1] is not None:
            drop = [s for s in sorted(c[1]) if not routes(have, s)]
            if drop:
                out.append((w, drop))
        elif c and c[0] == "data_access":
            if not routes(have, "allServices"):
                out.append((w, None))
        elif c and c[1] is None:
            if not _covers_log(have, c[0]):
                out.append((w, None))
        elif _norm(w) not in {_norm(h) for h in alternatives(have)}:
            out.append((w, None))
    return out


def missing(have: str, want: str) -> str:
    parts = []
    for w, drop in gaps(have, want):
        if drop is not None:
            w = (f'logName:"{AUDIT}%2Fdata_access" AND protoPayload.serviceName=('
                 + " OR ".join(f'"{s}"' for s in drop) + ")")
        parts.append(f"({unwrap(w)})")
    return " OR ".join(parts)


def _data_access_lists(have: str):
    """(does HAVE carry a data_access_all clause, the services its data_access_all clauses name).

    identity_access is a Data Access clause too, but naming only the identity services: it is not
    data_access_all, and the data_access_services variable is read only for data_access_all."""
    present, listed = False, set()
    for alt in alternatives(have):
        c = classify(alt)
        if c and c[0] == "data_access" and (c[1] is None or not c[1] <= TF_IDENTITY):
            present = True
            listed |= c[1] or set()
    return present, listed


def tfvars(have: str, want: str) -> list[str]:
    """Terraform variable changes that close the gap, always ADDING: a list replaced by what WANT names
    drops what the sink routes today, and a sink has no backfill. data_access_services is read only with
    data_access_all, so it is never advised without it."""
    lines, identity, others = [], set(), set()
    has_all, listed = _data_access_lists(have)
    for w, drop in gaps(have, want):
        c = classify(w)
        if c and c[0] in TF_CATEGORY:
            lines.append(f'log_categories: add "{TF_CATEGORY[c[0]]}"')
        elif c and c[0] == "data_access" and drop is None:
            lines.append(('log_categories: add "data_access_all", ' if not has_all else "with data_access_all, ")
                         + "make data_access_services = [] and acknowledge_high_volume = true (every service's Data Access logs)")
        elif drop:
            identity |= {s for s in drop if s in TF_IDENTITY}
            others |= {s for s in drop if s not in TF_IDENTITY}
        else:
            lines.append(f"no catalog category matches ({unwrap(w)}): add it with platform_log_filters or custom_filter")
    if identity:
        lines.append('log_categories: add "identity_access" (routes ' + ", ".join(sorted(identity)) + ")")
    if others:
        added = ", ".join(f'"{s}"' for s in sorted(others))
        if has_all:
            keep = ", ".join(f'"{s}"' for s in sorted(listed))
            lines.append(f"data_access_services (read with data_access_all, already in log_categories): add {added}; "
                         f"keep {keep}, which it routes today")
        else:
            lines.append('log_categories: add "data_access_all"')
            lines.append(f"data_access_services (read only with data_access_all): add {added} to the services already "
                         "listed, and keep them")
    return lines


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--missing":
        print(missing(sys.argv[2], sys.argv[3]))
    elif len(sys.argv) == 3 and sys.argv[1] == "--non-audit":
        print(" OR ".join(f"({a})" for a in alternatives(sys.argv[2]) if not selects_only_audit(a)))
    elif len(sys.argv) == 4 and sys.argv[1] == "--tfvars":
        print("\n".join(tfvars(sys.argv[2], sys.argv[3])))
    elif len(sys.argv) >= 3 and not sys.argv[1].startswith("--"):
        print(" ".join(s for s in sys.argv[2:] if not routes(sys.argv[1], s)))
    else:
        sys.exit(__doc__)
