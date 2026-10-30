import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { FALLBACK_ADD_UPDATE_FORM_OPTIONS } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-add-update";
import {
  DEFAULT_CASE_DETAIL_TAB,
  normalizeCaseDetailTab,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-detail";
import AtcpCaseRoute from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-route";

export default class AtcpCasesShowRoute extends AtcpCaseRoute {
  @service router;
  @service currentUser;

  async model(params) {
    const caseId = String(params.case_id);

    if (!/^\d+$/.test(caseId)) {
      return {
        case: null,
        error: "not_found",
        formOptions: FALLBACK_ADD_UPDATE_FORM_OPTIONS,
        picGroups: { groups: [] },
      };
    }

    this._resetTabOnSetup = Boolean(
      this._lastCaseId && this._lastCaseId !== caseId
    );
    this._lastCaseId = caseId;

    const [result, formOptions, picGroups] = await Promise.all([
      this._fetchCase(caseId),
      this._fetchOnce(
        "_formOptionsPromise",
        "/atcp/cases/form_options.json",
        FALLBACK_ADD_UPDATE_FORM_OPTIONS
      ),
      this._fetchOnce("_picGroupsPromise", "/atcp/cases/pic_candidates.json", {
        groups: [],
      }),
    ]);

    return { ...result, formOptions, picGroups };
  }

  async _fetchCase(caseId) {
    try {
      const result = await ajax(`/atcp/cases/${caseId}.json`);
      return { case: result.case, error: null };
    } catch (error) {
      if (error?.jqXHR?.status !== 404) {
        popupAjaxError(error);
      }

      return { case: null, error: "not_found" };
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

  setupController(controller, model) {
    super.setupController(controller, model);

    if (this._resetTabOnSetup) {
      this._resetTabOnSetup = false;
      controller.resetTab();
      return;
    }

    if (
      model.case?.id &&
      controller.tab &&
      normalizeCaseDetailTab(controller.tab) === DEFAULT_CASE_DETAIL_TAB
    ) {
      controller.resetTab();
      this.router.replaceWith("atcp-cases.show", model.case.id, {
        queryParams: { tab: null },
      });
    }
  }

  beforeModel() {
    if (!this.currentUser?.atcp_internal_access) {
      this.router.replaceWith("/");
    }
  }
}
