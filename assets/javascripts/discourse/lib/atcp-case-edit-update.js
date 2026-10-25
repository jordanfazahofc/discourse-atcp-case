import { MAX_UPDATE_TYPE_LENGTH } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-add-update";

function trim(value) {
  return String(value ?? "").trim();
}

export function validateEditUpdateType(updateType) {
  const value = trim(updateType);

  if (!value) {
    return { key: "required" };
  }

  if (value.length > MAX_UPDATE_TYPE_LENGTH) {
    return { key: "too_long", max: MAX_UPDATE_TYPE_LENGTH };
  }

  return null;
}

export function buildEditUpdatePayload({
  initialUpdate,
  updateType,
  body,
}) {
  const payload = {};
  const nextUpdateType = trim(updateType);
  const initialUpdateType = trim(initialUpdate?.update_type);
  const nextBody = trim(body);
  const initialBody = trim(initialUpdate?.body);

  if (nextUpdateType !== initialUpdateType) {
    payload.update_type = nextUpdateType;
  }

  if (nextBody !== initialBody) {
    payload.body = nextBody;
  }

  return payload;
}
