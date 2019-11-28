-- Convert schema '/hdd/openqa-devel/repos/openQA/script/../dbicdh/_source/deploy/83/001-auto.yml' to '/hdd/openqa-devel/repos/openQA/script/../dbicdh/_source/deploy/84/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE job_group_parents DROP COLUMN default_size_limit_gb;

;
ALTER TABLE job_group_parents ADD COLUMN size_limit_gb integer;

;
ALTER TABLE job_group_parents ADD COLUMN exclusively_kept_asset_size bigint;

;

COMMIT;

