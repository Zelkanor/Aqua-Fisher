export const SCHEMA_VERSION = "1.0" as const;

export type ComplianceStandard =
  "CPCB_CLASS_B" | "BIS_10500" | "WHO" | "CUSTOM";

export type UserRole = "admin" | "operator" | "client";

export type AlertSeverity = "info" | "warning" | "critical";
