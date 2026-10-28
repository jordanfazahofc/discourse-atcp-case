import Component from "@glimmer/component";
import { i18n } from "discourse-i18n";
import {
  caseProductLabel,
  displayUserName,
  formatCaseDate,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-detail";

export default class AtcpCaseDetailSummary extends Component {
  get pic() {
    const name = displayUserName(this.args.atcpCase?.assignee);

    return name === "-"
      ? i18n("atcp_case.cases.detail.summary.unassigned")
      : name;
  }

  get products() {
    return (this.args.atcpCase?.products || []).map((product, index) => ({
      key: product.id ?? `snapshot-${index}`,
      label: caseProductLabel(product),
    }));
  }

  get hasProducts() {
    return this.products.length > 0;
  }

  get source() {
    return this.args.atcpCase?.source || "-";
  }

  get openedAt() {
    return formatCaseDate(this.args.atcpCase?.opened_at);
  }

  get aging() {
    const days = this.args.atcpCase?.aging_days;

    return Number.isFinite(days)
      ? i18n("atcp_case.cases.aging_days", { count: days })
      : "-";
  }

  get reporter() {
    return displayUserName(this.args.atcpCase?.created_by);
  }

  get isClosed() {
    return this.args.atcpCase?.status === "Closed";
  }

  get closedAt() {
    return formatCaseDate(this.args.atcpCase?.closed_at);
  }

  get closeReason() {
    return this.args.atcpCase?.close_reason || "-";
  }

  <template>
    <section class="atcp-case-detail__summary">
      <h2 class="atcp-case-detail__section-title">
        {{i18n "atcp_case.cases.detail.summary.title"}}
      </h2>

      <dl class="atcp-case-detail__summary-grid">
        <div class="atcp-case-detail__summary-item"
          data-field="pic"
        >
          <dt>{{i18n "atcp_case.cases.detail.summary.pic"}}</dt>
          <dd>{{this.pic}}</dd>
        </div>

        <div class="atcp-case-detail__summary-item"
          data-field="product"
        >
          <dt>{{i18n "atcp_case.cases.detail.summary.product"}}</dt>
          <dd>
            {{#if this.hasProducts}}
              <ul class="atcp-case-detail__product-list">
                {{#each this.products as |product|}}
                  <li
                    class="atcp-case-detail__product"
                    data-product-key={{product.key}}
                  >
                    {{product.label}}
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <span class="atcp-case-detail__no-product">
                {{i18n "atcp_case.cases.detail.summary.no_product"}}
              </span>
            {{/if}}
          </dd>
        </div>

        <div class="atcp-case-detail__summary-item"
          data-field="opened"
        >
          <dt>{{i18n "atcp_case.cases.detail.summary.opened"}}</dt>
          <dd>{{this.openedAt}}</dd>
        </div>

        <div class="atcp-case-detail__summary-item"
          data-field="aging"
        >
          <dt>{{i18n "atcp_case.cases.detail.summary.aging"}}</dt>
          <dd>{{this.aging}}</dd>
        </div>

        <div class="atcp-case-detail__summary-item"
          data-field="source"
        >
          <dt>{{i18n "atcp_case.cases.detail.summary.source"}}</dt>
          <dd>{{this.source}}</dd>
        </div>

        <div class="atcp-case-detail__summary-item"
          data-field="reporter"
        >
          <dt>{{i18n "atcp_case.cases.detail.summary.reporter"}}</dt>
          <dd>{{this.reporter}}</dd>
        </div>

        {{#if this.isClosed}}
          <div class="atcp-case-detail__summary-item"
            data-field="closed"
          >
            <dt>{{i18n "atcp_case.cases.detail.summary.closed"}}</dt>
            <dd>{{this.closedAt}}</dd>
          </div>

          <div class="atcp-case-detail__summary-item"
            data-field="close_reason"
          >
            <dt>{{i18n "atcp_case.cases.detail.summary.close_reason"}}</dt>
            <dd>{{this.closeReason}}</dd>
          </div>
        {{/if}}
      </dl>
    </section>
  </template>
}
