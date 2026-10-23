export const MAX_ATTACHMENTS = 20;
export const KEEP_CURRENT_STATUS = "";
export const DEFAULT_UPDATE_TYPE = "General note";

export const FALLBACK_ADD_UPDATE_FORM_OPTIONS = Object.freeze({
  update_labels: Object.freeze([DEFAULT_UPDATE_TYPE]),
  statuses: Object.freeze([
    "Open",
    "In Progress",
    "On Hold",
    "Solution Found",
    "Closed",
  ]),
  upload: Object.freeze({ extensions: Object.freeze([]), max_mb: 100 }),
});

export function defaultUpdateType(labels = []) {
  const available = Array.isArray(labels) ? labels : [];

  return available.includes(DEFAULT_UPDATE_TYPE)
    ? DEFAULT_UPDATE_TYPE
    : available[0] || DEFAULT_UPDATE_TYPE;
}

export function normalizeUploadFileName(name) {
  return String(name || "")
    .trim()
    .toLowerCase();
}

export function resolveUploadCompletion(files = [], upload = {}) {
  const uploadedName = normalizeUploadFileName(
    upload.file_name || upload.original_filename
  );
  const matched = uploadedName
    ? files.filter(
        (file) => normalizeUploadFileName(file?.name) === uploadedName
      )
    : [];

  if (matched.length) {
    return { matched, unmatched: [] };
  }

  const candidates = files.filter((file) => file?.status === "uploading");

  if (candidates.length === 1) {
    return { matched: candidates, unmatched: [] };
  }

  if (candidates.length > 1) {
    return { matched: [], unmatched: candidates };
  }

  return { matched: [], unmatched: [] };
}

function normalizeExtensions(extensions) {
  return (Array.isArray(extensions) ? extensions : [])
    .map((extension) =>
      String(extension || "")
        .trim()
        .toLowerCase()
        .replace(/^\./, "")
    )
    .filter(Boolean);
}

function normalizeMaxMb(value) {
  const maxMb = Number(value);
  return Number.isFinite(maxMb) && maxMb > 0 ? maxMb : 100;
}

function fileNameExtension(fileName) {
  const name = String(fileName || "");
  const separator = name.lastIndexOf(".");
  return separator === -1 ? "" : name.slice(separator + 1).toLowerCase();
}

export function attachmentValidation(file, uploadOptions = {}) {
  const extensions = normalizeExtensions(uploadOptions.extensions);

  if (
    extensions.length &&
    !extensions.includes(fileNameExtension(file?.name))
  ) {
    return { key: "file_type" };
  }

  const maxMb = normalizeMaxMb(uploadOptions.max_mb);
  if (Number(file?.size) > maxMb * 1024 * 1024) {
    return { key: "file_size", maxMb };
  }

  return null;
}

export function isDuplicateFile(file, files = []) {
  const name = normalizeUploadFileName(file?.name);

  return files.some(
    (existing) => normalizeUploadFileName(existing?.name) === name
  );
}

export function hasAttachmentCapacity(files = []) {
  return files.length < MAX_ATTACHMENTS;
}

export function addUpdateStatusOptions(statuses, currentStatus) {
  const available = statuses?.length
    ? statuses
    : FALLBACK_ADD_UPDATE_FORM_OPTIONS.statuses;

  return [...new Set(available)]
    .map((status) => String(status || "").trim())
    .filter(
      (status) => status && status !== "Closed" && status !== currentStatus
    );
}

export function buildAddUpdatePayload({
  updateType,
  body,
  status,
  uploadIds = [],
}) {
  const payload = {
    update_type: String(updateType || "").trim(),
    upload_ids: [...uploadIds],
  };

  const note = String(body || "").trim();
  if (note) {
    payload.body = note;
  }

  if (status) {
    payload.status = status;
  }

  return payload;
}
