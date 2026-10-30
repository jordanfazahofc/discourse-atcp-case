import { productLabel } from "./atcp-case-detail";

const TEXT_FIELDS = ["title", "case_type", "severity", "source"];

function normalize(value) {
  return String(value ?? "").trim();
}

function normalizeIds(value) {
  return (Array.isArray(value) ? value : [])
    .map((id) => String(id ?? "").trim())
    .filter(Boolean);
}

function sameIds(first, second) {
  const left = normalizeIds(first).sort();
  const right = normalizeIds(second).sort();

  return (
    left.length === right.length &&
    left.every((value, index) => value === right[index])
  );
}

function normalizeAssignee(value) {
  return String(value ?? "").trim();
}

export function hasLinkedProduct(product) {
  return product?.id !== null && product?.id !== undefined;
}

export function linkedCaseProducts(atcpCase) {
  return (atcpCase?.products || []).filter(hasLinkedProduct);
}

export function orphanCaseProducts(atcpCase) {
  return (atcpCase?.products || []).filter((product) => !hasLinkedProduct(product));
}

export function editCaseInitialData(atcpCase) {
  return {
    title: normalize(atcpCase?.title),
    case_type: atcpCase?.case_type || null,
    severity: atcpCase?.severity || null,
    source: normalize(atcpCase?.source),
    product_ids: linkedCaseProducts(atcpCase).map((product) =>
      String(product.id)
    ),
    assignee_id: atcpCase?.assignee?.id
      ? String(atcpCase.assignee.id)
      : null,
  };
}

export function editCaseProductItems(atcpCase) {
  return linkedCaseProducts(atcpCase).map((product) => ({
    id: String(product.id),
    name: productLabel(product.name, product.sku),
    sku: product.sku,
  }));
}

export function buildEditCasePayload({
  atcpCase,
  data,
  productsTouched = false,
}) {
  const payload = {};
  const initial = editCaseInitialData(atcpCase);

  TEXT_FIELDS.forEach((field) => {
    const nextValue = normalize(data?.[field]);
    if (nextValue !== initial[field]) {
      payload[field] = nextValue;
    }
  });

  if (productsTouched && !sameIds(data?.product_ids, initial.product_ids)) {
    payload.product_ids = normalizeIds(data?.product_ids);
  }

  const nextAssignee = normalizeAssignee(data?.assignee_id);
  if (nextAssignee !== normalizeAssignee(initial.assignee_id)) {
    payload.assignee_id = nextAssignee;
  }

  return payload;
}
