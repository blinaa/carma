
CREATE TABLE "Sms"
  (id        SERIAL PRIMARY KEY
  ,ctime     timestamptz NOT NULL DEFAULT 'now()'
  ,mtime     timestamptz NOT NULL DEFAULT 'now()'
  ,status    text NOT NULL DEFAUlT 'draft'
  ,caseRef   text -- REFERENCES "casetbl"
  ,phone     text NOT NULL
  ,sender    text
  ,template  int4 REFERENCES "SmsTemplate"
  ,msgText   text NOT NULL
  ,foreignId text
  );

GRANT ALL ON "Sms" TO carma_search;
GRANT ALL ON "Sms" TO carma_db_sync;
GRANT ALL ON "Sms_id_seq" TO carma_search;
GRANT ALL ON "Sms_id_seq" TO carma_db_sync;
