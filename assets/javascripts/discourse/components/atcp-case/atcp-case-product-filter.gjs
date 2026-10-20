import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import AtcpCaseProductChooser from "./atcp-case-product-chooser";

export default class AtcpCaseProductFilter extends Component {
  @tracked selectedProduct = null;

  constructor() {
    super(...arguments);

    if (this.args.value) {
      this._loadSelectedProduct(this.args.value);
    }
  }

  get content() {
    return this.selectedProduct ? [this.selectedProduct] : [];
  }

  @action
  onChange(value, item) {
    this.selectedProduct = value && item ? item : null;
    this.args.onChange?.(value || null);
  }

  async _loadSelectedProduct(id) {
    try {
      const result = await ajax(`/atcp/products/${id}.json`);
      const product = result.product;
      this.selectedProduct = {
        id: String(product.id),
        name: product.name,
        sku: product.sku_code,
      };
    } catch {
      this.selectedProduct = { id: String(id), name: String(id) };
    }
  }

  <template>
    <AtcpCaseProductChooser
      @value={{@value}}
      @content={{this.content}}
      @onChange={{this.onChange}}
      @options={{hash
        none="atcp_case.cases.filters.all_products"
        filterable=true
      }}
    />
  </template>
}
