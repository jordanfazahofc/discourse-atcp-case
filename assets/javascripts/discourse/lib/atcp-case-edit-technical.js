export const TECHNICAL_FIELDS = [
  "symptom",
  "frequency",
  "non_trigger_conditions",
  "bios_version",
  "os_driver_info",
];

export const TECHNICAL_OPTIONAL_FIELDS = TECHNICAL_FIELDS.filter(
  (field) => field !== "symptom",
);

function normalize(value) {
  return String(value ?? "").trim();
}

export function buildCreateTechnicalPayload(data) {
  const payload = {};

  TECHNICAL_OPTIONAL_FIELDS.forEach((field) => {
    const value = normalize(data?.[field]);

    if (value) {
      payload[field] = value;
    }
  });

  return payload;
}

export function buildEditTechnicalPayload({ atcpCase, data }) {
  const payload = {};

  TECHNICAL_FIELDS.forEach((field) => {
    const nextValue = normalize(data?.[field]);
    const initialValue = normalize(atcpCase?.[field]);

    if (nextValue !== initialValue) {
      payload[field] = nextValue;
    }
  });

  return payload;
}
