import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import {
  buildCaseListParams,
  CASE_PER_PAGE,
  caseListErrorMessage,
  emptyCaseList,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-list-params";
import AtcpCaseRoute from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-route";

export default class AtcpCasesIndexRoute extends AtcpCaseRoute {
  @service router;
  @service currentUser;

  queryParams = {
    status: { refreshModel: true },
    q: { refreshModel: true },
    severity: { refreshModel: true },
    case_type: { refreshModel: true },
    product_id: { refreshModel: true },
    assignee_id: { refreshModel: true },
    date_from: { refreshModel: true },
    date_to: { refreshModel: true },
    page: { refreshModel: true },
  };

  beforeModel() {
    if (!this.currentUser?.atcp_internal_access) {
      this.router.replaceWith("/");
    }
  }

  @action
  loading(transition) {
    if (
      transition.from?.name !== "atcp-cases.index" ||
      transition.to?.name !== "atcp-cases.index"
    ) {
      return;
    }

    // Jangan masuk loading substate saat refresh query param: daftar dan
    // input pencarian harus tetap terpasang.
    return false;
  }

  async model(params) {
    const listParams = {
      ...buildCaseListParams(params),
      per_page: CASE_PER_PAGE,
    };
    const controller = this.controllerFor("atcp-cases.index");
    controller.isLoading = true;

    try {
      const [list, formOptions, picGroups] = await Promise.all([
        this._fetchList(listParams),
        this._fetchOnce("_formOptionsPromise", "/atcp/cases/form_options.json", {}),
        this._fetchOnce("_picGroupsPromise", "/atcp/cases/pic_candidates.json", {
          groups: [],
        }),
      ]);

      return { list: list.data, error: list.error, formOptions, picGroups };
    } finally {
      controller.isLoading = false;
    }
  }

  async _fetchList(params) {
    try {
      const data = await ajax("/atcp/cases.json", { data: params });
      return { data, error: null };
    } catch (error) {
      if (error?.jqXHR?.status === 422) {
        return { data: emptyCaseList(), error: caseListErrorMessage(error) };
      }

      popupAjaxError(error);
      return { data: emptyCaseList(), error: null };
    }
  }

  _fetchOnce(property, url, fallback) {
    if (!this[property]) {
      const request = ajax(url).catch((error) => {
        popupAjaxError(error);
        if (this[property] === request) {
          delete this[property];
        }
        return fallback;
      });

      this[property] = request;
    }

    return this[property];
  }
}
