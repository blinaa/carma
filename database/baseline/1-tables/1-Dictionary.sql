CREATE TABLE "Dictionary"
  (id          SERIAL PRIMARY KEY
  ,name        text UNIQUE NOT NULL
  ,description text
  ,parent      int4 REFERENCES "Dictionary"
  ,majorFields text[] default array[]::text[]
  );

INSERT INTO "Dictionary" (id, name, description, parent, majorFields) VALUES
  (0, 'CarMake', 'Марка машины', null, ARRAY['id', 'label'])
, (1, 'CarModel', 'Модель машины', 0, ARRAY['id', 'parent', 'label', 'info'])
, (2, 'City', 'Город', 0, ARRAY['id', 'label'])
, (3, 'Region', 'Регион', 0, ARRAY['id', 'label'])
, (4, 'NewCaseField', 'Поля для экрана нового кейса', null, ARRAY['id', 'program', 'label'])
, (5, 'FieldPermission', 'Разрешения для полей', null, ARRAY['id', 'role', 'model', 'field'])
, (6, 'SmsTemplate', 'Шаблон СМС', null, ARRAY['id', 'label'])
, (7, 'Role', 'Роли', null, ARRAY['id', 'value', 'label'])
, (8, 'ProgramInfo', 'Информация о программах', null, ARRAY['id', 'program', 'info'])
, (9, 'ServiceNames', 'Услуги', null, ARRAY['id', 'value', 'label', 'icon'])
, (10, 'ServiceInfo', 'Информация об услугах', null, ARRAY['id', 'program', 'service', 'info'])
, (11, 'Program', 'Программа', null, ARRAY['id', 'label'])
, (12, 'SubProgram', 'Подпрограмма', 11, ARRAY['id', 'parent', 'label'])
, (13, 'SynCarMake', 'Синонимы марок', null, ARRAY['make', 'label'])
, (14, 'SynCarModel', 'Синонимы моделей', null, ARRAY['make', 'model', 'label'])
, (15, 'Colors', 'Цвета', null, ARRAY['id', 'value', 'label'])
, (16, 'ProgramType', 'Типы программ', null, ARRAY['id', 'label'])
, (17, 'Engine', 'Типы двигателя', null, ARRAY['id', 'label'])
, (18, 'Transmission', 'Коробки передач', null, ARRAY['id', 'label'])
, (19, 'SynEngine', 'Синонимы типов двигателя', null, ARRAY['id', 'engine', 'label'])
, (20, 'SynTransmission', 'Синонимы коробок передач', null, ARRAY['id', 'transmission', 'label'])
;

GRANT SELECT ON "Dictionary" TO carma_db_sync;
GRANT SELECT ON "Dictionary" TO carma_search;
