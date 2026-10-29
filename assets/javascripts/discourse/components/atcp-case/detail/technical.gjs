import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { next } from "@ember/runloop";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";
import AtcpCaseEditTechnicalModal from "../atcp-case-edit-technical-modal";

const NOT_PROVIDED_KEY = "atcp_case.cases.detail.technical.not_provided";
const EDIT_BUTTON_ID = "atcp-case-technical-edit";

export default class AtcpCaseDetailTechnical extends Component {
  @service a11y;
  @service modal;
  @service router;

  get fields() {
    return [
      ["symptom", "atcp_case.cases.detail.technical.symptom"],
      ["frequency", "atcp_case.cases.detail.technical.frequency"],
      ["reproducibility", "atcp_case.cases.detail.technical.reproducibility"],
      [
        "non_trigger_conditions",
        "atcp_case.cases.detail.technical.non_trigger_conditions",
      ],
      ["bios_version", "atcp_case.cases.detail.technical.bios_version"],
      ["os_driver_info", "atcp_case.cases.detail.technical.os_driver_info"],
    ].map(([field, translationKey]) => {
      const value = this.args.atcpCase?.[field]?.trim();

      return {
        field,
        label: i18n(translationKey),
        value,
        isEmpty: !value,
      };
    });
  }

  get notProvided() {
    return i18n(NOT_PROVIDED_KEY);
  }

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
  editTechnical() {
    this.modal.show(AtcpCaseEditTechnicalModal, {
      model: {
        atcpCase: this.args.atcpCase,
        formOptions: this.args.formOptions,
        onSaved: this.technicalSaved,
        onNoLongerEditable: this.technicalNoLongerEditable,
      },
    });
  }

  @action
  async technicalSaved() {
    await this.router.refresh();
    this.a11y.announce(
      i18n("atcp_case.cases.detail.technical.edit.saved_announcement"),
      "polite"
    );
    this.#focusEditButton();
  }

  @action
  async technicalNoLongerEditable() {
    await this.router.refresh();
    this.a11y.announce(
      i18n("atcp_case.cases.detail.technical.edit.no_longer_editable"),
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
    <section class="atcp-case-detail__technical">
      <div class="atcp-case-detail__technical-header">
        <h2
          class="atcp-case-detail__section-title atcp-case-detail__technical-title"
        >
          {{i18n "atcp_case.cases.detail.tabs.technical"}}
        </h2>

        {{#if this.canEdit}}
          <button
            id={{this.editButtonId}}
            type="button"
            class="btn btn-default btn-small atcp-case-detail__technical-edit"
            {{on "click" this.editTechnical}}
          >
            {{i18n "atcp_case.cases.detail.technical.edit.button"}}
          </button>
        {{/if}}
      </div>

      <dl class="atcp-case-detail__technical-list">
        {{#each this.fields as |field|}}
          <div class="atcp-case-detail__technical-item" data-field={{field.field}}>
            <dt>{{field.label}}</dt>
            <dd class={{if field.isEmpty "atcp-case-detail__muted"}}>
              {{#if field.isEmpty}}
                {{this.notProvided}}
              {{else}}
                <span class="atcp-case-detail__pre-wrap">{{field.value}}</span>
              {{/if}}
            </dd>
          </div>
        {{/each}}
      </dl>
    </section>
  </template>
}
