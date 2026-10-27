import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat, fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import UppyUpload from "discourse/lib/uppy/uppy-upload";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import I18n, { i18n } from "discourse-i18n";
import {
  attachmentValidation,
  FALLBACK_ADD_UPDATE_FORM_OPTIONS,
  isDuplicateFile,
  MAX_ATTACHMENTS,
  normalizeUploadFileName,
  resolveUploadCompletion,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-add-update";

export default class AtcpCaseDetailAttachmentsEditor extends Component {
  @tracked selectedFiles = [];
  @tracked fileErrors = [];
  @tracked removedAttachmentIds = [];

  uppyUpload;

  constructor(owner, args) {
    super(owner, args);

    this.uppyUpload = new UppyUpload(getOwner(this), {
      id: args.uploadId || "atcp-case-attachment-editor",
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

  get classPrefix() {
    return this.args.classPrefix || "atcp-case-detail-attachments";
  }

  get uploadOptions() {
    return (
      this.args.uploadOptions ||
      FALLBACK_ADD_UPDATE_FORM_OPTIONS.upload
    );
  }

  get acceptAttribute() {
    return (this.uploadOptions.extensions || [])
      .map((extension) => `.${String(extension).replace(/^\./, "")}`)
      .join(",");
  }

  get maxAttachments() {
    return MAX_ATTACHMENTS;
  }

  get existingAttachments() {
    return this.args.existingAttachments || [];
  }

  get existingAttachmentRows() {
    return this.existingAttachments.map((attachment) => ({
      ...attachment,
      removed: this.removedAttachmentIds.includes(attachment.id),
    }));
  }

  get remainingExistingCount() {
    return this.existingAttachments.filter(
      (attachment) => !this.removedAttachmentIds.includes(attachment.id)
    ).length;
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

  get hasAnyAttachments() {
    return (
      this.remainingExistingCount + this.completedUploads.length > 0
    );
  }

  get totalAttachmentCount() {
    return this.remainingExistingCount + this.selectedFiles.length;
  }

  get hasAttachmentChanges() {
    return (
      this.selectedFiles.length > 0 || this.removedAttachmentIds.length > 0
    );
  }

  get uploadErrors() {
    return this.args.uploadErrors || [];
  }

  get removeErrors() {
    return this.args.removeErrors || [];
  }

  get uploadWaitMessageKey() {
    return (
      this.args.uploadWaitMessageKey ||
      "atcp_case.cases.detail.add_update.upload_wait"
    );
  }

  @action
  setupUpload(input) {
    this.uppyUpload.setup(input);
  }

  @action
  openPicker() {
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

    if (this.totalAttachmentCount >= MAX_ATTACHMENTS) {
      this.#addFileError(this.#attachmentLimitMessage());
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
    this.#emitChange();

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
    this.#emitChange();
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
    this.#emitChange();
  }

  @action
  removeFile(file) {
    this.#removeUppyFile(file, { cancel: file.status === "uploading" });

    this.selectedFiles = this.selectedFiles.filter(
      (selected) => selected !== file
    );
    this.#emitChange();
  }

  @action
  removeExistingAttachment(attachment) {
    if (this.removedAttachmentIds.includes(attachment.id)) {
      return;
    }

    this.removedAttachmentIds = [
      ...this.removedAttachmentIds,
      attachment.id,
    ];
    this.#emitChange();
  }

  @action
  undoRemoveExistingAttachment(attachment) {
    if (this.totalAttachmentCount + 1 > MAX_ATTACHMENTS) {
      this.#addFileError(this.#attachmentLimitMessage());
      return;
    }

    this.fileErrors = this.fileErrors.filter(
      (message) => message !== this.#attachmentLimitMessage()
    );
    this.removedAttachmentIds = this.removedAttachmentIds.filter(
      (id) => id !== attachment.id
    );
    this.#emitChange();
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

  #emitChange() {
    this.args.onChange?.({
      uploadIds: [...this.uploadIds],
      removeAttachmentIds: [...this.removedAttachmentIds],
      hasUploadsInProgress: this.hasUploadsInProgress,
      hasAnyAttachments: this.hasAnyAttachments,
      totalAttachmentCount: this.totalAttachmentCount,
      hasAttachmentChanges: this.hasAttachmentChanges,
    });
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

  #sameFileName(first, second) {
    return normalizeUploadFileName(first) === normalizeUploadFileName(second);
  }

  #addFileError(message) {
    if (!this.fileErrors.includes(message)) {
      this.fileErrors = [...this.fileErrors, message];
    }
  }

  #attachmentLimitMessage() {
    return i18n("atcp_case.cases.detail.add_update.errors.attachment_limit", {
      count: MAX_ATTACHMENTS,
    });
  }

  <template>
    <fieldset class="atcp-case-attachments-editor__attachments {{this.classPrefix}}__attachments">
      <legend class="atcp-case-attachments-editor__attachments-title {{this.classPrefix}}__attachments-title">
        {{i18n "atcp_case.cases.detail.add_update.fields.attachments"}}
      </legend>

      {{#if this.existingAttachmentRows.length}}
        <p class="atcp-case-attachments-editor__existing-title {{this.classPrefix}}__existing-title">
          {{i18n
            "atcp_case.cases.detail.attachments_editor.existing_attachments"
          }}
        </p>

        <ul class="atcp-case-attachments-editor__existing-files {{this.classPrefix}}__existing-files">
          {{#each this.existingAttachmentRows as |attachment|}}
            <li
              class="atcp-case-attachments-editor__existing-file {{this.classPrefix}}__existing-file {{if attachment.removed (concat this.classPrefix '__existing-file--removed')}}"
              data-attachment-id={{attachment.id}}
            >
              <span class="atcp-case-attachments-editor__existing-file-name {{this.classPrefix}}__existing-file-name">
                {{attachment.original_filename}}
              </span>
              <span class="atcp-case-attachments-editor__existing-file-size {{this.classPrefix}}__existing-file-size">
                {{attachment.human_filesize}}
              </span>

              {{#if attachment.removed}}
                <span class="atcp-case-attachments-editor__existing-file-status {{this.classPrefix}}__existing-file-status">
                  {{i18n
                    "atcp_case.cases.detail.attachments_editor.marked_for_removal"
                  }}
                </span>
                <button
                  type="button"
                  class="btn btn-default btn-small atcp-case-attachments-editor__undo-remove {{this.classPrefix}}__undo-remove"
                  aria-label={{i18n
                    "atcp_case.cases.detail.attachments_editor.undo_remove"
                    filename=attachment.original_filename
                  }}
                  {{on "click" (fn this.undoRemoveExistingAttachment attachment)}}
                >
                  {{i18n "atcp_case.cases.detail.attachments_editor.undo"}}
                </button>
              {{else}}
                <button
                  type="button"
                  class="btn btn-default btn-small atcp-case-attachments-editor__remove-existing {{this.classPrefix}}__remove-existing"
                  aria-label={{i18n
                    "atcp_case.cases.detail.attachments_editor.remove_existing"
                    filename=attachment.original_filename
                  }}
                  {{on "click" (fn this.removeExistingAttachment attachment)}}
                >
                  {{i18n "atcp_case.cases.detail.attachments_editor.remove"}}
                </button>
              {{/if}}
            </li>
          {{/each}}
        </ul>

        {{#if this.removeErrors.length}}
          <ul class="atcp-case-attachments-editor__remove-errors {{this.classPrefix}}__remove-errors" role="alert">
            {{#each this.removeErrors as |message|}}
              <li>{{message}}</li>
            {{/each}}
          </ul>
        {{/if}}
      {{/if}}

      <p class="atcp-case-attachments-editor__hint {{this.classPrefix}}__hint">
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
        class="btn-default atcp-case-attachments-editor__attach {{this.classPrefix}}__attach"
      />

      <input
        type="file"
        multiple
        accept={{this.acceptAttribute}}
        class="atcp-case-attachments-editor__file-input {{this.classPrefix}}__file-input"
        {{didInsert this.setupUpload}}
        aria-hidden="true"
        tabindex="-1"
      />

      {{#if this.hasUploadsInProgress}}
        <p class="atcp-case-attachments-editor__upload-wait {{this.classPrefix}}__upload-wait" aria-live="polite">
          {{i18n this.uploadWaitMessageKey}}
        </p>
      {{/if}}

      {{#if this.fileErrors.length}}
        <ul class="atcp-case-attachments-editor__file-errors {{this.classPrefix}}__file-errors" role="alert">
          {{#each this.fileErrors as |message|}}
            <li>{{message}}</li>
          {{/each}}
        </ul>
      {{/if}}

      {{#if this.selectedFiles.length}}
        <ul class="atcp-case-attachments-editor__file-list {{this.classPrefix}}__file-list">
          {{#each this.selectedFiles as |file|}}
            <li
              class="atcp-case-attachments-editor__file {{this.classPrefix}}__file"
              data-file-name={{file.name}}
            >
              <span class="atcp-case-attachments-editor__file-name {{this.classPrefix}}__file-name">
                {{file.name}}
              </span>
              <span class="atcp-case-attachments-editor__file-size {{this.classPrefix}}__file-size">
                {{file.humanFilesize}}
              </span>

              {{#if (eq file.status "uploading")}}
                <progress
                  class="atcp-case-attachments-editor__file-progress {{this.classPrefix}}__file-progress"
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
                <span class="atcp-case-attachments-editor__file-error {{this.classPrefix}}__file-error">
                  {{file.error}}
                </span>
              {{/if}}

              <button
                type="button"
                class="btn btn-default btn-small atcp-case-attachments-editor__remove {{this.classPrefix}}__remove"
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

      {{#if this.uploadErrors.length}}
        <ul class="atcp-case-attachments-editor__upload-errors {{this.classPrefix}}__upload-errors" role="alert">
          {{#each this.uploadErrors as |message|}}
            <li>{{message}}</li>
          {{/each}}
        </ul>
      {{/if}}
    </fieldset>
  </template>
}
