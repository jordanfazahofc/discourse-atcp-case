import Component from "@glimmer/component";
import { cached, tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import Form from "discourse/components/form";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";
import {
  buildCloseCasePayload,
  closeInitialData,
  closeReasonOptions,
  hasCloseCaseChanges,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-close-reopen";
import { normalizeCaseErrors } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-errors";

const FORM_FIELDS = new Set([
  "close_reason",
  "solution",
  "root_cause_summary",
  "workaround",
  "conclusion",
]);

const FIELD_TITLE_KEYS = {
  close_reason: "atcp_case.cases.detail.close_case.fields.close_reason",
  solution: "atcp_case.cases.detail.close_case.fields.solution",
  root_cause_summary:
    "atcp_case.cases.detail.close_case.fields.root_cause_summary",
  workaround: "atcp_case.cases.detail.close_case.fields.workaround",
  conclusion: "atcp_case.cases.detail.close_case.fields.conclusion",
};

function humanizeField(field) {
  const label = String(field).replaceAll("_", " ");
  return label.charAt(0).toUpperCase() + label.slice(1);
}

export default class AtcpCaseCloseModal extends Component {
  @service dialog;
  @service router;

  @tracked draft;
  @tracked formApi;
  @tracked isSubmitting = false;
  @tracked serverErrors = [];

  constructor(owner, args) {
    super(owner, args);

    this.draft = closeInitialData(args.model?.atcpCase);
  }

  @cached
  get initialData() {
    return closeInitialData(this.args.model?.atcpCase);
  }

  get closeReasons() {
    return closeReasonOptions(this.args.model?.formOptions?.close_reasons);
  }

  get solutionRequired() {
    return this.draft.close_reason === "Resolved";
  }

  get hasChanges() {
    return hasCloseCaseChanges({
      atcpCase: this.args.model?.atcpCase,
      data: this.draft,
    });
  }

  @action
  registerApi(api) {
    this.formApi = api;
  }

  @action
  onSet(name, value) {
    this.draft = { ...this.draft, [name]: value };
    this.serverErrors = [];
    this.formApi?.removeError(name);
  }

  @action
  submitForm() {
    this.formApi?.submit();
  }

  @action
  validate(data, { addError, removeError }) {
    removeError("solution");

    if (
      data.close_reason === "Resolved" &&
      !String(data.solution || "").trim()
    ) {
      addError("solution", {
        title: this.fieldTitle("solution"),
        message: i18n("atcp_case.cases.detail.close_case.validation.solution_required"),
      });
    }
  }

  @action
  async onSubmit(data) {
    if (this.isSubmitting) {
      return;
    }

    this.formApi?.removeErrors();
    this.serverErrors = [];
    this.isSubmitting = true;

    try {
      await ajax(`/atcp/cases/${this.args.model?.atcpCase?.id}/close.json`, {
        type: "POST",
        data: buildCloseCasePayload({
          atcpCase: this.args.model?.atcpCase,
          data,
        }),
      });

      this.args.closeModal();
      this.args.model?.onSaved?.();
    } catch (error) {
      const status = error?.jqXHR?.status;

      if (status === 403 || status === 404) {
        this.args.closeModal();
        await this.router.refresh();
      } else if (status === 422) {
        const hasBaseErrors = this.applyServerErrors(
          error.jqXHR.responseJSON
        );
        if (hasBaseErrors) {
          await this.router.refresh();
        }
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
      message: i18n("atcp_case.cases.detail.close_case.discard_confirmation"),
      confirmButtonLabel: "atcp_case.cases.detail.close_case.discard",
      cancelButtonLabel: "atcp_case.cases.detail.close_case.keep_editing",
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
      message: i18n("atcp_case.cases.detail.close_case.discard_confirmation"),
      confirmButtonLabel: "atcp_case.cases.detail.close_case.discard",
      cancelButtonLabel: "atcp_case.cases.detail.close_case.keep_editing",
    });
  }

  applyServerErrors(payload) {
    const { fieldErrors, baseErrors } = normalizeCaseErrors(payload);
    const messages = [...baseErrors];

    Object.entries(fieldErrors).forEach(([field, fieldMessages]) => {
      if (FORM_FIELDS.has(field)) {
        fieldMessages.forEach((message) => {
          this.formApi?.addError(field, {
            title: this.fieldTitle(field),
            message,
          });
        });
      } else {
        fieldMessages.forEach((message) => {
          messages.push(`${humanizeField(field)}: ${message}`);
        });
      }
    });

    this.serverErrors = messages;
    return baseErrors.length > 0;
  }

  fieldTitle(field) {
    return i18n(FIELD_TITLE_KEYS[field]);
  }

  <template>
    <DModal
      @title={{i18n "atcp_case.cases.detail.close_case.title"}}
      @closeModal={{@closeModal}}
      @beforeClose={{this.beforeClose}}
      class="atcp-case-close-modal"
    >
      <:body>
        {{#if this.serverErrors.length}}
          <div
            class="alert alert-error atcp-case-close-modal__errors"
            role="alert"
          >
            <p class="atcp-case-close-modal__errors-title">
              {{i18n "atcp_case.cases.detail.close_case.errors_title"}}
            </p>
            <ul class="atcp-case-close-modal__errors-list">
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
          @validate={{this.validate}}
          as |form|
        >
          <form.Field
            @name="close_reason"
            @title={{i18n "atcp_case.cases.detail.close_case.fields.close_reason"}}
            @type="select"
            @format="full"
            @validation="required"
            as |field|
          >
            <field.Control
              @nonePlaceholder={{i18n
                "atcp_case.cases.detail.close_case.placeholders.close_reason"
              }}
              autofocus
              as |select|
            >
              {{#each this.closeReasons as |reason|}}
                <select.Option @value={{reason}}>{{reason}}</select.Option>
              {{/each}}
            </field.Control>
          </form.Field>

          <form.Field
            @name="solution"
            @title={{i18n "atcp_case.cases.detail.close_case.fields.solution"}}
            @type="textarea"
            @format="full"
            @validation={{if this.solutionRequired "required:trim" ""}}
            as |field|
          >
            <field.Control rows="4" />
          </form.Field>

          <form.Field
            @name="root_cause_summary"
            @title={{i18n
              "atcp_case.cases.detail.close_case.fields.root_cause_summary"
            }}
            @type="textarea"
            @format="full"
            as |field|
          >
            <field.Control rows="3" />
          </form.Field>

          <form.Field
            @name="workaround"
            @title={{i18n "atcp_case.cases.detail.close_case.fields.workaround"}}
            @type="textarea"
            @format="full"
            as |field|
          >
            <field.Control rows="3" />
          </form.Field>

          <form.Field
            @name="conclusion"
            @title={{i18n "atcp_case.cases.detail.close_case.fields.conclusion"}}
            @type="textarea"
            @format="full"
            as |field|
          >
            <field.Control rows="3" />
          </form.Field>
        </Form>
      </:body>

      <:footer>
        <DButton
          @translatedLabel={{i18n "atcp_case.cases.detail.close_case.cancel"}}
          class="btn-default atcp-case-close-modal__cancel"
          @action={{this.cancel}}
          @disabled={{this.isSubmitting}}
        />
        <DButton
          @translatedLabel={{i18n "atcp_case.cases.detail.close_case.submit"}}
          class="btn-primary atcp-case-close-modal__submit"
          @action={{this.submitForm}}
          @disabled={{this.isSubmitting}}
          @isLoading={{this.isSubmitting}}
        />
      </:footer>
    </DModal>
  </template>
}
