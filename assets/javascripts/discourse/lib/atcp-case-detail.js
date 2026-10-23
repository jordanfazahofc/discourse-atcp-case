import moment from "moment";
import { relativeAge } from "discourse/lib/formatter";
import { i18n } from "discourse-i18n";

export const CASE_DETAIL_TABS = ["progress", "technical", "attachments"];
export const DEFAULT_CASE_DETAIL_TAB = "progress";

export function normalizeCaseDetailTab(value) {
  const tab = String(value || "")
    .trim()
    .toLowerCase();

  return CASE_DETAIL_TABS.includes(tab) ? tab : DEFAULT_CASE_DETAIL_TAB;
}

function parseCaseDate(value) {
  return value ? moment(value, moment.ISO_8601, true) : moment.invalid();
}

export function formatCaseDate(value) {
  const date = parseCaseDate(value);

  return date.isValid() ? date.format("D MMM YYYY") : "-";
}

export function formatCaseDateTime(value) {
  const date = parseCaseDate(value);

  return date.isValid() ? date.format("D MMM YYYY, HH:mm") : "-";
}

export function relativeCaseTime(value) {
  const date = parseCaseDate(value);

  if (!date.isValid()) {
    return "-";
  }

  try {
    return relativeAge(date.toDate()) || formatCaseDate(value);
  } catch {
    return formatCaseDate(value);
  }
}

export function displayUserName(user) {
  return user?.name || user?.username || "-";
}

export function productLabel(name, sku) {
  const productName = name == null ? "" : String(name);
  const productSku = sku == null ? "" : String(sku).trim();

  if (
    !productSku ||
    productName.toLowerCase().includes(productSku.toLowerCase())
  ) {
    return productName;
  }

  return `${productName} (${productSku})`;
}

export function caseProductLabel(product) {
  const name = product?.name || "-";

  if (product?.id === null || product?.id === undefined) {
    return name;
  }

  return productLabel(name, product.sku);
}

export function caseReporterLabel(atcpCase) {
  const name = atcpCase?.reporter_name?.trim();
  const branch = atcpCase?.reporter_branch_name?.trim();

  return [name, branch].filter(Boolean).join(" · ") || "-";
}

export function hasResolutionContent(atcpCase) {
  if (atcpCase?.status === "Closed") {
    return true;
  }

  return ["solution", "root_cause_summary", "workaround", "conclusion"].some(
    (field) => Boolean(atcpCase?.[field]?.trim())
  );
}

export function systemEventText(update) {
  const from = String(update?.from_value ?? "").trim() || "-";
  const to = String(update?.to_value ?? "").trim() || "-";
  const closeReason =
    String(update?.details?.close_reason ?? "").trim() || "-";

  switch (update?.system_event) {
    case "status_changed":
      return i18n("atcp_case.cases.detail.system.status_changed", { from, to });
    case "severity_changed":
      return i18n("atcp_case.cases.detail.system.severity_changed", {
        from,
        to,
      });
    case "assignee_changed":
      return i18n("atcp_case.cases.detail.system.assignee_changed", {
        from,
        to,
      });
    case "closed":
      return i18n("atcp_case.cases.detail.system.closed", { close_reason: closeReason });
    case "reopened":
      return i18n("atcp_case.cases.detail.system.reopened");
    default:
      return i18n("atcp_case.cases.detail.system.unknown", { from, to });
  }
}

export function collectCaseAttachments(updates = []) {
  return updates.flatMap((update) =>
    (update.attachments || []).map((attachment) => ({
      ...attachment,
      update_id: update.id,
      update_type: update.update_type,
      uploaded_by: displayUserName(update.user),
      created_at: update.created_at,
    }))
  );
}
