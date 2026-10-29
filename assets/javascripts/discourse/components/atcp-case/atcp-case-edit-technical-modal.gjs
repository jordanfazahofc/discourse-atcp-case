import Component from "@glimmer/component";
import { cached, tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import Form from "discourse/components/form";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { eq, not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";
import {
  buildEditTechnicalPayload,
  TECHNICAL_FIELDS,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-edit-technical";
import { normalizeCaseErrors } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-errors";

const FORM_FIELDS = new Set(TECHNICAL_FIELDS);

const FIELD_TITLE_KEYS = {
  symptom: "atcp_case.cases.detail.technical.symptom",
  frequency: "atcp_case.cases.detail.technical.frequency",
  reproducibility: "atcp_case.cases.detail.technical.reproducibility",
  non_trigger_conditions:
    "atcp_case.cases.detail.technical.non_trigger_conditions",
  bios_version: "atcp_case.cases.detail.technical.bios_version",
  os_driver_info: "atcp_case.cases.detail.technical.os_driver_info",
};

function initialTechnicalData(atcpCase) {
  return Object.fromEntries(
    TECHNICAL_FIELDS.map((field) => [
      field,
      String(atcpCase?.[field] ?? "").trim(),
    ])
  );
}

export default class AtcpCaseEditTechnicalModal extends Component {
  @service dialog;
  @service router;

  @tracked draft;
  @tracked formApi;
  @tracked isSubmitting = false;
  @tracked serverErrors = [];

  constructor(owner, args) {
    super(owner, args);

    this.draft = initialTechnicalData(args.model?.atcpCase);
  }

  @cached
  get initialData() {
    return initialTechnicalData(this.args.model?.atcpCase);
  }

  get frequencyOptions() {
    return this.args.model?.formOptions?.frequencies || [];
  }

  get reproducibilityOptions() {
    return this.args.model?.formOptions?.reproducibilities || [];
  }

  get hasChanges() {
    return (
      Object.keys(
        buildEditTechnicalPayload({
          atcpCase: this.args.model?.atcpCase,
          data: this.draft,
        })
      ).length > 0
    );
  }

  @action
  registerApi(api) {
    this.formApi = api;
  }

  @action
  submitForm() {
    this.formApi?.submit();
  }

  @action
  onSet(name, value) {
    this.draft = { ...this.draft, [name]: value };
    this.serverErrors = [];
    this.formApi?.removeError(name);
  }

  @action
  async updateSelect(field, event) {
    await field.set(event.target.value ?? "");
  }

  @action
  async onSubmit(data) {
    if (this.isSubmitting) {
      return;
    }

    const payload = buildEditTechnicalPayload({
      atcpCase: this.args.model?.atcpCase,
      data,
    });

    if (!Object.keys(payload).length) {
      this.args.closeModal();
      return;
    }

    this.formApi?.removeErrors();
    this.serverErrors = [];
    this.isSubmitting = true;

    try {
      await ajax(`/atcp/cases/${this.args.model?.atcpCase?.id}.json`, {
        type: "PUT",
        data: payload,
      });

      this.args.closeModal();
      this.args.model?.onSaved?.();
    } catch (error) {
      const status = error?.jqXHR?.status;

      if (status === 403) {
        this.args.closeModal();
        this.args.model?.onNoLongerEditable?.();
      } else if (status === 422) {
        await this.applyServerErrors(error.jqXHR.responseJSON);
      } else {
        popupAjaxError(error);
      }
    } finally {
      this.isSubmitting = false;
    }
  }

  @action
  async cancel() {
    if (!this.hasChanges) {
      this.args.closeModal();
      return;
    }

    const discard = await this.dialog.confirm({
      message: i18n(
        "atcp_case.cases.detail.technical.edit.discard_confirmation"
      ),
      confirmButtonLabel: "atcp_case.cases.detail.technical.edit.discard",
      cancelButtonLabel: "atcp_case.cases.detail.technical.edit.keep_editing",
    });

    if (discard) {
      this.args.closeModal();
    }
  }

  @action
  async beforeClose() {
    if (!this.hasChanges) {
      return true;
    }

    return this.dialog.confirm({
      message: i18n(
        "atcp_case.cases.detail.technical.edit.discard_confirmation"
      ),
      confirmButtonLabel: "atcp_case.cases.detail.technical.edit.discard",
      cancelButtonLabel: "atcp_case.cases.detail.technical.edit.keep_editing",
    });
  }

  async applyServerErrors(payload) {
    const { fieldErrors, baseErrors } = normalizeCaseErrors(payload);
    const messages = [...baseErrors];
    let refresh = false;

    Object.entries(fieldErrors).forEach(([field, fieldMessages]) => {
      if (FORM_FIELDS.has(field)) {
        fieldMessages.forEach((message) => {
          this.formApi?.addError(field, {
            title: this.fieldTitle(field),
            message,
          });
        });
        return;
      }

      fieldMessages.forEach((message) => {
        messages.push(`${this.humanizeField(field)}: ${message}`);
      });
    });

    baseErrors.forEach((message) => {
      if (/closed/i.test(message)) {
        refresh = true;
      }
    });

    this.serverErrors = messages;

    if (refresh) {
      await this.router.refresh();
    }
  }

  fieldTitle(field) {
    return i18n(FIELD_TITLE_KEYS[field]);
  }

  humanizeField(field) {
    const label = String(field).replaceAll("_", " ");
    return label.charAt(0).toUpperCase() + label.slice(1);
  }

  <template>
    <DModal
      @title={{i18n "atcp_case.cases.detail.technical.edit.title"}}
      @closeModal={{@closeModal}}
      @beforeClose={{this.beforeClose}}
      class="atcp-case-edit-technical-modal"
    >
      <:body>
        {{#if this.serverErrors.length}}
          <div
            class="alert alert-error atcp-case-edit-technical-modal__errors"
            role="alert"
          >
            <p class="atcp-case-edit-technical-modal__errors-title">
              {{i18n "atcp_case.cases.detail.technical.edit.errors_title"}}
            </p>
            <ul class="atcp-case-edit-technical-modal__errors-list">
              {{#each this.serverErrors as |message|}}
                <li>{{message}}</li>
              {{/each}}
            </ul>
          </div>
        {{/if}}

        <Form
          @data={{this.initialData}}
          @onSubmit={{this.onSubmit}}
          @onRegisterApi={{this.registerApi}}
          @onSet={{this.onSet}}
          as |form|
        >
          <form.Field
            @name="symptom"
            @title={{i18n "atcp_case.cases.detail.technical.symptom"}}
            @type="textarea"
            @format="full"
            @validation="required:trim"
            as |field|
          >
            <field.Control rows="5" autofocus />
          </form.Field>

          <form.Row as |row|>
            <row.Col @size={{6}}>
              <form.Field
                @name="frequency"
                @title={{i18n "atcp_case.cases.detail.technical.frequency"}}
                @type="custom"
                as |field|
              >
                <field.Control>
                  <select
                    id={{field.id}}
                    name={{field.name}}
                    class="atcp-case-edit-technical-modal__select"
                    value={{field.value}}
                    aria-describedby={{field.describedBy}}
                    aria-invalid={{if field.error "true"}}
                    {{on "change" (fn this.updateSelect field)}}
                  >
                    <option value="" selected={{not field.value}}>
                      {{i18n "atcp_case.cases.detail.technical.edit.not_set"}}
                    </option>
                    {{#each this.frequencyOptions as |frequencyOption|}}
                      <option
                        value={{frequencyOption}}
                        selected={{eq field.value frequencyOption}}
                      >
                        {{frequencyOption}}
                      </option>
                    {{/each}}
                  </select>
                </field.Control>
              </form.Field>
            </row.Col>

            <row.Col @size={{6}}>
              <form.Field
                @name="reproducibility"
                @title={{i18n
                  "atcp_case.cases.detail.technical.reproducibility"
                }}
                @type="custom"
                as |field|
              >
                <field.Control>
                  <select
                    id={{field.id}}
                    name={{field.name}}
                    class="atcp-case-edit-technical-modal__select"
                    value={{field.value}}
                    aria-describedby={{field.describedBy}}
                    aria-invalid={{if field.error "true"}}
                    {{on "change" (fn this.updateSelect field)}}
                  >
                    <option value="" selected={{not field.value}}>
                      {{i18n "atcp_case.cases.detail.technical.edit.not_set"}}
                    </option>
                    {{#each this.reproducibilityOptions as |reproducibilityOption|}}
                      <option
                        value={{reproducibilityOption}}
                        selected={{eq field.value reproducibilityOption}}
                      >
                        {{reproducibilityOption}}
                      </option>
                    {{/each}}
                  </select>
                </field.Control>
              </form.Field>
            </row.Col>
          </form.Row>

          <form.Field
            @name="non_trigger_conditions"
            @title={{i18n
              "atcp_case.cases.detail.technical.non_trigger_conditions"
            }}
            @type="textarea"
            @format="full"
            as |field|
          >
            <field.Control rows="5" />
          </form.Field>

          <form.Field
            @name="bios_version"
            @title={{i18n "atcp_case.cases.detail.technical.bios_version"}}
            @type="input"
            @format="full"
            as |field|
          >
            <field.Control maxlength="255" autocomplete="off" />
          </form.Field>

          <form.Field
            @name="os_driver_info"
            @title={{i18n "atcp_case.cases.detail.technical.os_driver_info"}}
            @type="textarea"
            @format="full"
            as |field|
          >
            <field.Control rows="5" />
          </form.Field>
        </Form>
      </:body>

      <:footer>
        <DButton
          @translatedLabel={{i18n
            "atcp_case.cases.detail.technical.edit.cancel"
          }}
          class="btn-default atcp-case-edit-technical-modal__cancel"
          @action={{this.cancel}}
          @disabled={{this.isSubmitting}}
        />
        <DButton
          @translatedLabel={{i18n "atcp_case.cases.detail.technical.edit.save"}}
          class="btn-primary atcp-case-edit-technical-modal__save"
          @action={{this.submitForm}}
          @disabled={{this.isSubmitting}}
          @isLoading={{this.isSubmitting}}
        />
      </:footer>
    </DModal>
  </template>
}
