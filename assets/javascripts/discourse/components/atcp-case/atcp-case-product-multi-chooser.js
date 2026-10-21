import { ajax } from "discourse/lib/ajax";
import MultiSelect from "discourse/select-kit/components/multi-select";

function productItem(product) {
  return {
    id: String(product.id),
    name: `${product.name} (${product.sku_code})`,
    sku: product.sku_code,
  };
}

export default class AtcpCaseProductMultiChooser extends MultiSelect {
  valueProperty = "id";

  search(filter = "") {
    const term = String(filter || "").trim();

    if (!term) {
      return [];
    }

    return ajax("/atcp/products/search.json", { data: { q: term } })
      .then((result) => (result.products || []).map(productItem))
      .then((items) => {
        const selectedIds = new Set(this.value || []);
        return items.filter((item) => !selectedIds.has(item.id));
      })
      .catch(() => []);
  }
}
