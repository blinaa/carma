DELETE FROM "ProgramInfo" WHERE program IS NULL;
ALTER TABLE "ProgramInfo" ALTER COLUMN program SET NOT NULL;
