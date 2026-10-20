import Component from "@glimmer/component";
import { fn, hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { cancel, later } from "@ember/runloop";
import ComboBox from "discourse/select-kit/components/combo-box";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DConditionalLoadingSpinner from "discourse/ui-kit/d-conditional-loading-spinner";
import DDateInput from "discourse/ui-kit/d-date-input";
import { i18n } from "discourse-i18n";
import {
  caseSeverityKey,
  caseStatusPills,
  hasActiveCaseFilters,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-list-params";
import AtcpCaseProductFilter from "./atcp-case-product-filter";
import AtcpCaseSeverityBadge from "./atcp-case-severity-badge";
import AtcpCaseStatusBadge from "./atcp-case-status-badge";

const SEARCH_DEBOUNCE_MS = 300;

export default class AtcpCaseList extends Component {
  willDestroy(...args) {
    cancel(this._searchTimer);
    super.willDestroy(...args);
  }

  get cases() {
    return this.args.list?.cases || [];
  }

  get totalCount() {
    return this.args.list?.total_count || 0;
  }

  get currentPage() {
    return Number.parseInt(this.args.list?.page, 10) || 1;
  }

  get totalPages() {
    return Math.max(Number.parseInt(this.args.list?.total_pages, 10) || 1, 1);
  }

  get isFirstPage() {
    return this.currentPage <= 1;
  }

  get isLastPage() {
    return this.currentPage >= this.totalPages;
  }

  get isEmpty() {
    return this.cases.length === 0;
  }

  get hasFilters() {
    return hasActiveCaseFilters(this.args.filters);
  }

  get statusPills() {
    return caseStatusPills(this.args.list?.status_counts).map((pill) => ({
      ...pill,
      label: i18n(`atcp_case.cases.statuses.${pill.key}`),
    }));
  }

  get severityOptions() {
    return (this.args.formOptions?.severities || []).map((severity) => ({
      id: severity,
      name: i18n(`atcp_case.cases.severities.${caseSeverityKey(severity)}`),
    }));
  }

  get caseTypeOptions() {
    return (this.args.formOptions?.case_types || []).map((caseType) => ({
      id: caseType,
      name: caseType,
    }));
  }

  get assigneeOptions() {
    const seen = new Set();
    const options = [];

    (this.args.picGroups?.groups || []).forEach((group) => {
      (group.users || []).forEach((user) => {
        const id = String(user.id);
        if (seen.has(id)) {
          return;
        }

        seen.add(id);
        options.push({ id, name: user.name || user.username });
      });
    });

    const assigneeId = this.args.filters?.assignee_id;
    if (assigneeId && !seen.has(String(assigneeId))) {
      options.push({
        id: String(assigneeId),
        name: i18n("atcp_case.cases.filters.unknown_pic", { id: assigneeId }),
      });
    }

    return options;
  }

  @action
  changeStatus(status) {
    this.args.onStatusChange?.(status);
  }

  @action
  changeFilter(name, value) {
    this.args.onFilterChange?.(name, value);
  }

  @action
  changeDate(name, value) {
    this.args.onDateChange?.(name, value ? value.format("YYYY-MM-DD") : null);
  }

  @action
  clearFilters() {
    this.args.onClearFilters?.();
  }

  @action
  previousPage() {
    this.args.onPageChange?.(this.currentPage - 1);
  }

  @action
  nextPage() {
    this.args.onPageChange?.(this.currentPage + 1);
  }

  @action
  openCase(id, event) {
    if (event?.target?.closest?.("a")) {
      return;
    }

    this.args.onOpenCase?.(id);
  }

  @action
  openCaseLink(id, event) {
    if (
      event.ctrlKey ||
      event.metaKey ||
      event.shiftKey ||
      event.button !== 0
    ) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    this.args.onOpenCase?.(id);
  }

  @action
  onSearchInput(event) {
    const value = event.target.value;
    cancel(this._searchTimer);
    this._searchTimer = later(
      this,
      () => this._commitSearch(value),
      SEARCH_DEBOUNCE_MS
    );
  }

  @action
  onSearchKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      cancel(this._searchTimer);
      this._commitSearch(event.target.value);
    }
  }

  caseHref(id) {
    return `/internal/cases/${id}`;
  }

  productsLabel(products) {
    if (!products?.length) {
      return "-";
    }

    const [first, ...rest] = products;
    return rest.length ? `${first.name} +${rest.length}` : first.name;
  }

  productsTitle(products) {
    if (!products?.length) {
      return "-";
    }

    return products.map((product) => product.name).join(", ");
  }

  assigneeLabel(assignee) {
    return assignee?.name || assignee?.username || "-";
  }

  waitingLabel(waiting) {
    return i18n("atcp_case.cases.waiting", {
      label: waiting.label,
      days: waiting.days,
    });
  }

  _commitSearch(value) {
    this.args.onSearch?.(value.trim());
  }

  <template>
    <div class="atcp-case-list {{if @isLoading 'atcp-case-list--loading'}}">
      <h1 class="atcp-case-list__title">{{i18n "atcp_case.cases.title"}}</h1>

      <div
        class="atcp-case-list__pills"
        role="group"
        aria-label={{i18n "atcp_case.cases.status_filter_label"}}
      >
        {{#each this.statusPills as |pill|}}
          <DButton
            class="atcp-case-list__pill
              {{if (eq pill.value @filters.status) 'atcp-case-list__pill--active'}}"
            @action={{fn this.changeStatus pill.value}}
            @ariaPressed={{eq pill.value @filters.status}}
          >
            <span class="atcp-case-list__pill-label">{{pill.label}}</span>
            <span class="atcp-case-list__pill-count">{{pill.count}}</span>
          </DButton>
        {{/each}}
      </div>

      <div class="atcp-case-list__filters">
        <div class="atcp-case-list__filter atcp-case-list__filter--search">
          <label class="atcp-case-list__label" for="atcp-case-search">
            {{i18n "atcp_case.cases.search_label"}}
          </label>
          <input
            id="atcp-case-search"
            type="text"
            class="atcp-case-list__search no-blur"
            value={{@filters.q}}
            placeholder={{i18n "atcp_case.cases.search_placeholder"}}
            {{on "input" this.onSearchInput}}
            {{on "keydown" this.onSearchKeydown}}
          />
        </div>

        <div class="atcp-case-list__filter">
          <label class="atcp-case-list__label">
            {{i18n "atcp_case.cases.filters.severity"}}
          </label>
          <ComboBox
            @value={{@filters.severity}}
            @content={{this.severityOptions}}
            @onChange={{fn this.changeFilter "severity"}}
            @options={{hash none="atcp_case.cases.filters.all_severities"}}
            class="atcp-case-list__severity"
          />
        </div>

        <div class="atcp-case-list__filter">
          <label class="atcp-case-list__label">
            {{i18n "atcp_case.cases.filters.case_type"}}
          </label>
          <ComboBox
            @value={{@filters.case_type}}
            @content={{this.caseTypeOptions}}
            @onChange={{fn this.changeFilter "case_type"}}
            @options={{hash none="atcp_case.cases.filters.all_types"}}
            class="atcp-case-list__type"
          />
        </div>

        <div class="atcp-case-list__filter">
          <label class="atcp-case-list__label">
            {{i18n "atcp_case.cases.filters.product"}}
          </label>
          <AtcpCaseProductFilter
            @value={{@filters.product_id}}
            @onChange={{fn this.changeFilter "product_id"}}
          />
        </div>

        <div class="atcp-case-list__filter">
          <label class="atcp-case-list__label">
            {{i18n "atcp_case.cases.filters.pic"}}
          </label>
          <ComboBox
            @value={{@filters.assignee_id}}
            @content={{this.assigneeOptions}}
            @onChange={{fn this.changeFilter "assignee_id"}}
            @options={{hash none="atcp_case.cases.filters.all_pics"}}
            class="atcp-case-list__pic"
          />
        </div>

        <div class="atcp-case-list__filter atcp-case-list__filter--date">
          <label class="atcp-case-list__label" for="atcp-case-date-from">
            {{i18n "atcp_case.cases.filters.date_from"}}
          </label>
          <DDateInput
            @date={{@filters.date_from}}
            @onChange={{fn this.changeDate "date_from"}}
            @inputId="atcp-case-date-from"
          />
        </div>

        <div class="atcp-case-list__filter atcp-case-list__filter--date">
          <label class="atcp-case-list__label" for="atcp-case-date-to">
            {{i18n "atcp_case.cases.filters.date_to"}}
          </label>
          <DDateInput
            @date={{@filters.date_to}}
            @onChange={{fn this.changeDate "date_to"}}
            @inputId="atcp-case-date-to"
          />
        </div>

        {{#if this.hasFilters}}
          <div class="atcp-case-list__filter atcp-case-list__filter--clear">
            <DButton
              @translatedLabel={{i18n "atcp_case.cases.clear_filters"}}
              class="btn-default atcp-case-list__clear"
              @action={{this.clearFilters}}
            />
          </div>
        {{/if}}
      </div>

      {{#if @error}}
        <div class="atcp-case-list__error" role="alert">{{@error}}</div>
      {{/if}}

      <p class="atcp-case-list__total">
        {{i18n "atcp_case.cases.total" count=this.totalCount}}
        <DConditionalLoadingSpinner
          @condition={{@isLoading}}
          @size="small"
          class="atcp-case-list__refreshing"
          role="status"
          aria-label={{i18n "atcp_case.cases.loading"}}
        />
      </p>

      {{#if this.isEmpty}}
        <div class="atcp-case-list__empty">
          {{#if this.hasFilters}}
            <p class="atcp-case-list__empty-text">
              {{i18n "atcp_case.cases.no_match"}}
            </p>
            <DButton
              @translatedLabel={{i18n "atcp_case.cases.clear_filters"}}
              class="btn-default atcp-case-list__clear"
              @action={{this.clearFilters}}
            />
          {{else}}
            <p class="atcp-case-list__empty-text">
              {{i18n "atcp_case.cases.empty"}}
            </p>
          {{/if}}
        </div>
      {{else}}
        <div class="atcp-case-list__table-wrap">
          <table class="grid atcp-case-list__table">
            <thead>
              <tr>
                <th>{{i18n "atcp_case.cases.columns.case_number"}}</th>
                <th>{{i18n "atcp_case.cases.columns.title"}}</th>
                <th>{{i18n "atcp_case.cases.columns.product"}}</th>
                <th>{{i18n "atcp_case.cases.columns.severity"}}</th>
                <th>{{i18n "atcp_case.cases.columns.status"}}</th>
                <th>{{i18n "atcp_case.cases.columns.pic"}}</th>
                <th>{{i18n "atcp_case.cases.columns.aging"}}</th>
              </tr>
            </thead>
            <tbody>
              {{#each this.cases as |caseItem|}}
                {{! eslint-disable ember/template-no-invalid-interactive }}
                <tr
                  class="atcp-case-list__row"
                  {{on "click" (fn this.openCase caseItem.id)}}
                >
                  <td class="atcp-case-list__case-number">
                    <a
                      class="atcp-case-list__link"
                      href={{this.caseHref caseItem.id}}
                      {{on "click" (fn this.openCaseLink caseItem.id)}}
                    >
                      {{caseItem.case_number}}
                    </a>
                  </td>
                  <td class="atcp-case-list__case-title">{{caseItem.title}}</td>
                  <td
                    class="atcp-case-list__products"
                    title={{this.productsTitle caseItem.products}}
                  >
                    <span class="atcp-case-list__truncate">
                      {{this.productsLabel caseItem.products}}
                    </span>
                  </td>
                  <td class="atcp-case-list__severity-cell">
                    <AtcpCaseSeverityBadge @severity={{caseItem.severity}} />
                  </td>
                  <td class="atcp-case-list__status-cell">
                    <AtcpCaseStatusBadge @status={{caseItem.status}} />
                    {{#if caseItem.waiting}}
                      <span class="atcp-case-list__waiting">
                        {{this.waitingLabel caseItem.waiting}}
                      </span>
                    {{/if}}
                  </td>
                  <td class="atcp-case-list__assignee">
                    <span class="atcp-case-list__truncate">
                      {{this.assigneeLabel caseItem.assignee}}
                    </span>
                  </td>
                  <td class="atcp-case-list__aging">
                    {{i18n
                      "atcp_case.cases.aging_days"
                      count=caseItem.aging_days
                    }}
                  </td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        </div>

        <nav
          class="atcp-case-list__pagination"
          aria-label={{i18n "atcp_case.cases.pagination.label"}}
        >
          <DButton
            @translatedLabel={{i18n "atcp_case.cases.pagination.previous"}}
            class="btn-default atcp-case-list__page-prev"
            @action={{this.previousPage}}
            @disabled={{this.isFirstPage}}
          />
          <span class="atcp-case-list__page-info">
            {{i18n
              "atcp_case.cases.pagination.page_of"
              page=this.currentPage
              total=this.totalPages
            }}
          </span>
          <DButton
            @translatedLabel={{i18n "atcp_case.cases.pagination.next"}}
            class="btn-default atcp-case-list__page-next"
            @action={{this.nextPage}}
            @disabled={{this.isLastPage}}
          />
        </nav>
      {{/if}}
    </div>
  </template>
}
