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
import { eq, not } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import {
  addUpdateStatusOptions,
  buildAddUpdatePayload,
  KEEP_CURRENT_STATUS,
  MAX_UPDATE_TYPE_LENGTH,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-add-update";
import { normalizeCaseErrors } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-errors";
import { caseStatusKey } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-list-params";
import AtcpCaseDetailAttachmentsEditor from "./attachments-editor";

const FIELD_KEYS = {
  update_type: "update_type",
  body: "note",
  status: "status",
  upload_ids: "attachments",
};

export default class AtcpCaseDetailAddUpdate extends Component {
  @service a11y;
  @service dialog;
  @service router;

  @tracked formApi;
  @tracked isFormOpen = false;
  @tracked isSubmitting = false;
  @tracked uploadIdsErrors = [];
  @tracked serverErrors = [];
  @tracked
  attachmentsState = {
    uploadIds: [],
    removeAttachmentIds: [],
    hasUploadsInProgress: false,
    hasAnyAttachments: false,
    totalAttachmentCount: 0,
    hasAttachmentChanges: false,
  };

  get isClosed() {
    return this.args.atcpCase?.status === "Closed";
  }

  get caseId() {
    return this.args.caseId ?? this.args.atcpCase?.id;
  }

  get formId() {
    return `atcp-case-add-update-form-${this.caseId || "new"}`;
  }

  get toggleId() {
    return `atcp-case-add-update-toggle-${this.caseId || "new"}`;
  }

  get maxUpdateTypeLength() {
    return MAX_UPDATE_TYPE_LENGTH;
  }

  get hasFormContent() {
    return this.formApi?.isDirty || this.attachmentsState.hasAttachmentChanges;
  }

  get uploadOptions() {
    return this.args.formOptions?.upload;
  }

  get attachmentsUploadId() {
    return `atcp-case-add-update-${this.caseId || "new"}`;
  }

  get statusOptions() {
    return addUpdateStatusOptions(
      this.args.formOptions?.statuses,
      this.args.atcpCase?.status
    ).map((status) => ({
      value: status,
      label: i18n(`atcp_case.cases.statuses.${caseStatusKey(status)}`),
    }));
  }

  get submitDisabled() {
    return this.isSubmitting || this.attachmentsState.hasUploadsInProgress;
  }

  get keepCurrentStatus() {
    return KEEP_CURRENT_STATUS;
  }

  @cached
  get initialData() {
    return {
      update_type: "",
      body: "",
      status: KEEP_CURRENT_STATUS,
    };
  }

  @action
  registerApi(api) {
    this.formApi = api;
  }

  @action
  openForm() {
    this.serverErrors = [];
    this.isFormOpen = true;

    next(() => {
      document.querySelector(`#${this.formId} textarea`)?.focus();
    });
  }

  @action
  async cancel() {
    if (!this.hasFormContent) {
      this.closeForm();
      return;
    }

    const discard = await this.dialog.confirm({
      message: i18n(
        "atcp_case.cases.detail.add_update.discard_confirmation"
      ),
      confirmButtonLabel: "atcp_case.cases.detail.add_update.discard",
      cancelButtonLabel: "atcp_case.cases.detail.add_update.keep_editing",
    });

    if (discard) {
      this.closeForm();
    }
  }

  @action
  closeForm() {
    this.formApi?.reset();
    this.uploadIdsErrors = [];
    this.serverErrors = [];
    this.attachmentsState = this.#emptyAttachmentsState();
    this.isFormOpen = false;

    next(() => {
      document.getElementById(this.toggleId)?.focus();
    });
  }

  @action
  attachmentsChanged(state) {
    this.attachmentsState = state;
    this.uploadIdsErrors = [];

    if (state.hasAnyAttachments) {
      this.formApi?.removeError("body");
    }
  }

  @action
  updateNativeField(field, event) {
    field.set(event.target.value);
  }

  @action
  validateForm(data, { addError, removeError }) {
    removeError("body");

    if (!String(data.body || "").trim() && !this.attachmentsState.hasAnyAttachments) {
      addError("body", {
        title: i18n("atcp_case.cases.detail.add_update.fields.note"),
        message: i18n(
          "atcp_case.cases.detail.add_update.errors.note_or_attachment"
        ),
      });
    }
  }

  @action
  async onSubmit(data) {
    if (this.submitDisabled) {
      return;
    }

    this.formApi?.removeErrors();
    this.serverErrors = [];
    this.uploadIdsErrors = [];
    this.isSubmitting = true;

    try {
      await ajax(`/atcp/cases/${this.args.atcpCase.id}/updates.json`, {
        type: "POST",
        data: buildAddUpdatePayload({
          updateType: data.update_type,
          body: data.body,
          status: data.status,
          uploadIds: this.attachmentsState.uploadIds,
        }),
      });

      this.formApi?.reset();
      this.uploadIdsErrors = [];
      this.serverErrors = [];
      this.attachmentsState = this.#emptyAttachmentsState();
      this.isFormOpen = false;
      await this.router.refresh();
      this.a11y.announce(
        i18n("atcp_case.cases.detail.add_update.announcement"),
        "polite"
      );
      next(() => {
        document.getElementById(this.toggleId)?.focus();
      });
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

  async applyServerErrors(payload) {
    const { fieldErrors, baseErrors } = normalizeCaseErrors(payload);
    const messages = [];
    let refresh = false;

    Object.entries(fieldErrors).forEach(([field, fieldMessages]) => {
      if (field === "upload_ids") {
        this.uploadIdsErrors = [...fieldMessages];
        return;
      }

      const fieldKey = FIELD_KEYS[field];
      if (fieldKey) {
        fieldMessages.forEach((message) => {
          this.formApi?.addError(field, {
            title: i18n(
              `atcp_case.cases.detail.add_update.fields.${fieldKey}`
            ),
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
    }
  }

  #emptyAttachmentsState() {
    return {
      uploadIds: [],
      removeAttachmentIds: [],
      hasUploadsInProgress: false,
      hasAnyAttachments: false,
      totalAttachmentCount: 0,
      hasAttachmentChanges: false,
    };
  }

  #humanize(field) {
    const label = String(field).replaceAll("_", " ");
    return label.charAt(0).toUpperCase() + label.slice(1);
  }

  <template>
    <section class="atcp-case-detail-add-update">
      {{#if this.isClosed}}
        <p class="atcp-case-detail-add-update__closed">
          {{i18n "atcp_case.cases.detail.add_update.closed"}}
        </p>
      {{else}}
        {{#unless this.isFormOpen}}
          <button
            id={{this.toggleId}}
            type="button"
            class="btn btn-primary atcp-case-detail-add-update__toggle"
            aria-expanded="false"
            aria-controls={{this.formId}}
            {{on "click" this.openForm}}
          >
            {{i18n "atcp_case.cases.detail.add_update.title"}}
          </button>
        {{/unless}}

        <div id={{this.formId}}>
          {{#if this.isFormOpen}}
            {{#if this.serverErrors.length}}
              <div
                class="alert alert-error atcp-case-detail-add-update__errors"
                role="alert"
              >
                <p class="atcp-case-detail-add-update__errors-title">
                  {{i18n "atcp_case.cases.detail.add_update.errors_title"}}
                </p>
                <ul class="atcp-case-detail-add-update__errors-list">
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
              @validate={{this.validateForm}}
              as |form|
            >
              <form.Row as |row|>
                <row.Col @size={{6}}>
                  <form.Field
                    @name="update_type"
                    @title={{i18n
                      "atcp_case.cases.detail.add_update.fields.update_type"
                    }}
                    @description={{i18n
                      "atcp_case.cases.detail.add_update.hints.update_type"
                    }}
                    @type="custom"
                    @validation="length:0,100"
                    as |field|
                  >
                    <field.Control>
                      <input
                        id={{field.id}}
                        name={{field.name}}
                        type="text"
                        class="atcp-case-detail-add-update__input"
                        value={{field.value}}
                        maxlength={{this.maxUpdateTypeLength}}
                        placeholder={{i18n
                          "atcp_case.cases.detail.add_update.placeholders.update_type"
                        }}
                        aria-describedby={{field.describedBy}}
                        aria-invalid={{if field.error "true"}}
                        {{on "input" (fn this.updateNativeField field)}}
                      />
                    </field.Control>
                  </form.Field>
                </row.Col>

                <row.Col @size={{6}}>
                  <form.Field
                    @name="status"
                    @title={{i18n
                      "atcp_case.cases.detail.add_update.fields.status"
                    }}
                    @type="custom"
                    as |field|
                  >
                    <field.Control>
                      <select
                        id={{field.id}}
                        name={{field.name}}
                        class="atcp-case-detail-add-update__select"
                        value={{field.value}}
                        aria-describedby={{field.describedBy}}
                        aria-invalid={{if field.error "true"}}
                        {{on "change" (fn this.updateNativeField field)}}
                      >
                        <option
                          value={{this.keepCurrentStatus}}
                          selected={{not field.value}}
                        >
                          {{i18n
                            "atcp_case.cases.detail.add_update.options.keep_status"
                          }}
                        </option>
                        {{#each this.statusOptions as |statusOption|}}
                          <option
                            value={{statusOption.value}}
                            selected={{eq field.value statusOption.value}}
                          >
                            {{statusOption.label}}
                          </option>
                        {{/each}}
                      </select>
                    </field.Control>
                  </form.Field>
                </row.Col>
              </form.Row>

              <form.Field
                @name="body"
                @title={{i18n "atcp_case.cases.detail.add_update.fields.note"}}
                @format="full"
                @type="textarea"
                @placeholder={{i18n
                  "atcp_case.cases.detail.add_update.placeholders.note"
                }}
                as |field|
              >
                <field.Control rows="5" />
              </form.Field>

          <AtcpCaseDetailAttachmentsEditor
            @classPrefix="atcp-case-detail-add-update"
            @uploadId={{this.attachmentsUploadId}}
            @uploadOptions={{this.uploadOptions}}
            @uploadErrors={{this.uploadIdsErrors}}
            @onChange={{this.attachmentsChanged}}
          />

              <form.Actions>
                <button
                  type="button"
                  class="btn btn-flat atcp-case-detail-add-update__cancel"
                  {{on "click" this.cancel}}
                >
                  {{i18n "atcp_case.cases.detail.add_update.cancel"}}
                </button>
                <form.Submit
                  @label="atcp_case.cases.detail.add_update.submit"
                  @disabled={{this.submitDisabled}}
                  @isLoading={{this.isSubmitting}}
                  class="atcp-case-detail-add-update__submit"
                />
              </form.Actions>
            </Form>
          {{/if}}
        </div>
      {{/if}}
    </section>
  </template>
}
