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
import { MAX_UPDATE_TYPE_LENGTH } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-add-update";
import { exceedsAttachmentLimit } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-attachments";
import {
  buildEditUpdatePayload,
  validateEditUpdateType,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-edit-update";
import { normalizeCaseErrors } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-errors";
import AtcpCaseDetailAttachmentsEditor from "./attachments-editor";

const FIELD_TITLE_KEYS = {
  update_type: "atcp_case.cases.detail.edit_update.fields.update_type",
  body: "atcp_case.cases.detail.edit_update.fields.note",
};

export default class AtcpCaseDetailEditUpdate extends Component {
  @service a11y;
  @service dialog;
  @service router;

  @tracked draft;
  @tracked formApi;
  @tracked isSubmitting = false;
  @tracked serverErrors = [];
  @tracked uploadErrors = [];
  @tracked removeErrors = [];
  @tracked
  attachmentsState = {
    uploadIds: [],
    removeAttachmentIds: [],
    hasUploadsInProgress: false,
    hasAnyAttachments: false,
    totalAttachmentCount: 0,
    hasAttachmentChanges: false,
  };

  constructor(owner, args) {
    super(owner, args);

    this.draft = {
      update_type: String(args.update?.update_type ?? "").trim(),
      body: String(args.update?.body ?? ""),
    };
    this.attachmentsState = {
      uploadIds: [],
      removeAttachmentIds: [],
      hasUploadsInProgress: false,
      hasAnyAttachments: Boolean(args.update?.attachments?.length),
      totalAttachmentCount: args.update?.attachments?.length || 0,
      hasAttachmentChanges: false,
    };
  }

  get formId() {
    return `atcp-case-edit-update-form-${this.args.update?.id}`;
  }

  get maxUpdateTypeLength() {
    return MAX_UPDATE_TYPE_LENGTH;
  }

  get bodyOnly() {
    return Boolean(this.args.bodyOnly);
  }

  get lockUpdateType() {
    return Boolean(this.args.update?.initial_report);
  }

  get showUpdateType() {
    return !this.bodyOnly && !this.lockUpdateType;
  }

  get bodyRequired() {
    return this.bodyOnly && this.args.update?.system_event === "reopened";
  }

  get attachmentLimitExceeded() {
    return (
      !this.bodyOnly &&
      exceedsAttachmentLimit({
        existingAttachments: this.args.update?.attachments || [],
        removeAttachmentIds: this.attachmentsState.removeAttachmentIds,
        uploadIds: this.attachmentsState.uploadIds,
      })
    );
  }

  get uploadOptions() {
    return this.args.formOptions?.upload;
  }

  get attachmentsUploadId() {
    return `atcp-case-edit-update-${this.args.update?.id}`;
  }

  get changedPayload() {
    return buildEditUpdatePayload({
      initialUpdate: this.args.update,
      updateType: this.draft.update_type,
      body: this.draft.body,
      bodyOnly: this.bodyOnly,
      lockUpdateType: this.lockUpdateType,
      uploadIds: this.attachmentsState.uploadIds,
      removeAttachmentIds: this.attachmentsState.removeAttachmentIds,
    });
  }

  get hasChanges() {
    return Object.keys(this.changedPayload).length > 0;
  }

  get saveDisabled() {
    return (
      this.isSubmitting ||
      !this.hasChanges ||
      this.attachmentsState.hasUploadsInProgress ||
      this.attachmentLimitExceeded
    );
  }

  @cached
  get initialData() {
    const data = {
      body: String(this.args.update?.body ?? ""),
    };

    if (!this.bodyOnly) {
      data.update_type = String(this.args.update?.update_type ?? "").trim();
    }

    return data;
  }

  @action
  registerApi(api) {
    this.formApi = api;

    next(() => {
      const selector =
        this.bodyOnly || this.lockUpdateType ? "textarea" : "input";
      document.querySelector(`#${this.formId} ${selector}`)?.focus();
    });
  }

  @action
  async updateField(field, name, event) {
    const value = event.target.value;

    this.draft = { ...this.draft, [name]: value };
    this.serverErrors = [];
    this.formApi?.removeError(name);
    this.#notifyDirty();
    await field.set(value);
  }

  @action
  attachmentsChanged(state) {
    this.attachmentsState = state;
    this.serverErrors = [];
    this.uploadErrors = [];
    this.removeErrors = [];
    this.formApi?.removeError("body");
    this.#notifyDirty();
  }

  @action
  handleKeydown(event) {
    if (event.key !== "Escape") {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    this.cancel();
  }

  @action
  validate(data, { addError, removeError }) {
    removeError("update_type");
    removeError("body");

    if (!this.bodyOnly && !this.lockUpdateType) {
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
    }

    if (this.bodyOnly) {
      if (this.bodyRequired && !String(data.body ?? "").trim()) {
        addError("body", {
          title: this.#fieldTitle("body"),
          message: i18n(
            "atcp_case.cases.detail.edit_update.errors.note_required"
          ),
        });
      }
      return;
    }

    if (
      !String(data.body ?? "").trim() &&
      !this.attachmentsState.hasAnyAttachments
    ) {
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
      bodyOnly: this.bodyOnly,
      lockUpdateType: this.lockUpdateType,
      uploadIds: this.attachmentsState.uploadIds,
      removeAttachmentIds: this.attachmentsState.removeAttachmentIds,
    });

    if (!Object.keys(payload).length) {
      return;
    }

    this.formApi?.removeErrors();
    this.serverErrors = [];
    this.uploadErrors = [];
    this.removeErrors = [];
    this.isSubmitting = true;

    try {
      await ajax(
        `/atcp/cases/${this.args.update.case_id ?? this.args.atcpCase?.id}/updates/${this.args.update.id}.json`,
        { type: "PUT", data: payload }
      );
      await this.router.refresh();
      this.args.onSaved?.();
    } catch (error) {
      const status = error?.jqXHR?.status;

      if (status === 403) {
        await this.router.refresh();
        this.a11y.announce(
          i18n("atcp_case.cases.detail.edit_update.no_longer_editable"),
          "polite"
        );
        this.args.onCancel?.();
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
      if (field === "upload_ids") {
        this.uploadErrors = [...fieldMessages];
        return;
      }

      if (field === "remove_attachment_ids") {
        this.removeErrors = [...fieldMessages];
        return;
      }

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

  #notifyDirty() {
    this.args.onDirtyChange?.(this.hasChanges);
  }

  #fieldTitle(field) {
    return i18n(FIELD_TITLE_KEYS[field]);
  }

  #humanize(field) {
    const label = String(field).replaceAll("_", " ");
    return label.charAt(0).toUpperCase() + label.slice(1);
  }

  <template>
    {{! eslint-disable ember/template-no-invalid-interactive }}
    <section
      id={{this.formId}}
      class="atcp-case-detail-edit-update"
      aria-label={{i18n "atcp_case.cases.detail.edit_update.title"}}
      {{on "keydown" this.handleKeydown}}
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
        {{#if this.showUpdateType}}
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
                placeholder={{i18n
                  "atcp_case.cases.detail.edit_update.placeholders.update_type"
                }}
                aria-describedby={{field.describedBy}}
                aria-invalid={{if field.error "true"}}
                {{on "input" (fn this.updateField field "update_type")}}
              />
            </field.Control>
          </form.Field>
        {{/if}}

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

        {{#unless this.bodyOnly}}
          <AtcpCaseDetailAttachmentsEditor
            @classPrefix="atcp-case-detail-edit-update"
            @uploadId={{this.attachmentsUploadId}}
            @uploadOptions={{this.uploadOptions}}
            @existingAttachments={{@update.attachments}}
            @uploadErrors={{this.uploadErrors}}
            @removeErrors={{this.removeErrors}}
            @uploadWaitMessageKey="atcp_case.cases.detail.edit_update.upload_wait"
            @onChange={{this.attachmentsChanged}}
          />
        {{/unless}}

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
