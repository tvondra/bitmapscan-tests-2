#!/usr/bin/env bash

rm results.db

sqlite3 results.db "create table results (machine text, device text, build text, rows int, dataset text, relpages int, workers int, wm int, eic int, ioc int, readahead int, nmatches int, ndistinct int, run int, caching text, optimal text, timing numeric)"

sqlite3 results.db "create table results_aggregated (machine text, device text, build text, rows int, dataset text, relpages int, workers int, wm int, eic int, ioc int, readahead int, nmatches int, ndistinct int, caching text, optimal text, timing numeric)"

sed 's/^/ryzen /' bitmap-ryzen.csv > tmp-ryzen.csv
sed 's/^/xeon /' bitmap-xeon.csv > tmp-xeon.csv

sqlite3 results.db <<EOF
.mode csv
.separator ' '
.import -skip 1 tmp-ryzen.csv results
.import -skip 1 tmp-xeon.csv results
EOF

# sqlite3 results.db "select * from results where eic = 1 and ioc = 16 and readahead = 256 and caching = 'uncached'"

sqlite3 results.db "insert into results_aggregated select machine, device, build, rows, dataset, relpages, workers, wm, eic, ioc, readahead, nmatches, ndistinct, caching, optimal, avg(timing) from results group by machine, device, build, rows, dataset, relpages, workers, wm, eic, ioc, readahead, nmatches, ndistinct, caching, optimal"

sqlite3 results.db "UPDATE results set device = 'nvme' where device = 'data'"
sqlite3 results.db "UPDATE results_aggregated set device = 'nvme' where device = 'data'"

# all

sqlite3 results.db > comparison-melanie-relative.txt <<EOF
.mode table
SELECT m.machine, m.device, m.build, m.rows, m.dataset, m.relpages, m.workers, m.wm, m.eic, m.ioc, m.readahead, m.nmatches, m.ndistinct, m.optimal, m.caching, m.timing AS master, p.timing AS patched
FROM results_aggregated m
JOIN results_aggregated p ON (m.machine = p.machine AND m.device = p.device AND m.rows = p.rows AND m.dataset = p.dataset AND m.relpages = p.relpages AND m.workers = p.workers AND m.wm = p.wm AND m.eic = p.eic AND m.ioc = p.ioc AND m.readahead = p.readahead AND m.nmatches = p.nmatches AND m.ndistinct = p.ndistinct AND m.optimal = p.optimal AND m.caching = p.caching)
WHERE m.build = 'master' AND p.build = 'patched-melanie'
ORDER BY p.timing / m.timing DESC
EOF

sqlite3 results.db > comparison-melanie-absolute.txt <<EOF
.mode table
SELECT m.machine, m.device, m.build, m.rows, m.dataset, m.relpages, m.workers, m.wm, m.eic, m.ioc, m.readahead, m.nmatches, m.ndistinct, m.optimal, m.caching, m.timing AS master, p.timing AS patched
FROM results_aggregated m
JOIN results_aggregated p ON (m.machine = p.machine AND m.device = p.device AND m.rows = p.rows AND m.dataset = p.dataset AND m.relpages = p.relpages AND m.workers = p.workers AND m.wm = p.wm AND m.eic = p.eic AND m.ioc = p.ioc AND m.readahead = p.readahead AND m.nmatches = p.nmatches AND m.ndistinct = p.ndistinct AND m.optimal = p.optimal AND m.caching = p.caching)
WHERE m.build = 'master' AND p.build = 'patched-melanie'
ORDER BY (p.timing - m.timing) DESC
EOF

sqlite3 results.db > comparison-thomas-relative.txt <<EOF
.mode table
SELECT m.machine, m.device, m.build, m.rows, m.dataset, m.relpages, m.workers, m.wm, m.eic, m.ioc, m.readahead, m.nmatches, m.ndistinct, m.optimal, m.caching, m.timing AS master, p.timing AS patched
FROM results_aggregated m
JOIN results_aggregated p ON (m.machine = p.machine AND m.device = p.device AND m.rows = p.rows AND m.dataset = p.dataset AND m.relpages = p.relpages AND m.workers = p.workers AND m.wm = p.wm AND m.eic = p.eic AND m.ioc = p.ioc AND m.readahead = p.readahead AND m.nmatches = p.nmatches AND m.ndistinct = p.ndistinct AND m.optimal = p.optimal AND m.caching = p.caching)
WHERE m.build = 'master' AND p.build = 'patched-thomas'
ORDER BY p.timing / m.timing DESC
EOF

sqlite3 results.db > comparison-thomas-absolute.txt <<EOF
.mode table
SELECT m.machine, m.device, m.build, m.rows, m.dataset, m.relpages, m.workers, m.wm, m.eic, m.ioc, m.readahead, m.nmatches, m.ndistinct, m.optimal, m.caching, m.timing AS master, p.timing AS patched
FROM results_aggregated m
JOIN results_aggregated p ON (m.machine = p.machine AND m.device = p.device AND m.rows = p.rows AND m.dataset = p.dataset AND m.relpages = p.relpages AND m.workers = p.workers AND m.wm = p.wm AND m.eic = p.eic AND m.ioc = p.ioc AND m.readahead = p.readahead AND m.nmatches = p.nmatches AND m.ndistinct = p.ndistinct AND m.optimal = p.optimal AND m.caching = p.caching)
WHERE m.build = 'master' AND p.build = 'patched-thomas'
ORDER BY (p.timing - m.timing) DESC
EOF

# optimal only

sqlite3 results.db > comparison-melanie-relative-optimal.txt <<EOF
.mode table
SELECT m.machine, m.device, m.build, m.rows, m.dataset, m.relpages, m.workers, m.wm, m.eic, m.ioc, m.readahead, m.nmatches, m.ndistinct, m.optimal, m.caching, m.timing AS master, p.timing AS patched
FROM results_aggregated m
JOIN results_aggregated p ON (m.machine = p.machine AND m.device = p.device AND m.rows = p.rows AND m.dataset = p.dataset AND m.relpages = p.relpages AND m.workers = p.workers AND m.wm = p.wm AND m.eic = p.eic AND m.ioc = p.ioc AND m.readahead = p.readahead AND m.nmatches = p.nmatches AND m.ndistinct = p.ndistinct AND m.optimal = p.optimal AND m.caching = p.caching)
WHERE m.build = 'master' AND p.build = 'patched-melanie' AND p.optimal = 'bitmapscan'
ORDER BY p.timing / m.timing DESC
EOF

sqlite3 results.db > comparison-melanie-absolute-optimal.txt <<EOF
.mode table
SELECT m.machine, m.device, m.build, m.rows, m.dataset, m.relpages, m.workers, m.wm, m.eic, m.ioc, m.readahead, m.nmatches, m.ndistinct, m.optimal, m.caching, m.timing AS master, p.timing AS patched
FROM results_aggregated m
JOIN results_aggregated p ON (m.machine = p.machine AND m.device = p.device AND m.rows = p.rows AND m.dataset = p.dataset AND m.relpages = p.relpages AND m.workers = p.workers AND m.wm = p.wm AND m.eic = p.eic AND m.ioc = p.ioc AND m.readahead = p.readahead AND m.nmatches = p.nmatches AND m.ndistinct = p.ndistinct AND m.optimal = p.optimal AND m.caching = p.caching)
WHERE m.build = 'master' AND p.build = 'patched-melanie' AND p.optimal = 'bitmapscan'
ORDER BY (p.timing - m.timing) DESC
EOF

sqlite3 results.db > comparison-thomas-relative-optimal.txt <<EOF
.mode table
SELECT m.machine, m.device, m.build, m.rows, m.dataset, m.relpages, m.workers, m.wm, m.eic, m.ioc, m.readahead, m.nmatches, m.ndistinct, m.optimal, m.caching, m.timing AS master, p.timing AS patched
FROM results_aggregated m
JOIN results_aggregated p ON (m.machine = p.machine AND m.device = p.device AND m.rows = p.rows AND m.dataset = p.dataset AND m.relpages = p.relpages AND m.workers = p.workers AND m.wm = p.wm AND m.eic = p.eic AND m.ioc = p.ioc AND m.readahead = p.readahead AND m.nmatches = p.nmatches AND m.ndistinct = p.ndistinct AND m.optimal = p.optimal AND m.caching = p.caching)
WHERE m.build = 'master' AND p.build = 'patched-thomas' AND p.optimal = 'bitmapscan'
ORDER BY p.timing / m.timing DESC
EOF

sqlite3 results.db > comparison-thomas-absolute-optimal.txt <<EOF
.mode table
SELECT m.machine, m.device, m.build, m.rows, m.dataset, m.relpages, m.workers, m.wm, m.eic, m.ioc, m.readahead, m.nmatches, m.ndistinct, m.optimal, m.caching, m.timing AS master, p.timing AS patched
FROM results_aggregated m
JOIN results_aggregated p ON (m.machine = p.machine AND m.device = p.device AND m.rows = p.rows AND m.dataset = p.dataset AND m.relpages = p.relpages AND m.workers = p.workers AND m.wm = p.wm AND m.eic = p.eic AND m.ioc = p.ioc AND m.readahead = p.readahead AND m.nmatches = p.nmatches AND m.ndistinct = p.ndistinct AND m.optimal = p.optimal AND m.caching = p.caching)
WHERE m.build = 'master' AND p.build = 'patched-thomas' AND p.optimal = 'bitmapscan'
ORDER BY (p.timing - m.timing) DESC
EOF
