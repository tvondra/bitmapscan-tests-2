#!/usr/bin/env bash

set -e

# fraction of distinct values, a width of the fuzz interval
FUZZ=1

# number of intervals
CYCLES=100

# fillfactor of the table, to make the tuples look wider
FILLFACTOR=25

function restart_postgres () {
	DATADIR=$1
	cp postgresql.conf $DATADIR
	pg_ctl -D $DATADIR -l pg.log -w stop || true
	pg_ctl -D $DATADIR -l pg.log -w start
}

function stop_postgres() {
        DATADIR=$1
        pg_ctl -D $DATADIR -l pg.log -w stop || true
}

function drop_caches () {
	sudo ./drop-caches.sh
}

function check_postgres_build () {
	command=$(pgrep -a postgres | grep data)

	if [[ ! $command =~ $1 ]]; then
		exit 1
	fi
}

OUTDIR=`date +%Y%m%d-%H%M%S`
mkdir $OUTDIR

echo "device build rows dataset relpages workers wm eic ioc readahead matches distinct run caching optimal timing" > $OUTDIR/results.csv

PATH_OLD=$PATH


for rows in 1000000 10000000; do

	for run in $(seq 1 3); do

		for dev in samsung-990-pro wd-sn640; do

			PATH=/home/tomas/builds/master/bin:$PATH_OLD

			restart_postgres /mnt/$dev/data

			ps ax | grep postgres

			for dataset in uniform linear linear-fuzz cyclic cyclic-fuzz; do

				# cleanup before this run
				dropdb --if-exists test
				createdb test

				psql test -c "create table bitmap_scan_test (a bigint, b bigint, c text) with (fillfactor = $FILLFACTOR)"

				if [ "$dataset" == "uniform" ]; then
					distinct=$((rows/100))
					psql test -c "insert into bitmap_scan_test select $distinct * random(), i, md5(random()::text) from generate_series(1, $rows) s(i)"
				elif [ "$dataset" == "linear" ]; then
					distinct=$((rows/100))
					psql test -c "insert into bitmap_scan_test select ($distinct * (i * 1.0 / $rows)), i, md5(random()::text) from generate_series(1, $rows) s(i)"
				elif [ "$dataset" == "linear-fuzz" ]; then
					distinct=$((rows/100))
					fuzz=$((distinct*FUZZ/100))
					psql test -c "insert into bitmap_scan_test select ($distinct * (i * 1.0 / $rows)) + $fuzz * random(), i, md5(random()::text) from generate_series(1, $rows) s(i)"
				elif [ "$dataset" == "cyclic" ]; then
					cycle=$((rows/CYCLES))
					distinct=$((rows/cycle))
					psql test -c "insert into bitmap_scan_test select ($distinct * (mod(i,$cycle) * 1.0 / $cycle)), i, md5(random()::text) from generate_series(1, $rows) s(i)"
				elif [ "$dataset" == "cyclic-fuzz" ]; then
					cycle=$((rows/CYCLES))
					distinct=$((rows/cycle))
					fuzz=$((distinct*FUZZ/100))
					psql test -c "insert into bitmap_scan_test select ($distinct * (mod(i,$cycle) * 1.0 / $cycle)) + $fuzz * random(), i, md5(random()::text) from generate_series(1, $rows) s(i)"
				fi

				psql test -c "create index on bitmap_scan_test (a)"
				psql test -c "vacuum analyze"
				psql test -c "checkpoint"

				relpages=$(psql test -t -A -c "select relpages from pg_class where relname = 'bitmap_scan_test'")

				for workers in 0 4; do

					# work_mem in kilobytes
					for wm in 128 $((4*1024)) $((64*1024)); do

						for eic in 0 1 8 16 32; do

							for ioc in 16 1 32 8; do

								for ra in 256 2048 8192; do

									if [ "$dev" == "samsung-990-pro" ]; then
										sudo blockdev --setra $ra /dev/nvme1n1p1
									elif [ "$dev" == "wd-sn640" ]; then
										sudo blockdev --setra $ra /dev/nvme0n1p1
									fi

									for build in master patched-melanie patched-thomas; do

										PATH=/home/tomas/builds/$build/bin:$PATH_OLD

										matches=1

										while /bin/true; do

											# did we match the whole dataset already?
											if [[ $matches -gt $distinct ]]; then
												break
											fi

											if [[ $((distinct/5)) -gt $matches ]]; then
												matches=$((matches*2))
											else
												matches=$((matches+distinct/5))
											fi

											from=$(psql -t -A test -c "SELECT (random() * ($distinct - $matches))::int")
											to=$((from + matches))

											# clean all caches (OS and postgres)
											drop_caches
											restart_postgres /mnt/$dev/data

											check_postgres_build $build

											# is bitmap heap scan the optimal plan?
											psql test > explain.log 2>&1 <<EOF
SET max_parallel_workers_per_gather = $workers;
SET effective_io_concurrency = $eic;
SET io_combine_limit = $ioc;
SET parallel_setup_cost = 0;
SET parallel_tuple_cost = 0;
SET work_mem = '${wm}kB';
EXPLAIN SELECT * FROM bitmap_scan_test WHERE (a BETWEEN $from AND $to) OFFSET $rows;
EOF

											bitmapscan=$(grep ' Bitmap Heap Scan' explain.log | wc -l)
											seqscan=$(grep ' Seq Scan' explain.log | wc -l)
											indexscan=$(grep ' Index Scan' explain.log | wc -l)

											optimal="unknown"
											if [ "$bitmapscan" == "1" ]; then
												optimal="bitmapscan"
											elif [ "$seqscan" == "1" ]; then
												optimal="seqscan"
											elif [ "$indexscan" == "1" ]; then
												optimal="indexscan"
											else
												cat explain.log
											fi


											psql test > timing.log 2>&1 <<EOF
SET enable_seqscan = off;
SET enable_indexscan = off;
SET max_parallel_workers_per_gather = $workers;
SET effective_io_concurrency = $eic;
SET io_combine_limit = $ioc;
SET parallel_setup_cost = 0;
SET parallel_tuple_cost = 0;
SET work_mem = '${wm}kB';

EXPLAIN SELECT * FROM bitmap_scan_test WHERE (a BETWEEN $from AND $to) OFFSET $rows;

\timing on
SELECT * FROM bitmap_scan_test WHERE (a BETWEEN $from AND $to) OFFSET $rows;
EOF

											t=`grep Time timing.log | awk '{print $2}'`

											echo $dev $build $rows $dataset $relpages $workers $wm $eic $ioc $ra $matches $distinct $run uncached $optimal $t >> $OUTDIR/results.csv

											echo "========== dev: $dev  build: $build  rows: $rows  dataset: $dataset  relpages: $relpages  workers: $workers  work_mem: $wm  effective_io_concurrency: $eic  io_combine_limit: $ioc  read-ahead: $ra  matches: $matches  distinct: $distinct  run: $run  caching: uncached  optimal: $optimal  timing: $t ==========" >> $OUTDIR/explain.log 2>&1
											cat timing.log >> $OUTDIR/explain.log 2>&1

											# clean shared buffers (but keep OS cache)
											restart_postgres /mnt/$dev/data

											check_postgres_build $build

											psql test > timing.log 2>&1 <<EOF
SET enable_seqscan = off;
SET enable_indexscan = off;
SET max_parallel_workers_per_gather = $workers;
SET effective_io_concurrency = $eic;
SET io_combine_limit = $ioc;
SET parallel_setup_cost = 0;
SET parallel_tuple_cost = 0;
SET work_mem = '${wm}kB';

EXPLAIN SELECT * FROM bitmap_scan_test WHERE (a BETWEEN $from AND $to) OFFSET $rows;

\timing on
SELECT * FROM bitmap_scan_test WHERE (a BETWEEN $from AND $to) OFFSET $rows;
EOF

											t=`grep Time timing.log | awk '{print $2}'`

											echo $dev $build $rows $dataset $relpages $workers $wm $eic $ioc $ra $matches $distinct $run cached-os $optimal $t >> $OUTDIR/results.csv

											echo "========== dev: $dev  build: $build  rows: $rows  dataset: $dataset  relpages: $relpages  workers: $workers  work_mem: $wm  effective_io_concurrency: $eic  io_combine_limit: $ioc  read-ahead: $ra  matches: $matches  distinct: $distinct  run: $run  caching: cached-os  optimal: $optimal  timing: $t ==========" >> $OUTDIR/explain.log 2>&1
											cat timing.log >> $OUTDIR/explain.log 2>&1

											# keep both caches
											psql test > timing.log 2>&1 <<EOF
SET enable_seqscan = off;
SET enable_indexscan = off;
SET max_parallel_workers_per_gather = $workers;
SET effective_io_concurrency = $eic;
SET io_combine_limit = $ioc;
SET parallel_setup_cost = 0;
SET parallel_tuple_cost = 0;
SET work_mem = '${wm}kB';

EXPLAIN SELECT * FROM bitmap_scan_test WHERE (a BETWEEN $from AND $to) OFFSET $rows;

\timing on
SELECT * FROM bitmap_scan_test WHERE (a BETWEEN $from AND $to) OFFSET $rows;
EOF

											t=`grep Time timing.log | awk '{print $2}'`

											echo $dev $build $rows $dataset $relpages $workers $wm $eic $ioc $ra $matches $distinct $run cached $optimal $t >> $OUTDIR/results.csv

											echo "========== dev: $dev  build: $build  rows: $rows  dataset: $dataset  relpages: $relpages  workers: $workers  work_mem: $wm  effective_io_concurrency: $eic  io_combine_limit: $ioc  read-ahead: $ra  matches: $matches  distinct: $distinct  run: $run  caching: cached  optimal: $optimal  timing: $t ==========" >> $OUTDIR/explain.log 2>&1
											cat timing.log >> $OUTDIR/explain.log 2>&1

										done

									done

								done

							done

						done

					done

				done

			done

			# stop using the old data directory
			stop_postgres /mnt/$dev/data

		done

	done

done
