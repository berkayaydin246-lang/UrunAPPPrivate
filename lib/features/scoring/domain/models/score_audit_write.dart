enum ScoreAuditTriggerSource {
  submissionApproval('submission_approval'),
  stagingApproval('staging_approval'),
  verifiedCorrection('verified_correction'),
  catalogueChange('catalogue_change'),
  controlledBackfill('controlled_backfill');

  const ScoreAuditTriggerSource(this.databaseValue);

  final String databaseValue;
}

class ScoreAuditSnapshotWriteResult {
  const ScoreAuditSnapshotWriteResult({
    required this.snapshotId,
    required this.inserted,
  });

  final String snapshotId;
  final bool inserted;
}
