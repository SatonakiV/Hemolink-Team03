CREATE TABLE database_meta (
  singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
  payload TEXT NOT NULL CHECK(json_valid(payload) AND json_type(payload, '$.version') IS 'integer' AND json_extract(payload, '$.version') = 1),
  sequence INTEGER NOT NULL CHECK(sequence >= 0)
) STRICT;
INSERT INTO database_meta VALUES (1, '{"version":1}', 0);

CREATE TABLE users (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id) > 0),
  position INTEGER NOT NULL UNIQUE CHECK(position >= 0),
  payload TEXT NOT NULL CHECK(json_valid(payload)),
  email TEXT GENERATED ALWAYS AS (json_extract(payload, '$.email')) STORED NOT NULL,
  CHECK(json_type(payload, '$.id') IS 'text' AND json_extract(payload, '$.id') = id),
  CHECK(json_type(payload, '$.email') IS 'text' AND length(trim(email)) > 0)
) STRICT;
CREATE UNIQUE INDEX users_email ON users(lower(trim(email)));
CREATE INDEX users_email_lookup ON users(email);

CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY NOT NULL CHECK(length(token_hash) = 64 AND token_hash NOT GLOB '*[^0-9a-f]*'),
  position INTEGER NOT NULL UNIQUE CHECK(position >= 0),
  payload TEXT NOT NULL CHECK(json_valid(payload)),
  user_id TEXT GENERATED ALWAYS AS (json_extract(payload, '$.userId')) STORED NOT NULL,
  expires_at INTEGER GENERATED ALWAYS AS (json_extract(payload, '$.expiresAt')) STORED NOT NULL,
  CHECK(json_type(payload, '$.tokenHash') IS 'text' AND json_extract(payload, '$.tokenHash') = token_hash),
  CHECK(json_type(payload, '$.expiresAt') IS 'integer' AND expires_at > 0),
  FOREIGN KEY(user_id) REFERENCES users(id) DEFERRABLE INITIALLY DEFERRED
) STRICT;
CREATE INDEX sessions_expiration ON sessions(expires_at);
CREATE INDEX sessions_user ON sessions(user_id);

CREATE TABLE records (
  module TEXT NOT NULL CHECK(length(module) > 0),
  id TEXT NOT NULL CHECK(length(id) > 0),
  position INTEGER NOT NULL UNIQUE CHECK(position >= 0),
  payload TEXT NOT NULL CHECK(json_valid(payload)),
  scope_id TEXT GENERATED ALWAYS AS (json_extract(payload, '$.scopeId')) STORED NOT NULL,
  donor_id TEXT GENERATED ALWAYS AS (json_extract(payload, '$.donanteId')) STORED,
  donor_module TEXT GENERATED ALWAYS AS (
    CASE WHEN module IN ('evaluations', 'donations', 'samples') AND donor_id IS NOT NULL THEN 'donors' END
  ) STORED,
  evaluation_id TEXT GENERATED ALWAYS AS (json_extract(payload, '$.evaluacionId')) STORED,
  evaluation_module TEXT GENERATED ALWAYS AS (
    CASE WHEN module = 'donations' AND evaluation_id IS NOT NULL THEN 'evaluations' END
  ) STORED,
  donation_id TEXT GENERATED ALWAYS AS (json_extract(payload, '$.donacionId')) STORED,
  donation_module TEXT GENERATED ALWAYS AS (
    CASE WHEN module IN ('inventory', 'samples') AND donation_id IS NOT NULL THEN 'donations' END
  ) STORED,
  sample_donation_module TEXT GENERATED ALWAYS AS (
    CASE WHEN module = 'samples' AND donation_id IS NOT NULL THEN 'donations' END
  ) STORED,
  rut TEXT GENERATED ALWAYS AS (json_extract(payload, '$.rut')) STORED,
  rut_clean TEXT GENERATED ALWAYS AS (
    upper(replace(replace(replace(replace(replace(replace(rut, '.', ''), '-', ''), ' ', ''), char(9), ''), char(10), ''), char(13), ''))
  ) STORED,
  rut_key TEXT GENERATED ALWAYS AS (ltrim(substr(rut_clean, 1, length(rut_clean) - 1), '0') || substr(rut_clean, -1)) STORED,
  code TEXT GENERATED ALWAYS AS (json_extract(payload, '$.codigo')) STORED,
  confirmation TEXT GENERATED ALWAYS AS (json_extract(payload, '$.claveConfirmacion')) STORED,
  responsible_id TEXT GENERATED ALWAYS AS (json_extract(payload, '$.responsableId')) STORED,
  registered_by TEXT GENERATED ALWAYS AS (json_extract(payload, '$.usuarioRegistroId')) STORED,
  modified_by TEXT GENERATED ALWAYS AS (json_extract(payload, '$.usuarioModificacionId')) STORED,
  PRIMARY KEY(module, id),
  UNIQUE(module, id, scope_id),
  UNIQUE(module, id, scope_id, donor_id),
  CHECK(json_type(payload, '$.id') IS 'text' AND json_extract(payload, '$.id') = id),
  CHECK(json_type(payload, '$.module') IS 'text' AND json_extract(payload, '$.module') = module),
  CHECK(json_type(payload, '$.scopeId') IS 'text' AND length(scope_id) > 0),
  CHECK(module <> 'evaluations' OR json_type(payload, '$.resultado') IS NULL OR donor_id IS NOT NULL),
  CHECK(module <> 'donations' OR json_type(payload, '$.fechaExtraccion') IS NULL OR (donor_id IS NOT NULL AND evaluation_id IS NOT NULL)),
  CHECK(module <> 'donations' OR evaluation_id IS NULL OR donor_id IS NOT NULL),
  CHECK(module NOT IN ('inventory', 'samples') OR code IS NULL OR donation_id IS NOT NULL),
  CHECK(module <> 'samples' OR code IS NULL OR donor_id IS NOT NULL),
  FOREIGN KEY(donor_module, donor_id, scope_id) REFERENCES records(module, id, scope_id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY(evaluation_module, evaluation_id, scope_id, donor_id) REFERENCES records(module, id, scope_id, donor_id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY(donation_module, donation_id, scope_id) REFERENCES records(module, id, scope_id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY(sample_donation_module, donation_id, scope_id, donor_id) REFERENCES records(module, id, scope_id, donor_id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY(responsible_id) REFERENCES users(id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY(registered_by) REFERENCES users(id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY(modified_by) REFERENCES users(id) DEFERRABLE INITIALLY DEFERRED
) STRICT;
CREATE INDEX records_scope ON records(module, scope_id, position);
CREATE INDEX records_id ON records(id);
CREATE INDEX records_scope_only ON records(scope_id, position);
CREATE INDEX records_donor ON records(module, scope_id, donor_id, position);
CREATE INDEX records_donor_reference ON records(donor_module, donor_id, scope_id);
CREATE INDEX records_evaluation ON records(evaluation_module, evaluation_id, scope_id, donor_id);
CREATE INDEX records_donation ON records(module, scope_id, donation_id, position);
CREATE INDEX records_donation_reference ON records(donation_module, donation_id, scope_id);
CREATE INDEX records_sample_donation ON records(sample_donation_module, donation_id, scope_id, donor_id);
CREATE INDEX records_responsible ON records(responsible_id);
CREATE INDEX records_registered ON records(registered_by);
CREATE INDEX records_modified ON records(modified_by);
CREATE UNIQUE INDEX donors_rut ON records(rut_key) WHERE module = 'donors' AND rut IS NOT NULL;
CREATE UNIQUE INDEX inventory_code ON records(upper(trim(code))) WHERE module = 'inventory' AND code IS NOT NULL;
CREATE UNIQUE INDEX samples_code ON records(upper(trim(code))) WHERE module = 'samples' AND code IS NOT NULL;
CREATE UNIQUE INDEX donations_confirmation ON records(scope_id, confirmation)
  WHERE module = 'donations' AND confirmation IS NOT NULL;
