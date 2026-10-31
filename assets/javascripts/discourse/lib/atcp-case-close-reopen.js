export const CLOSE_REASONS = Object.freeze([
  "Resolved",
  "Duplicate",
  "Cannot Reproduce",
  "Won't Fix",
  "Cancelled",
]);

export const REOPEN_REASON_MAX_LENGTH = 2000;

const OPTIONAL_CLOSE_FIELDS = Object.freeze([
  "solution",
  "root_cause_summary",
  "workaround",
  "conclusion",
]);

function normalized(value) {
  return String(value ?? "").trim();
}

export function closeReasonOptions(reasons) {
  const available = Array.isArray(reasons) && reasons.length
    ? reasons
    : CLOSE_REASONS;

  return [...new Set(available.map(normalized).filter(Boolean))];
}

export function closeInitialData(atcpCase) {
  return {
    close_reason: "",
    solution: normalized(atcpCase?.solution),
    root_cause_summary: normalized(atcpCase?.root_cause_summary),
    workaround: normalized(atcpCase?.workaround),
    conclusion: normalized(atcpCase?.conclusion),
  };
}

export function buildCloseCasePayload({ atcpCase, data }) {
  const payload = {
    close_reason: normalized(data?.close_reason),
  };

  OPTIONAL_CLOSE_FIELDS.forEach((field) => {
    const value = normalized(data?.[field]);

    if (value !== normalized(atcpCase?.[field])) {
      payload[field] = value;
    }
  });

  return payload;
}

export function hasCloseCaseChanges({ atcpCase, data }) {
  const payload = buildCloseCasePayload({ atcpCase, data });

  return payload.close_reason !== "" || Object.keys(payload).length > 1;
}

export function buildReopenPayload(reason) {
  return { reason: normalized(reason) };
}
