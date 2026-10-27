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
  bodyOnly = false,
  uploadIds = [],
  removeAttachmentIds = [],
}) {
  const payload = {};
  const nextBody = trim(body);
  const initialBody = trim(initialUpdate?.body);

  if (!bodyOnly) {
    const nextUpdateType = trim(updateType);
    const initialUpdateType = trim(initialUpdate?.update_type);

    if (nextUpdateType !== initialUpdateType) {
      payload.update_type = nextUpdateType;
    }
  }

  if (nextBody !== initialBody) {
    payload.body = nextBody;
  }

  if (!bodyOnly && uploadIds.length) {
    payload.upload_ids = [...uploadIds];
  }

  if (!bodyOnly && removeAttachmentIds.length) {
    payload.remove_attachment_ids = [...removeAttachmentIds];
  }

  return payload;
}
