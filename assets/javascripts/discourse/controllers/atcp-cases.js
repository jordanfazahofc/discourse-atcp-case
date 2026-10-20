import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import {
  DEFAULT_CASE_PAGE,
  DEFAULT_CASE_STATUS,
  hasActiveCaseFilters,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-list-params";

const DEFAULT_FILTERS = {
  status: DEFAULT_CASE_STATUS,
  q: null,
  severity: null,
  case_type: null,
  product_id: null,
  assignee_id: null,
  date_from: null,
  date_to: null,
};

export default class AtcpCasesController extends Controller {
  @service router;

  @tracked status = DEFAULT_CASE_STATUS;
  @tracked q = null;
  @tracked severity = null;
  @tracked case_type = null;
  @tracked product_id = null;
  @tracked assignee_id = null;
  @tracked date_from = null;
  @tracked date_to = null;
  @tracked page = DEFAULT_CASE_PAGE;
  @tracked isLoading = false;

  get filters() {
    return {
      status: this.status,
      q: this.q,
      severity: this.severity,
      case_type: this.case_type,
      product_id: this.product_id,
      assignee_id: this.assignee_id,
      date_from: this.date_from,
      date_to: this.date_to,
    };
  }

  get hasFilters() {
    return hasActiveCaseFilters(this.filters);
  }

  @action
  setStatus(status) {
    this._updateQuery({ status, page: DEFAULT_CASE_PAGE });
  }

  @action
  search(value) {
    this._updateQuery({ q: value || null, page: DEFAULT_CASE_PAGE });
  }

  @action
  setFilter(name, value) {
    this._updateQuery({ [name]: value || null, page: DEFAULT_CASE_PAGE });
  }

  @action
  setPage(page) {
    this._updateQuery({ page });
  }

  @action
  clearFilters() {
    this._updateQuery({ ...DEFAULT_FILTERS, page: DEFAULT_CASE_PAGE });
  }

  @action
  openCase(id) {
    this.router.transitionTo("atcp-cases.show", id);
  }

  _updateQuery(params) {
    this.router.replaceWith({ queryParams: params });
  }
}
