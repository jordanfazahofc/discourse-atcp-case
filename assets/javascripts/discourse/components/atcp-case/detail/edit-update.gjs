import Component from "@glimmer/component";
import { cached, tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { next } from "@ember/runloop";
import { service } from "@ember/service";
import Form from "discourse/components/form";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import {
  MAX_UPDATE_TYPE_LENGTH,
  updateTypeSuggestions,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-add-update";
import {
  buildEditUpdatePayload,
  validateEditUpdateType,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-edit-update";
import { normalizeCaseErrors } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-errors";
import AtcpCaseUpdateTypeSuggestions from "./update-type-suggestions";

const FIELD_TITLE_KEYS = {
  update_type: "atcp_case.cases.detail.edit_update.fields.update_type",
  body: "atcp_case.cases.detail.edit_update.fields.note",
};

export default class AtcpCaseDetailEditUpdate extends Component {
  @service dialog;
  @service router;

  @tracked draft;
  @tracked formApi;
  @tracked isSubmitting = false;
  @tracked serverErrors = [];

  constructor(owner, args) {
    super(owner, args);

    this.draft = {
      update_type: String(args.update?.update_type ?? "").trim(),
      body: String(args.update?.body ?? ""),
    };
  }

  get formId() {
    return `atcp-case-edit-update-form-${this.args.update?.id}`;
  }

  get updateTypeListId() {
    return `atcp-case-edit-update-type-options-${this.args.update?.id}`;
  }

  get maxUpdateTypeLength() {
    return MAX_UPDATE_TYPE_LENGTH;
  }

  get updateTypeLabels() {
    return updateTypeSuggestions(this.args.formOptions);
  }

  get hasAttachments() {
    return Boolean(this.args.update?.attachments?.length);
  }

  get changedPayload() {
    return buildEditUpdatePayload({
      initialUpdate: this.args.update,
      updateType: this.draft.update_type,
      body: this.draft.body,
    });
  }

  get hasChanges() {
    return Object.keys(this.changedPayload).length > 0;
  }

  get saveDisabled() {
    return this.isSubmitting || !this.hasChanges;
  }

  @cached
  get initialData() {
    return {
      update_type: String(this.args.update?.update_type ?? "").trim(),
      body: String(this.args.update?.body ?? ""),
    };
  }

  @action
  registerApi(api) {
    this.formApi = api;

    next(() => {
      document.querySelector(`#${this.formId} input`)?.focus();
    });
  }

  @action
  async updateField(field, name, event) {
    const value = event.target.value;

    this.draft = { ...this.draft, [name]: value };
    this.serverErrors = [];
    this.formApi?.removeError(name);
    await field.set(value);
  }

  @action
  validate(data, { addError, removeError }) {
    removeError("update_type");
    removeError("body");

    const typeFailure = validateEditUpdateType(data.update_type);
    if (typeFailure) {
      addError("update_type", {
        title: this.#fieldTitle("update_type"),
        message: i18n(
          `atcp_case.cases.detail.edit_update.errors.${typeFailure.key}`,
          { max: typeFailure.max }
        ),
      });
    }

    if (!String(data.body ?? "").trim() && !this.hasAttachments) {
      addError("body", {
        title: this.#fieldTitle("body"),
        message: i18n(
          "atcp_case.cases.detail.edit_update.errors.note_or_attachment"
        ),
      });
    }
  }

  @action
  async save(data) {
    if (this.isSubmitting) {
      return;
    }

    const payload = buildEditUpdatePayload({
      initialUpdate: this.args.update,
      updateType: data.update_type,
      body: data.body,
    });

    if (!Object.keys(payload).length) {
      return;
    }

    this.formApi?.removeErrors();
    this.serverErrors = [];
    this.isSubmitting = true;

    try {
      await ajax(
        `/atcp/cases/${this.args.update.case_id ?? this.args.atcpCase?.id}/updates/${this.args.update.id}.json`,
        { type: "PUT", data: payload }
      );
      await this.router.refresh();
      this.args.onSaved?.();
    } catch (error) {
      if (error?.jqXHR?.status === 422) {
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
      this.args.onCancel?.();
      return;
    }

    const discard = await this.dialog.confirm({
      message: i18n(
        "atcp_case.cases.detail.edit_update.discard_confirmation"
      ),
      confirmButtonLabel: "atcp_case.cases.detail.edit_update.discard",
      cancelButtonLabel: "atcp_case.cases.detail.edit_update.keep_editing",
    });

    if (discard) {
      this.args.onCancel?.();
    }
  }

  async applyServerErrors(payload) {
    const { fieldErrors, baseErrors } = normalizeCaseErrors(payload);
    const messages = [];
    let refresh = false;

    Object.entries(fieldErrors).forEach(([field, fieldMessages]) => {
      if (FIELD_TITLE_KEYS[field]) {
        fieldMessages.forEach((message) => {
          this.formApi?.addError(field, {
            title: this.#fieldTitle(field),
            message,
          });
        });
        return;
      }

      fieldMessages.forEach((message) => {
        messages.push(`${this.#humanize(field)}: ${message}`);
      });
    });

    baseErrors.forEach((message) => {
      messages.push(message);
      if (/closed/i.test(message)) {
        refresh = true;
      }
    });

    this.serverErrors = messages;

    if (refresh) {
      await this.router.refresh();
      this.args.onCancel?.();
    }
  }

  #fieldTitle(field) {
    return i18n(FIELD_TITLE_KEYS[field]);
  }

  #humanize(field) {
    const label = String(field).replaceAll("_", " ");
    return label.charAt(0).toUpperCase() + label.slice(1);
  }

  <template>
    <section
      id={{this.formId}}
      class="atcp-case-detail-edit-update"
      aria-label={{i18n "atcp_case.cases.detail.edit_update.title"}}
    >
      {{#if this.serverErrors.length}}
        <div
          class="alert alert-error atcp-case-detail-edit-update__errors"
          role="alert"
        >
          <p class="atcp-case-detail-edit-update__errors-title">
            {{i18n "atcp_case.cases.detail.edit_update.errors_title"}}
          </p>
          <ul class="atcp-case-detail-edit-update__errors-list">
            {{#each this.serverErrors as |message|}}
              <li>{{message}}</li>
            {{/each}}
          </ul>
        </div>
      {{/if}}

      <Form
        @data={{this.initialData}}
        @onSubmit={{this.save}}
        @onRegisterApi={{this.registerApi}}
        @validate={{this.validate}}
        as |form|
      >
        <form.Field
          @name="update_type"
          @title={{i18n "atcp_case.cases.detail.edit_update.fields.update_type"}}
          @description={{i18n
            "atcp_case.cases.detail.edit_update.hints.update_type"
          }}
          @type="custom"
          as |field|
        >
          <field.Control>
            <input
              id={{field.id}}
              name={{field.name}}
              type="text"
              class="atcp-case-detail-edit-update__input"
              value={{field.value}}
              maxlength={{this.maxUpdateTypeLength}}
              list={{this.updateTypeListId}}
              placeholder={{i18n
                "atcp_case.cases.detail.edit_update.placeholders.update_type"
              }}
              aria-describedby={{field.describedBy}}
              aria-invalid={{if field.error "true"}}
              {{on "input" (fn this.updateField field "update_type")}}
            />
            <AtcpCaseUpdateTypeSuggestions
              @id={{this.updateTypeListId}}
              @labels={{this.updateTypeLabels}}
            />
          </field.Control>
        </form.Field>

        <form.Field
          @name="body"
          @title={{i18n "atcp_case.cases.detail.edit_update.fields.note"}}
          @format="full"
          @type="custom"
          as |field|
        >
          <field.Control>
            <textarea
              id={{field.id}}
              name={{field.name}}
              rows="5"
              class="atcp-case-detail-edit-update__note"
              placeholder={{i18n
                "atcp_case.cases.detail.add_update.placeholders.note"
              }}
              value={{field.value}}
              aria-describedby={{field.describedBy}}
              aria-invalid={{if field.error "true"}}
              {{on "input" (fn this.updateField field "body")}}
            ></textarea>
          </field.Control>
        </form.Field>

        <form.Actions>
          <button
            type="button"
            class="btn btn-flat atcp-case-detail-edit-update__cancel"
            {{on "click" this.cancel}}
          >
            {{i18n "atcp_case.cases.detail.edit_update.cancel"}}
          </button>
          <form.Submit
            @label="atcp_case.cases.detail.edit_update.save"
            @disabled={{this.saveDisabled}}
            @isLoading={{this.isSubmitting}}
            class="atcp-case-detail-edit-update__save"
          />
        </form.Actions>
      </Form>
    </section>
  </template>
}
