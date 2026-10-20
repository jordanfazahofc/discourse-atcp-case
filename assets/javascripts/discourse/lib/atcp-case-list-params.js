export const DEFAULT_CASE_STATUS = "active";
export const DEFAULT_CASE_PAGE = 1;
export const CASE_PER_PAGE = 20;

const FILTER_KEYS = [
  "q",
  "severity",
  "case_type",
  "product_id",
  "assignee_id",
  "date_from",
  "date_to",
];

const PILL_STATUSES = [
  "Open",
  "In Progress",
  "On Hold",
  "Solution Found",
  "Closed",
];

export function buildCaseListParams(filters = {}) {
  const params = {};

  FILTER_KEYS.forEach((key) => {
    const value = filters[key];
    if (value === undefined || value === null) {
      return;
    }

    const normalized = String(value).trim();
    if (normalized) {
      params[key] = normalized;
    }
  });

  const status = filters.status || DEFAULT_CASE_STATUS;
  if (status !== DEFAULT_CASE_STATUS) {
    params.status = status;
  }

  const page = Number.parseInt(filters.page, 10);
  if (Number.isFinite(page) && page > DEFAULT_CASE_PAGE) {
    params.page = page;
  }

  return params;
}

export function hasActiveCaseFilters(filters = {}) {
  if ((filters.status || DEFAULT_CASE_STATUS) !== DEFAULT_CASE_STATUS) {
    return true;
  }

  return FILTER_KEYS.some((key) => {
    const value = filters[key];
    return (
      value !== undefined &&
      value !== null &&
      String(value).trim().length > 0
    );
  });
}

export function caseStatusKey(status) {
  return String(status || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "-");
}

export function caseSeverityKey(severity) {
  return String(severity || "")
    .trim()
    .toLowerCase();
}

export function caseStatusPills(statusCounts = {}) {
  const counts = statusCounts || {};

  return [
    {
      key: DEFAULT_CASE_STATUS,
      value: DEFAULT_CASE_STATUS,
      count: counts.active || 0,
    },
    ...PILL_STATUSES.map((status) => ({
      key: caseStatusKey(status),
      value: status,
      count: counts[status] || 0,
    })),
  ];
}

export function emptyCaseList() {
  return {
    cases: [],
    status_counts: { active: 0 },
    total_count: 0,
    page: DEFAULT_CASE_PAGE,
    per_page: CASE_PER_PAGE,
    total_pages: 1,
  };
}

export function caseListErrorMessage(error) {
  return error?.jqXHR?.responseJSON?.errors?.[0] || null;
}
