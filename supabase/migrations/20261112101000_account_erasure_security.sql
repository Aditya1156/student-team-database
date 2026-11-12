-- Complete DB-026 access isolation for existing evidence deletion/hold tables.
alter table safety.evidence_storage_deletion_jobs enable row level security;
alter table safety.legal_hold_evidence enable row level security;

revoke all on safety.evidence_storage_deletion_jobs,
  safety.legal_hold_evidence
from public,anon,authenticated;

grant all on safety.evidence_storage_deletion_jobs,
  safety.legal_hold_evidence
to service_role;

