-- Convert schema '/home/martchus/repos/openQA/script/../dbicdh/_source/deploy/60/001-auto.yml' to '/home/martchus/repos/openQA/script/../dbicdh/_source/deploy/61/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE assets ADD COLUMN last_use_job_id integer;

;
ALTER TABLE assets ADD COLUMN fixed boolean DEFAULT '0' NOT NULL;

;
CREATE INDEX assets_idx_last_use_job_id on assets (last_use_job_id);

;
ALTER TABLE assets ADD CONSTRAINT assets_fk_last_use_job_id FOREIGN KEY (last_use_job_id)
  REFERENCES jobs (id) DEFERRABLE;

;
ALTER TABLE job_groups ADD COLUMN exclusively_kept_asset_size integer;

;

COMMIT;

