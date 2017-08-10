#!/usr/bin/env bash
set -e

initdb -D "$PGDATA"
perl -p -i -e 's/^unix_socket_directories = .*\n//' "$PGDATA/postgresql.conf"
echo $'unix_socket_directories = \'/tmp\'' >> "$PGDATA/postgresql.conf"
postgres -D "$PGDATA" -h 127.0.0.1 -p 5432 &
PGPID=$!
sleep 2

echo $'

ALTER  USER postgres      WITH           PASSWORD \'pass\';
CREATE USER carma         WITH SUPERUSER PASSWORD \'pass\';
CREATE USER carma_db_sync WITH SUPERUSER PASSWORD \'pass\';

CREATE USER carma_geo;
CREATE USER carma_sms;
CREATE USER mail_svc;
CREATE USER fmuser;
CREATE USER "pavel.golovnin";
CREATE USER reportgen;

' | psql -h 127.0.0.1

echo 'CREATE DATABASE carma;' | psql -h 127.0.0.1 -U carma_db_sync -d postgres

kill -TERM "$PGPID"
sleep 2
kill -KILL "$PGPID" 2>/dev/null || true
sleep 1

chmod go-rwx -R "$PGDATA"
