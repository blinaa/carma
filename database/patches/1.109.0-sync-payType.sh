#!/bin/bash -e

REDIS=$(mktemp /tmp/redisXXXXXX)

TABLE="averagecommissionertbl"
MODEL="averagecommissioner"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="banktbl"
MODEL="bank"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="consultationtbl"
MODEL="consultation"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="continuetbl"
MODEL="continue"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="delivercartbl"
MODEL="delivercar"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="deliverclienttbl"
MODEL="deliverclient"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="deliverpartstbl"
MODEL="deliverparts"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="hoteltbl"
MODEL="hotel"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="informationtbl"
MODEL="information"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="insurancetbl"
MODEL="insurance"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="kentbl"
MODEL="ken"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="renttbl"
MODEL="rent"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="sobertbl"
MODEL="sober"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="taxitbl"
MODEL="taxi"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="tech1tbl"
MODEL="tech1"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="techtbl"
MODEL="tech"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="ticketstbl"
MODEL="tickets"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="towagetbl"
MODEL="towage"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="transportationtbl"
MODEL="transportation"
FIELD="payType"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

TABLE="partnercanceltbl"
MODEL="partnercancel"
FIELD="partnerCancelReason"
FIELDSIZE=${#FIELD}
${PSQL} -A -t -c "select concat(E'*4\r\n', '$', E'4\r\nHSET\r\n', '$', length(concat('${MODEL}:', id)), E'\r\n', concat('${MODEL}:', id), E'\r\n', '$', ${FIELDSIZE}, E'\r\n${FIELD}\r\n', '$', octet_length(coalesce(${FIELD}::text, '')), E'\r\n', ${FIELD}, E'\r') from ${TABLE};" > ${REDIS}
cat ${REDIS} | redis-cli --pipe

rm ${REDIS}
