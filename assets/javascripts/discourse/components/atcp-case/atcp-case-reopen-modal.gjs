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
  buildReopenPayload,
  REOPEN_REASON_MAX_LENGTH,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-close-reopen";
import { normalizeCaseErrors } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-errors";

const FIELD_TITLE_KEYS = {
  reason: "atcp_case.cases.detail.reopen_case.fields.reason",
};

function humanizeField(field) {
  const label = String(field).replaceAll("_", " ");
  return label.charAt(0).toUpperCase() + label.slice(1);
}

export default class AtcpCaseReopenModal extends Component {
  @service dialog;
  @service router;

  @tracked draft = { reason: "" };
  @tracked formApi;
  @tracked isSubmitting = false;
  @tracked serverErrors = [];

  get maxReasonLength() {
    return REOPEN_REASON_MAX_LENGTH;
  }

  @cached
  get initialData() {
    return { reason: "" };
  }

  get hasChanges() {
    return String(this.draft?.reason ?? "").trim() !== "";
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
  async onSubmit(data) {
    if (this.isSubmitting) {
      return;
    }

    this.formApi?.removeErrors();
    this.serverErrors = [];
    this.isSubmitting = true;

    try {
      await ajax(`/atcp/cases/${this.args.model?.atcpCase?.id}/reopen.json`, {
        type: "POST",
        data: buildReopenPayload(data.reason),
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
      message: i18n("atcp_case.cases.detail.reopen_case.discard_confirmation"),
      confirmButtonLabel: "atcp_case.cases.detail.reopen_case.discard",
      cancelButtonLabel: "atcp_case.cases.detail.reopen_case.keep_editing",
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
      message: i18n("atcp_case.cases.detail.reopen_case.discard_confirmation"),
      confirmButtonLabel: "atcp_case.cases.detail.reopen_case.discard",
      cancelButtonLabel: "atcp_case.cases.detail.reopen_case.keep_editing",
    });
  }

  applyServerErrors(payload) {
    const { fieldErrors, baseErrors } = normalizeCaseErrors(payload);
    const messages = [...baseErrors];

    Object.entries(fieldErrors).forEach(([field, fieldMessages]) => {
      if (FIELD_TITLE_KEYS[field]) {
        fieldMessages.forEach((message) => {
          this.formApi?.addError(field, {
            title: i18n(FIELD_TITLE_KEYS[field]),
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

  <template>
    <DModal
      @title={{i18n "atcp_case.cases.detail.reopen_case.title"}}
      @closeModal={{@closeModal}}
      @beforeClose={{this.beforeClose}}
      class="atcp-case-reopen-modal"
    >
      <:body>
        <p class="atcp-case-reopen-modal__note">
          {{i18n "atcp_case.cases.detail.reopen_case.note"}}
        </p>

        {{#if this.serverErrors.length}}
          <div
            class="alert alert-error atcp-case-reopen-modal__errors"
            role="alert"
          >
            <p class="atcp-case-reopen-modal__errors-title">
              {{i18n "atcp_case.cases.detail.reopen_case.errors_title"}}
            </p>
            <ul class="atcp-case-reopen-modal__errors-list">
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
            @name="reason"
            @title={{i18n "atcp_case.cases.detail.reopen_case.fields.reason"}}
            @type="textarea"
            @format="full"
            @validation="required:trim|length:0,2000"
            as |field|
          >
            <field.Control
              rows="5"
              maxlength={{this.maxReasonLength}}
              autofocus
            />
          </form.Field>
        </Form>
      </:body>

      <:footer>
        <DButton
          @translatedLabel={{i18n "atcp_case.cases.detail.reopen_case.cancel"}}
          class="btn-default atcp-case-reopen-modal__cancel"
          @action={{this.cancel}}
          @disabled={{this.isSubmitting}}
        />
        <DButton
          @translatedLabel={{i18n "atcp_case.cases.detail.reopen_case.submit"}}
          class="btn-primary atcp-case-reopen-modal__submit"
          @action={{this.submitForm}}
          @disabled={{this.isSubmitting}}
          @isLoading={{this.isSubmitting}}
        />
      </:footer>
    </DModal>
  </template>
}
