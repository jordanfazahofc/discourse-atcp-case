function normalizeMessages(value) {
  if (value === undefined || value === null) {
    return [];
  }

  const messages = Array.isArray(value) ? value : [value];

  return messages
    .flatMap((message) => (Array.isArray(message) ? message : [message]))
    .filter((message) => message !== undefined && message !== null)
    .map((message) => String(message).trim())
    .filter(Boolean);
}

export function normalizeCaseErrors(payload) {
  const errors = payload?.errors;

  if (!errors) {
    return { fieldErrors: {}, baseErrors: [] };
  }

  if (Array.isArray(errors) || typeof errors !== "object") {
    return { fieldErrors: {}, baseErrors: normalizeMessages(errors) };
  }

  const fieldErrors = {};
  const baseErrors = [];

  Object.entries(errors).forEach(([field, value]) => {
    const messages = normalizeMessages(value);

    if (messages.length === 0) {
      return;
    }

    if (!field || field === "base") {
      baseErrors.push(...messages);
    } else {
      fieldErrors[field] = messages;
    }
  });

  return { fieldErrors, baseErrors };
}
