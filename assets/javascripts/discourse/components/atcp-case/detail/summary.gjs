import Component from "@glimmer/component";
import { i18n } from "discourse-i18n";
import {
  caseProductLabel,
  caseReporterLabel,
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
    const products = this.args.atcpCase?.products || [];

    if (!products.length) {
      return [
        { key: "none", label: i18n("atcp_case.cases.detail.summary.no_product") },
      ];
    }

    return products.map((product, index) => ({
      key: product.id ?? `snapshot-${index}`,
      label: caseProductLabel(product),
    }));
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
    return caseReporterLabel(this.args.atcpCase);
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
            {{#each this.products as |product|}}
              <span class="atcp-case-detail__product" data-product-key={{product.key}}>
                {{product.label}}
              </span>
            {{/each}}
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
