import Component from "@glimmer/component";
import { cached, tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { next } from "@ember/runloop";
import { service } from "@ember/service";
import Form from "discourse/components/form";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import UppyUpload from "discourse/lib/uppy/uppy-upload";
import { eq, not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import I18n, { i18n } from "discourse-i18n";
import {
  addUpdateStatusOptions,
  attachmentValidation,
  buildAddUpdatePayload,
  FALLBACK_ADD_UPDATE_FORM_OPTIONS,
  hasAttachmentCapacity,
  isDuplicateFile,
  KEEP_CURRENT_STATUS,
  MAX_ATTACHMENTS,
  MAX_UPDATE_TYPE_LENGTH,
  normalizeUploadFileName,
  resolveUploadCompletion,
  updateTypeSuggestions,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-add-update";
import { normalizeCaseErrors } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-errors";
import { caseStatusKey } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-list-params";
import AtcpCaseUpdateTypeSuggestions from "./update-type-suggestions";

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
  @tracked selectedFiles = [];
  @tracked fileErrors = [];
  @tracked uploadIdsErrors = [];
  @tracked serverErrors = [];

  uppyUpload;

  constructor(owner, args) {
    super(owner, args);

    this.uppyUpload = new UppyUpload(getOwner(this), {
      id: `atcp-case-add-update-${this.caseId || "new"}`,
      type: "atcp-case-attachment",
      validateUploadedFilesOptions: { skipValidation: true },
      isUploadedFileAllowed: (file) => this.isUploadedFileAllowed(file),
      uploadDone: (upload) => this.uploadDone(upload),
      uploadError: (file) => this.markUploadFailed(file),
      uppyReady: () => {
        this.uppyUpload.uppyWrapper.uppyInstance?.on(
          "upload-error",
          (file) => this.markUploadFailed(file)
        );
        this.uppyUpload.uppyWrapper.uppyInstance?.on(
          "upload-progress",
          (file, progress) => this.updateProgress(file.name, progress)
        );
      },
    });
  }

  willDestroy() {
    this.uppyUpload?.teardown();
    super.willDestroy(...arguments);
  }

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

  get updateTypeListId() {
    return `atcp-case-update-type-options-${this.caseId || "new"}`;
  }

  get maxUpdateTypeLength() {
    return MAX_UPDATE_TYPE_LENGTH;
  }

  get hasFormContent() {
    return this.formApi?.isDirty || this.selectedFiles.length > 0;
  }

  get updateLabels() {
    return updateTypeSuggestions(this.args.formOptions);
  }

  get uploadOptions() {
    return (
      this.args.formOptions?.upload ||
      FALLBACK_ADD_UPDATE_FORM_OPTIONS.upload
    );
  }

  get acceptAttribute() {
    return (this.uploadOptions.extensions || [])
      .map((extension) => `.${String(extension).replace(/^\./, "")}`)
      .join(",");
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

  get completedUploads() {
    return this.selectedFiles.filter((file) => file.status === "uploaded");
  }

  get uploadIds() {
    return this.completedUploads.map((file) => file.uploadId);
  }

  get hasUploadsInProgress() {
    return this.selectedFiles.some((file) => file.status === "uploading");
  }

  get submitDisabled() {
    return this.isSubmitting || this.hasUploadsInProgress;
  }

  get maxAttachments() {
    return MAX_ATTACHMENTS;
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
    this.#clearUppyFiles();
    this.selectedFiles = [];
    this.fileErrors = [];
    this.uploadIdsErrors = [];
    this.serverErrors = [];
    this.isFormOpen = false;

    next(() => {
      document.getElementById(this.toggleId)?.focus();
    });
  }

  @action
  setupUpload(input) {
    this.uppyUpload.setup(input);
  }

  @action
  openPicker() {
    this.fileErrors = [];
    this.uploadIdsErrors = [];
    this.uppyUpload.openPicker();
  }

  isUploadedFileAllowed(file) {
    const validation = attachmentValidation(file, this.uploadOptions);

    if (validation?.key === "file_type") {
      this.#addFileError(
        i18n("atcp_case.cases.detail.add_update.errors.file_type", {
          filename: file.name,
        })
      );
      return false;
    }

    if (validation?.key === "file_size") {
      this.#addFileError(
        i18n("atcp_case.cases.detail.add_update.errors.file_size", {
          filename: file.name,
          max_mb: validation.maxMb,
        })
      );
      return false;
    }

    if (!hasAttachmentCapacity(this.selectedFiles)) {
      this.#addFileError(
        i18n("atcp_case.cases.detail.add_update.errors.attachment_limit", {
          count: MAX_ATTACHMENTS,
        })
      );
      return false;
    }

    if (isDuplicateFile(file, this.selectedFiles)) {
      this.#addFileError(
        i18n("atcp_case.cases.detail.add_update.errors.duplicate_file", {
          filename: file.name,
        })
      );
      return false;
    }

    this.selectedFiles = [
      ...this.selectedFiles,
      {
        name: file.name,
        humanFilesize: I18n.toHumanSize(file.size),
        status: "uploading",
        progress: 0,
      },
    ];

    return true;
  }

  uploadDone(upload) {
    const { matched, unmatched } = resolveUploadCompletion(
      this.selectedFiles,
      upload
    );
    const matchedFiles = new Set(matched);
    const unmatchedFiles = new Set(unmatched);

    this.selectedFiles = this.selectedFiles.map((file) => {
      if (matchedFiles.has(file)) {
        return {
          ...file,
          status: "uploaded",
          uploadId: upload.id,
          humanFilesize: upload.human_filesize || file.humanFilesize,
        };
      }

      if (unmatchedFiles.has(file)) {
        return {
          ...file,
          status: "failed",
          error: i18n(
            "atcp_case.cases.detail.add_update.errors.upload_completion_ambiguous",
            { filename: file.name }
          ),
        };
      }

      return file;
    });

    if (matched.length) {
      this.formApi?.removeError("body");
      this.uploadIdsErrors = [];
    }
  }

  markUploadFailed(file) {
    const name = file?.name || file?.fileName;
    if (!name) {
      return;
    }

    this.selectedFiles = this.selectedFiles.map((selected) =>
      this.#sameFileName(selected.name, name)
        ? {
            ...selected,
            status: "failed",
            error: i18n(
              "atcp_case.cases.detail.add_update.errors.upload_failed",
              { filename: selected.name }
            ),
          }
        : selected
    );
  }

  @action
  removeFile(file) {
    this.#removeUppyFile(file, { cancel: file.status === "uploading" });

    this.selectedFiles = this.selectedFiles.filter(
      (selected) => selected !== file
    );
    this.uploadIdsErrors = [];
    this.formApi?.removeError("body");
  }

  #removeUppyFile(file, { cancel = false } = {}) {
    const uppy = this.uppyUpload.uppyWrapper.uppyInstance;
    const uppyFile = uppy
      ?.getFiles()
      .find((item) => this.#sameFileName(item.name, file.name));

    if (!uppyFile) {
      return;
    }

    if (cancel) {
      this.uppyUpload.cancelSingleUpload({ fileId: uppyFile.id });
    } else {
      uppy.removeFile(uppyFile.id);
    }
  }

  #clearUppyFiles() {
    const uppy = this.uppyUpload.uppyWrapper.uppyInstance;

    uppy?.getFiles().forEach((file) => uppy.removeFile(file.id));
  }

  updateProgress(name, progress) {
    const total = Number(progress?.bytesTotal) || 0;
    const value = total
      ? Math.round((Number(progress.bytesUploaded) / total) * 100)
      : 0;

    this.selectedFiles = this.selectedFiles.map((file) =>
      file.status === "uploading" && this.#sameFileName(file.name, name)
        ? { ...file, progress: value }
        : file
    );
  }

  @action
  updateNativeField(field, event) {
    field.set(event.target.value);
  }

  @action
  validateForm(data, { addError, removeError }) {
    removeError("body");

    if (!String(data.body || "").trim() && this.completedUploads.length === 0) {
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
          uploadIds: this.uploadIds,
        }),
      });

      this.formApi?.reset();
      this.#clearUppyFiles();
      this.selectedFiles = [];
      this.fileErrors = [];
      this.uploadIdsErrors = [];
      this.serverErrors = [];
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
        this.uploadIdsErrors = [...this.uploadIdsErrors, ...fieldMessages];
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

  #sameFileName(first, second) {
    return normalizeUploadFileName(first) === normalizeUploadFileName(second);
  }

  #humanize(field) {
    const label = String(field).replaceAll("_", " ");
    return label.charAt(0).toUpperCase() + label.slice(1);
  }

  #addFileError(message) {
    if (!this.fileErrors.includes(message)) {
      this.fileErrors = [...this.fileErrors, message];
    }
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
                        list={{this.updateTypeListId}}
                        placeholder={{i18n
                          "atcp_case.cases.detail.add_update.placeholders.update_type"
                        }}
                        aria-describedby={{field.describedBy}}
                        aria-invalid={{if field.error "true"}}
                        {{on "input" (fn this.updateNativeField field)}}
                      />
                      <AtcpCaseUpdateTypeSuggestions
                        @id={{this.updateTypeListId}}
                        @labels={{this.updateLabels}}
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

          <fieldset class="atcp-case-detail-add-update__attachments">
            <legend class="atcp-case-detail-add-update__attachments-title">
              {{i18n "atcp_case.cases.detail.add_update.fields.attachments"}}
            </legend>

            <p class="atcp-case-detail-add-update__hint">
              {{i18n
                "atcp_case.cases.detail.add_update.attachment_hint"
                count=this.maxAttachments
              }}
            </p>

            <DButton
              @translatedLabel={{i18n
                "atcp_case.cases.detail.add_update.attach_files"
              }}
              @action={{this.openPicker}}
              @disabled={{this.hasUploadsInProgress}}
              class="btn-default atcp-case-detail-add-update__attach"
            />

            <input
              type="file"
              multiple
              accept={{this.acceptAttribute}}
              class="atcp-case-detail-add-update__file-input"
              {{didInsert this.setupUpload}}
              aria-hidden="true"
              tabindex="-1"
            />

            {{#if this.hasUploadsInProgress}}
              <p
                class="atcp-case-detail-add-update__upload-wait"
                aria-live="polite"
              >
                {{i18n "atcp_case.cases.detail.add_update.upload_wait"}}
              </p>
            {{/if}}

            {{#if this.fileErrors.length}}
              <ul class="atcp-case-detail-add-update__file-errors" role="alert">
                {{#each this.fileErrors as |message|}}
                  <li>{{message}}</li>
                {{/each}}
              </ul>
            {{/if}}

            {{#if this.selectedFiles.length}}
              <ul class="atcp-case-detail-add-update__file-list">
                {{#each this.selectedFiles as |file|}}
                  <li
                    class="atcp-case-detail-add-update__file"
                    data-file-name={{file.name}}
                  >
                    <span class="atcp-case-detail-add-update__file-name">
                      {{file.name}}
                    </span>
                    <span class="atcp-case-detail-add-update__file-size">
                      {{file.humanFilesize}}
                    </span>

                    {{#if (eq file.status "uploading")}}
                      <progress
                        class="atcp-case-detail-add-update__file-progress"
                        max="100"
                        value={{file.progress}}
                        aria-label={{i18n
                          "atcp_case.cases.detail.add_update.file_progress"
                          filename=file.name
                        }}
                      >
                        {{file.progress}}%
                      </progress>
                    {{/if}}

                    {{#if (eq file.status "failed")}}
                      <span class="atcp-case-detail-add-update__file-error">
                        {{file.error}}
                      </span>
                    {{/if}}

                    <button
                      type="button"
                      class="btn btn-default btn-small atcp-case-detail-add-update__remove"
                      aria-label={{i18n
                        "atcp_case.cases.detail.add_update.remove_file"
                        filename=file.name
                      }}
                      {{on "click" (fn this.removeFile file)}}
                    >
                      {{i18n "atcp_case.cases.detail.add_update.remove"}}
                    </button>
                  </li>
                {{/each}}
              </ul>
            {{/if}}

            {{#if this.uploadIdsErrors.length}}
              <ul
                class="atcp-case-detail-add-update__upload-errors"
                role="alert"
              >
                {{#each this.uploadIdsErrors as |message|}}
                  <li>{{message}}</li>
                {{/each}}
              </ul>
            {{/if}}
          </fieldset>

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
