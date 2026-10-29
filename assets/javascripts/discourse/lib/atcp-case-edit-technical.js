export const TECHNICAL_FIELDS = [
  "symptom",
  "frequency",
  "reproducibility",
  "non_trigger_conditions",
  "bios_version",
  "os_driver_info",
];

function normalize(value) {
  return String(value ?? "").trim();
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
