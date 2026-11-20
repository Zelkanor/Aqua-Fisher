library;

/// Canonical ICD schema version enforced across all telemetry streams.
const String aquaSchemaVersion = '1.0';

enum ComplianceStandard {
  cpcbClassB('CPCB_CLASS_B'),
  bis10500('BIS_10500'),
  who('WHO'),
  custom('CUSTOM');

  const ComplianceStandard(this.wireValue);
  final String wireValue;
}

enum UserRole { admin, operator, client }

enum AlertSeverity { info, warning, critical }
