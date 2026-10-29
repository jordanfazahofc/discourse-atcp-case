import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import {
  collectCaseAttachments,
  hasResolutionContent,
  normalizeCaseDetailTab,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-detail";
import AtcpCaseDetailAttachments from "./attachments";
import AtcpCaseDetailHeader from "./header";
import AtcpCaseDetailNotFound from "./not-found";
import AtcpCaseDetailProgress from "./progress";
import AtcpCaseDetailResolution from "./resolution";
import AtcpCaseDetailSummary from "./summary";
import AtcpCaseDetailTabs from "./tabs";
import AtcpCaseDetailTechnical from "./technical";

export default class AtcpCaseDetail extends Component {
  @service atcpCaseReturnUrl;
  @service router;

  get activeTab() {
    return normalizeCaseDetailTab(this.args.activeTab);
  }

  get attachments() {
    return collectCaseAttachments(this.args.atcpCase?.updates);
  }

  get tabs() {
    return [
      {
        key: "progress",
        label: i18n("atcp_case.cases.detail.tabs.progress"),
      },
      {
        key: "technical",
        label: i18n("atcp_case.cases.detail.tabs.technical"),
      },
      {
        key: "attachments",
        label: i18n("atcp_case.cases.detail.tabs.attachments", {
          count: this.attachments.length,
        }),
      },
    ];
  }

  get showResolution() {
    return hasResolutionContent(this.args.atcpCase);
  }

  @action
  backToList(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) {
      return;
    }

    event.preventDefault();
    this.router.transitionTo(this.atcpCaseReturnUrl.url);
  }

  @action
  selectTab(tab) {
    this.args.onSelectTab?.(normalizeCaseDetailTab(tab));
  }

  <template>
    <div class="atcp-case-detail">
      {{#if @error}}
        <AtcpCaseDetailNotFound
          @returnURL={{this.atcpCaseReturnUrl.url}}
          @onBack={{this.backToList}}
        />
      {{else}}
        <AtcpCaseDetailHeader
          @atcpCase={{@atcpCase}}
          @returnURL={{this.atcpCaseReturnUrl.url}}
          @onBack={{this.backToList}}
        />

        <AtcpCaseDetailSummary @atcpCase={{@atcpCase}} />

        {{#if this.showResolution}}
          <AtcpCaseDetailResolution @atcpCase={{@atcpCase}} />
        {{/if}}

        <AtcpCaseDetailTabs
          @tabs={{this.tabs}}
          @activeTab={{this.activeTab}}
          @onSelect={{this.selectTab}}
        />

        <div
          id="atcp-case-detail-panel-{{this.activeTab}}"
          class="atcp-case-detail__panel"
          role="tabpanel"
          aria-labelledby="atcp-case-detail-tab-{{this.activeTab}}"
          tabindex="0"
        >
          {{#if (eq this.activeTab "progress")}}
            <AtcpCaseDetailProgress
              @atcpCase={{@atcpCase}}
              @updates={{@atcpCase.updates}}
              @formOptions={{@formOptions}}
            />
          {{else if (eq this.activeTab "technical")}}
            <AtcpCaseDetailTechnical
              @atcpCase={{@atcpCase}}
              @formOptions={{@formOptions}}
            />
          {{else}}
            <AtcpCaseDetailAttachments
              @attachments={{this.attachments}}
              @onViewUpdate={{fn this.selectTab "progress"}}
            />
          {{/if}}
        </div>
      {{/if}}
    </div>
  </template>
}
