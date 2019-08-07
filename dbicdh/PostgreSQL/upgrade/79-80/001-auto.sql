-- Convert schema '/hdd/openqa-devel/repos/openQA/script/../dbicdh/_source/deploy/79/001-auto.yml' to '/hdd/openqa-devel/repos/openQA/script/../dbicdh/_source/deploy/80/001-auto.yml':;

;
BEGIN;

;
CREATE INDEX idx_t_created on audit_events (t_created);

;

COMMIT;

