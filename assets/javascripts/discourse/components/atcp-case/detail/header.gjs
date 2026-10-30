import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { next } from "@ember/runloop";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";
import AtcpCaseEditCaseModal from "../atcp-case-edit-case-modal";
import AtcpCaseSeverityBadge from "../atcp-case-severity-badge";
import AtcpCaseStatusBadge from "../atcp-case-status-badge";

const EDIT_BUTTON_ID = "atcp-case-edit-case";

export default class AtcpCaseDetailHeader extends Component {
  @service a11y;
  @service modal;
  @service router;

  get canEdit() {
    return Boolean(
      this.args.atcpCase?.can_manage &&
        this.args.atcpCase?.status !== "Closed"
    );
  }

  get editButtonId() {
    return EDIT_BUTTON_ID;
  }

  @action
  editCase() {
    this.modal.show(AtcpCaseEditCaseModal, {
      model: {
        atcpCase: this.args.atcpCase,
        formOptions: this.args.formOptions,
        picGroups: this.args.picGroups,
        onSaved: this.caseSaved,
        onNoLongerEditable: this.caseNoLongerEditable,
      },
    });
  }

  @action
  async caseSaved() {
    await this.router.refresh();
    this.a11y.announce(
      i18n("atcp_case.cases.detail.edit_case.saved_announcement"),
      "polite"
    );
    this.#focusEditButton();
  }

  @action
  async caseNoLongerEditable() {
    await this.router.refresh();
    this.a11y.announce(
      i18n("atcp_case.cases.detail.edit_case.no_longer_editable"),
      "polite"
    );
    this.#focusEditButton();
  }

  #focusEditButton() {
    next(() => {
      document.getElementById(this.editButtonId)?.focus();
    });
  }

  <template>
    <header class="atcp-case-detail__header">
      <div class="atcp-case-detail__top">
        <a
          href={{@returnURL}}
          class="atcp-case-detail__back"
          {{on "click" @onBack}}
        >
          <span aria-hidden="true">←</span>
          {{i18n "atcp_case.cases.detail.back_to_list"}}
        </a>

        {{#if this.canEdit}}
          <button
            id={{this.editButtonId}}
            type="button"
            class="btn btn-default btn-small atcp-case-detail__edit"
            {{on "click" this.editCase}}
          >
            {{i18n "atcp_case.cases.detail.edit_case.button"}}
          </button>
        {{/if}}
      </div>

      <h1 class="atcp-case-detail__title">
        {{@atcpCase.case_number}}
        ·
        {{@atcpCase.title}}
      </h1>

      <div class="atcp-case-detail__meta">
        <AtcpCaseSeverityBadge @severity={{@atcpCase.severity}} />
        <AtcpCaseStatusBadge @status={{@atcpCase.status}} />

        {{#if @atcpCase.case_type}}
          <span class="atcp-case-detail__type">{{@atcpCase.case_type}}</span>
        {{/if}}

        {{#if @atcpCase.waiting}}
          <span class="atcp-case-detail__waiting">
            {{i18n
              "atcp_case.cases.waiting"
              label=@atcpCase.waiting.label
              days=@atcpCase.waiting.days
            }}
          </span>
        {{/if}}
      </div>
    </header>
  </template>
}
