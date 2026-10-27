import { MAX_ATTACHMENTS } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-add-update";

export function remainingAttachmentCount(
  existingAttachments = [],
  removeAttachmentIds = []
) {
  const removedIds = new Set(removeAttachmentIds);

  return existingAttachments.filter(
    (attachment) => !removedIds.has(attachment?.id)
  ).length;
}

export function totalAttachmentCount({
  existingAttachments = [],
  removeAttachmentIds = [],
  uploadIds = [],
}) {
  return (
    remainingAttachmentCount(existingAttachments, removeAttachmentIds) +
    uploadIds.length
  );
}

export function exceedsAttachmentLimit(attributes) {
  return totalAttachmentCount(attributes) > MAX_ATTACHMENTS;
}
