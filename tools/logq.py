#!/usr/bin/env python3
"""Search agentgateway's JSON request log, like a tiny SIEM.

Reads a log written with config.logging.format: json (Listing 12.1), keeps the
request records, and skips everything else (startup lines, span export errors).

  python3 tools/logq.py ch12/gateway.log gen_ai.tool.name=issue_refund http.status=200 \\
      --table time,agent.id,enduser.id,mcp.target,trace.id
  python3 tools/logq.py ch12/gateway.log reason=Authorization --since 24h \\
      --count-by agent.id,gen_ai.tool.name
  python3 tools/logq.py ch12/gateway.log protocol=llm --sum agw.ai.usage.cost.total \\
      --by agent.id --per hour
  python3 tools/logq.py ch12/gateway.log trace.id=<id> --table time,protocol,agent.id,http.status

Filters are field=value (exact match), field!=value, or field=* (field is present).
With no output option, matching records are printed as JSON lines.
"""

import argparse
import json
import re
import signal
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

SHORT = {"gen_ai.request.model": "model", "gen_ai.tool.name": "tool", "http.status": "status",
         "agw.ai.usage.cost.total": "cost"}


def parse_time(s):
    if not s:
        return None
    s = s.replace("Z", "+00:00")
    m = re.match(r"(.*\.\d{6})\d*(.*)", s)  # Python wants at most 6 fractional digits
    if m:
        s = m.group(1) + m.group(2)
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return None


def get(rec, field):
    if field in rec:
        return rec[field]
    cur = rec  # also allow nested objects
    for part in field.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return None
    return cur


def fmt(v, field=""):
    if v is None:
        return ""
    if field == "time":
        t = parse_time(str(v))
        return t.strftime("%H:%M:%S.%f")[:-3] if t else str(v)
    if field == "gen_ai.tool.name" and isinstance(v, str):
        return v
    return str(v)


def matches(rec, filters):
    for field, op, want in filters:
        got = get(rec, field)
        if want == "*":
            ok = got is not None
        else:
            ok = got is not None and str(got) == want
        if op == "!=":
            ok = not ok
        if not ok:
            return False
    return True


def load(path):
    fh = sys.stdin if path == "-" else open(path, encoding="utf-8", errors="replace")
    for line in fh:
        line = line.strip()
        start = line.find("{")
        if start < 0:
            continue
        try:
            rec = json.loads(line[start:])
        except json.JSONDecodeError:
            continue
        if not isinstance(rec, dict):
            continue
        if rec.get("scope") not in (None, "request") and "http.status" not in rec:
            continue
        if "http.status" not in rec and "protocol" not in rec:
            continue  # not a request record
        yield rec


def table(rows, cols):
    heads = [SHORT.get(c, c) for c in cols]
    cells = [[fmt(get(r, c), c) for c in cols] for r in rows]
    widths = [max([len(h)] + [len(row[i]) for row in cells]) for i, h in enumerate(heads)]
    print("  ".join(h.ljust(w) for h, w in zip(heads, widths)).rstrip())
    for row in cells:
        print("  ".join(v.ljust(w) for v, w in zip(row, widths)).rstrip())


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("logfile", help="the gateway log (use - for stdin)")
    ap.add_argument("filters", nargs="*", help="field=value, field!=value, or field=*")
    ap.add_argument("--since", help="only records newer than this, such as 30m, 24h, 7d")
    ap.add_argument("--table", help="comma-separated fields to show as a table")
    ap.add_argument("--count-by", help="count records by these comma-separated fields")
    ap.add_argument("--sum", help="numeric field to add up")
    ap.add_argument("--by", help="group --sum by this field")
    ap.add_argument("--per", choices=["minute", "hour", "day"], help="also group --sum by time bucket")
    args = ap.parse_args()

    filters = []
    for f in args.filters:
        m = re.match(r"^([^=!]+)(!=|=)(.*)$", f)
        if not m:
            raise SystemExit(f"filter {f!r} should look like field=value")
        filters.append((m.group(1), m.group(2), m.group(3)))

    since = None
    if args.since:
        m = re.match(r"^(\d+)([smhd])$", args.since)
        if not m:
            raise SystemExit("--since looks like 30m, 24h or 7d")
        unit = {"s": "seconds", "m": "minutes", "h": "hours", "d": "days"}[m.group(2)]
        since = datetime.now(timezone.utc) - timedelta(**{unit: int(m.group(1))})

    rows = []
    for rec in load(args.logfile):
        if not matches(rec, filters):
            continue
        if since:
            t = parse_time(rec.get("time"))
            if t and t < since:
                continue
        rows.append(rec)

    if args.count_by:
        cols = args.count_by.split(",")
        counts = Counter(tuple(fmt(get(r, c), c) for c in cols) for r in rows)
        out = [dict(zip(cols, k), count=n) for k, n in counts.most_common()]
        table(out, cols + ["count"])
    elif args.sum:
        groups = defaultdict(float)
        for r in rows:
            try:
                v = float(get(r, args.sum))
            except (TypeError, ValueError):
                continue
            key = []
            if args.per:
                t = parse_time(r.get("time"))
                pattern = {"minute": "%Y-%m-%d %H:%M", "hour": "%Y-%m-%d %H:00", "day": "%Y-%m-%d"}[args.per]
                key.append(t.strftime(pattern) if t else "?")
            if args.by:
                key.append(fmt(get(r, args.by)) or "(none)")
            groups[tuple(key)] += v
        cols = (["time"] if args.per else []) + ([args.by] if args.by else []) + [args.sum]
        out = []
        for k, v in sorted(groups.items()):
            row = dict(zip(cols, list(k)))
            row[args.sum] = f"{v:.7f}".rstrip("0").rstrip(".") if v else "0"
            out.append(row)
        heads = [("time" if c == "time" else c) for c in cols]
        widths = [max([len(SHORT.get(h, h))] + [len(str(r.get(c, ""))) for r in out]) for h, c in zip(heads, cols)]
        print("  ".join(SHORT.get(h, h).ljust(w) for h, w in zip(heads, widths)).rstrip())
        for r in out:
            print("  ".join(str(r.get(c, "")).ljust(w) for c, w in zip(cols, widths)).rstrip())
    elif args.table:
        table(rows, args.table.split(","))
    else:
        for r in rows:
            print(json.dumps(r))
    return 0


if __name__ == "__main__":
    if hasattr(signal, "SIGPIPE"):
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)  # quiet when piped into head
    sys.exit(main())
