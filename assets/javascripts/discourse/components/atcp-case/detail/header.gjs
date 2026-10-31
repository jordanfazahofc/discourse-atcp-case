import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { next } from "@ember/runloop";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";
import AtcpCaseCloseModal from "../atcp-case-close-modal";
import AtcpCaseEditCaseModal from "../atcp-case-edit-case-modal";
import AtcpCaseReopenModal from "../atcp-case-reopen-modal";
import AtcpCaseSeverityBadge from "../atcp-case-severity-badge";
import AtcpCaseStatusBadge from "../atcp-case-status-badge";

const EDIT_BUTTON_ID = "atcp-case-edit-case";
const CLOSE_BUTTON_ID = "atcp-case-close-case";
const REOPEN_BUTTON_ID = "atcp-case-reopen-case";

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

  get canClose() {
    return this.args.atcpCase?.status !== "Closed";
  }

  get canReopen() {
    return this.args.atcpCase?.status === "Closed";
  }

  get hasActions() {
    return this.canEdit || this.canClose || this.canReopen;
  }

  get editButtonId() {
    return EDIT_BUTTON_ID;
  }

  get closeButtonId() {
    return CLOSE_BUTTON_ID;
  }

  get reopenButtonId() {
    return REOPEN_BUTTON_ID;
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

  @action
  closeCase() {
    this.modal.show(AtcpCaseCloseModal, {
      model: {
        atcpCase: this.args.atcpCase,
        formOptions: this.args.formOptions,
        onSaved: this.caseClosed,
      },
    });
  }

  @action
  reopenCase() {
    this.modal.show(AtcpCaseReopenModal, {
      model: {
        atcpCase: this.args.atcpCase,
        onSaved: this.caseReopened,
      },
    });
  }

  @action
  async caseClosed() {
    await this.router.refresh();
    this.a11y.announce(
      i18n("atcp_case.cases.detail.close_case.saved_announcement"),
      "polite"
    );
    this.#focusButton(this.reopenButtonId);
  }

  @action
  async caseReopened() {
    await this.router.refresh();
    this.a11y.announce(
      i18n("atcp_case.cases.detail.reopen_case.saved_announcement"),
      "polite"
    );
    this.#focusButton(this.closeButtonId);
  }

  #focusEditButton() {
    this.#focusButton(this.editButtonId);
  }

  #focusButton(id) {
    next(() => {
      document.getElementById(id)?.focus();
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

        {{#if this.hasActions}}
          <div class="atcp-case-detail__actions">
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

            {{#if this.canClose}}
              <button
                id={{this.closeButtonId}}
                type="button"
                class="btn btn-default btn-small atcp-case-detail__close"
                {{on "click" this.closeCase}}
              >
                {{i18n "atcp_case.cases.detail.close_case.button"}}
              </button>
            {{/if}}

            {{#if this.canReopen}}
              <button
                id={{this.reopenButtonId}}
                type="button"
                class="btn btn-default btn-small atcp-case-detail__reopen"
                {{on "click" this.reopenCase}}
              >
                {{i18n "atcp_case.cases.detail.reopen_case.button"}}
              </button>
            {{/if}}
          </div>
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
