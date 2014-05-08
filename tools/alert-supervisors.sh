#!/bin/bash

DB_NAME=${1:-carma}

SUBJECT="[Действия] - Сообщение от CaRMa"
EMAIL_TO="supervisor@ruamc.ru, robots@formalmethods.ru"
EMAIL_FROM="carma@carma.ruamc.ru"
EMAIL_SENDER="psa@ruamc.ru"

run_query () {
  psql -c "$1" \
    -t \
    --no-align \
    --field-separator ';' \
    --quiet \
    $DB_NAME | while IFS=';' read -ra Record; do
      echo "<tr>"
      for i in "${Record[@]}"; do
        echo "<td>$i</td>"
      done
      echo "</tr>"
    done
}

build_table () {
  cat << EOF
    <table width=100% border="1" style="border-collapse:collapse;"
      cellpadding="2" cellspacing="2">
      <thead>
        <tr>
          <th>
            URL
          </th>
          <th>
            Номер кейса
          </th>
          <th>
            Оператор
          </th>
          <th>
            Просрочено
          </th>
          <th>
            Тип действия
          </th>
          <th>
            Запланировано
          </th>
          <th>
            Город
          </th>
          <th>
            Программа
          </th>
        </tr>
      </thead>
      <tbody>
        $1
      </tbody>
    </table>
EOF
}

send_message () {
/usr/sbin/sendmail -t -r $EMAIL_SENDER << EOF
From: $EMAIL_FROM
To: $EMAIL_TO
Subject: $SUBJECT
MIME-Version: 1.0
Content-Type: text/html
Content-Disposition: inline

$1

EOF
}

UNASSIGNED="
  SELECT
    replace(caseid, 'case:', 'http://carma:8000/#case/'),
    split_part(caseid, ':', 2),
    assignedto,
    date_trunc('seconds', now() - ctime),
    \"ActionName\".label,
    duetime,
    \"City\".label,
    \"Program\".label
  FROM
    actiontbl
  LEFT JOIN \"ActionName\" ON actiontbl.name = \"ActionName\".value
  INNER JOIN casetbl ON split_part(actiontbl.caseid, ':', 2)::int = casetbl.id
  LEFT JOIN \"City\" ON casetbl.city = \"City\".value
  LEFT JOIN \"Program\" ON casetbl.program = \"Program\".id
  WHERE
    NOT closed
    AND ctime > now()::date - 7
    AND now() > duetime
    AND name = ANY ('{orderService, callMeMaybe, orderServiceAnalyst, tellMeMore}')
    AND assigntime IS NULL
    AND now() > ('5 minutes'::interval + ctime)
"

OUTSTANDING="
  SELECT
    replace(caseid, 'case:', 'http://carma:8000/#case/'),
    split_part(caseid, ':', 2),
    assignedto,
    date_trunc('seconds', now() - assigntime),
    \"ActionName\".label,
    duetime,
    \"City\".label,
    \"Program\".label
  FROM
    actiontbl
  LEFT JOIN \"ActionName\" ON actiontbl.name = \"ActionName\".value
  INNER JOIN casetbl ON split_part(actiontbl.caseid, ':', 2)::int = casetbl.id
  LEFT JOIN \"City\" ON casetbl.city = \"City\".value
  LEFT JOIN \"Program\" ON casetbl.program = \"Program\".id
  WHERE
    NOT closed
    AND ctime > now()::date - 7
    AND now() > ('10 minutes'::interval + duetime)
    AND name = ANY ('{orderService, callMeMaybe, orderServiceAnalyst, tellMeMore}')
    AND (assigntime IS NOT NULL AND closetime IS NULL)
    AND now() > ('15 minutes'::interval + assigntime)
"

UNASSIGNED_RESULT=$(run_query "$UNASSIGNED")
OUTSTANDING_RESULT=$(run_query "$OUTSTANDING")
MESSAGE=""

if [[ ! -z "$UNASSIGNED_RESULT" ]]
then
  UNASSIGNED_TABLE=$(build_table "$UNASSIGNED_RESULT")
  MESSAGE="$MESSAGE <h3>Нераспределенные действия</h3> $UNASSIGNED_TABLE"
fi

if [[ ! -z "$OUTSTANDING_RESULT" ]]
then
  OUTSTANDING_TABLE=$(build_table "$OUTSTANDING_RESULT")
  MESSAGE="$MESSAGE <h3>Невыполненные действия</h3> $OUTSTANDING_TABLE"
fi

if [[ ! -z "$MESSAGE" ]]
then
  send_message "$MESSAGE"
fi

