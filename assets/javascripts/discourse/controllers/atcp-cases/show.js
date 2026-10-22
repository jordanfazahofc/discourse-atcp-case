import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";
import {
  DEFAULT_CASE_DETAIL_TAB,
  normalizeCaseDetailTab,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-detail";

export default class AtcpCasesShowController extends Controller {
  @tracked tab = null;

  queryParams = ["tab"];

  @action
  selectTab(tab) {
    const normalized = normalizeCaseDetailTab(tab);
    this.tab = normalized === DEFAULT_CASE_DETAIL_TAB ? null : normalized;
  }

  resetTab() {
    this.tab = null;
  }
}
