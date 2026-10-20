import { ajax } from "discourse/lib/ajax";
import ComboBox from "discourse/select-kit/components/combo-box";

export default class AtcpCaseProductChooser extends ComboBox {
  search(filter = "") {
    const term = String(filter || "").trim();

    if (!term) {
      return this.content || [];
    }

    return ajax("/atcp/products/search.json", { data: { q: term } })
      .then((result) =>
        (result.products || []).map((product) => ({
          id: String(product.id),
          name: product.name,
          sku: product.sku_code,
        }))
      )
      .catch(() => []);
  }
}
