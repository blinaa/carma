CREATE TABLE "SynCarModel"
  ( id    SERIAL PRIMARY KEY
  , make  int4 REFERENCES "CarMake"
  , model int4 REFERENCES "CarModel"
  , label text UNIQUE NOT NULL
  );

GRANT ALL ON "SynCarModel" TO carma_db_sync;
GRANT ALL ON "SynCarModel" TO carma_search;
GRANT ALL ON "SynCarModel_id_seq" TO carma_db_sync;
GRANT ALL ON "SynCarModel_id_seq" TO carma_search;
