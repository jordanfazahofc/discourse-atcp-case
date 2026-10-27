import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { next } from "@ember/runloop";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import {
  displayUserName,
  formatCaseDate,
  formatCaseDateTime,
  normalizeEditHistory,
  relativeCaseTime,
  systemEventText,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-detail";
import { normalizeCaseErrors } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-errors";
import AtcpCaseDetailEditUpdate from "./edit-update";

export default class AtcpCaseDetailUpdate extends Component {
  @service a11y;
  @service dialog;
  @service router;

  @tracked isDeleting = false;

  get author() {
    return displayUserName(this.args.update?.user);
  }

  get relativeTime() {
    return relativeCaseTime(this.args.update?.created_at);
  }

  get timeTitle() {
    return formatCaseDateTime(this.args.update?.created_at);
  }

  get isEdited() {
    return Boolean(this.args.update?.edited_at);
  }

  get editedTitle() {
    return formatCaseDateTime(this.args.update?.edited_at);
  }

  get editedLabel() {
    return i18n("atcp_case.cases.detail.progress.edited");
  }

  get updateTypeLabel() {
    return (
      String(this.args.update?.update_type ?? "").trim() ||
      i18n("atcp_case.cases.detail.edit_update.untitled_update")
    );
  }

  get editAriaLabel() {
    return i18n("atcp_case.cases.detail.edit_update.edit_aria", {
      type: this.updateTypeLabel,
      time: this.timeTitle,
    });
  }

  get deleteAriaLabel() {
    return i18n("atcp_case.cases.detail.edit_update.delete_aria", {
      type: this.updateTypeLabel,
      time: this.timeTitle,
    });
  }

  get editHistory() {
    return normalizeEditHistory(this.args.update?.details).map((version) => ({
      ...version,
      edited_at_label: formatCaseDateTime(version.edited_at),
      empty_version:
        !version.has_body &&
        !version.update_type &&
        !version.added_attachments.length &&
        !version.removed_attachments.length,
    }));
  }

  get systemText() {
    return systemEventText(this.args.update);
  }

  get hasBody() {
    return Boolean(String(this.args.update?.body ?? "").trim());
  }

  get attachments() {
    return (this.args.update?.attachments || []).map((attachment) => ({
      ...attachment,
      date: formatCaseDate(this.args.update?.created_at),
    }));
  }

  get fileCountLabel() {
    return i18n("atcp_case.cases.detail.progress.attachments", {
      count: this.attachments.length,
    });
  }

  get canEdit() {
    return Boolean(
      this.args.update?.can_edit && this.args.atcpCase?.status !== "Closed"
    );
  }

  get canDelete() {
    return Boolean(
      this.args.update?.can_delete && this.args.atcpCase?.status !== "Closed"
    );
  }

  get canShowActions() {
    return this.canEdit || this.canDelete;
  }

  get deleteConfirmationMessage() {
    return i18n(
      this.args.update?.is_system
        ? "atcp_case.cases.detail.edit_update.delete_system_confirmation"
        : "atcp_case.cases.detail.edit_update.delete_confirmation"
    );
  }

  get editButtonId() {
    return `atcp-case-update-edit-${this.args.update?.id}`;
  }

  @action
  startEditing() {
    this.args.onStartEdit?.();
  }

  @action
  finishEditing() {
    this.args.onStopEdit?.();
    next(() => {
      document.getElementById(this.editButtonId)?.focus();
    });
  }

  @action
  updateSaved() {
    this.finishEditing();
    this.a11y.announce(
      i18n("atcp_case.cases.detail.edit_update.announcement"),
      "polite"
    );
  }

  @action
  async deleteUpdate() {
    if (this.isDeleting) {
      return;
    }

    const confirmed = await this.dialog.deleteConfirm({
      message: this.deleteConfirmationMessage,
      confirmButtonLabel: "atcp_case.cases.detail.edit_update.delete",
    });

    if (!confirmed) {
      return;
    }

    this.isDeleting = true;

    try {
      await ajax(
        `/atcp/cases/${this.args.atcpCase?.id}/updates/${this.args.update?.id}.json`,
        { type: "DELETE" }
      );
      await this.router.refresh();
      this.a11y.announce(
        i18n("atcp_case.cases.detail.edit_update.deleted_announcement"),
        "polite"
      );
      this.#focusAddUpdate();
    } catch (error) {
      const status = error?.jqXHR?.status;

      if (status === 403) {
        await this.router.refresh();
        this.a11y.announce(
          i18n("atcp_case.cases.detail.edit_update.no_longer_editable"),
          "polite"
        );
        this.#focusAddUpdate();
      } else if (status === 404 || status === 422) {
        const announcement =
          status === 404
            ? i18n("atcp_case.cases.detail.edit_update.no_longer_exists")
            : this.#deleteErrorMessage(error.jqXHR?.responseJSON) ||
              i18n("atcp_case.cases.detail.edit_update.no_longer_exists");

        await this.router.refresh();
        this.a11y.announce(announcement, "polite");
        this.#focusAddUpdate();
      } else {
        popupAjaxError(error);
      }
    } finally {
      this.isDeleting = false;
    }
  }

  #deleteErrorMessage(payload) {
    const { fieldErrors, baseErrors } = normalizeCaseErrors(payload);

    return baseErrors[0] || Object.values(fieldErrors).flat()[0];
  }

  #focusAddUpdate() {
    next(() => {
      document
        .getElementById(`atcp-case-add-update-toggle-${this.args.atcpCase?.id}`)
        ?.focus();
    });
  }

  <template>
    <article class={{if @update.is_system "atcp-case-detail__system-update" "atcp-case-detail__update"}}>
      <span class="atcp-case-detail__update-icon" aria-hidden="true">
        {{#if @update.is_system}}
          {{dIcon "gear"}}
        {{else}}
          {{dIcon "user"}}
        {{/if}}
      </span>

      <div class={{if @update.is_system "atcp-case-detail__system-update-content" "atcp-case-detail__update-content"}}>
        <div class="atcp-case-detail__update-header">
          {{#if @update.is_system}}
            <p class="atcp-case-detail__system-update-text">
              {{this.systemText}}
            </p>

            {{#if this.isEdited}}
              <span
                class="atcp-case-detail__edited"
                title={{this.editedTitle}}
              >
                {{this.editedLabel}}
              </span>
            {{/if}}
          {{else}}
            <span class="atcp-case-detail__update-author">{{this.author}}</span>

            {{#if @update.update_type}}
              <span class="atcp-case-detail__update-type">
                {{@update.update_type}}
              </span>
            {{/if}}

            <time
              class="atcp-case-detail__update-time"
              datetime={{@update.created_at}}
              title={{this.timeTitle}}
            >
              {{this.relativeTime}}
            </time>

            {{#if this.isEdited}}
              <span
                class="atcp-case-detail__edited"
                title={{this.editedTitle}}
              >
                {{this.editedLabel}}
              </span>
            {{/if}}
          {{/if}}

          {{#if this.canShowActions}}
            {{#unless @isEditing}}
              <div class="atcp-case-detail__update-actions">
                {{#if this.canEdit}}
                  <button
                    id={{this.editButtonId}}
                    type="button"
                    class="btn btn-flat btn-small atcp-case-detail__update-action"
                    aria-label={{this.editAriaLabel}}
                    {{on "click" this.startEditing}}
                  >
                    {{i18n "atcp_case.cases.detail.edit_update.edit"}}
                  </button>
                {{/if}}

                {{#if this.canDelete}}
                  <button
                    type="button"
                    class="btn btn-flat btn-small atcp-case-detail__update-action atcp-case-detail__update-action--danger"
                    disabled={{this.isDeleting}}
                    aria-label={{this.deleteAriaLabel}}
                    {{on "click" this.deleteUpdate}}
                  >
                    {{i18n "atcp_case.cases.detail.edit_update.delete"}}
                  </button>
                {{/if}}
              </div>
            {{/unless}}
          {{/if}}
        </div>

        {{#if @isEditing}}
          <AtcpCaseDetailEditUpdate
            @update={{@update}}
            @atcpCase={{@atcpCase}}
            @bodyOnly={{@update.is_system}}
            @onCancel={{this.finishEditing}}
            @onSaved={{this.updateSaved}}
            @onDirtyChange={{@onDirtyChange}}
            @formOptions={{@formOptions}}
          />
        {{else if this.hasBody}}
          {{#if @update.is_system}}
            <p class="atcp-case-detail__pre-wrap atcp-case-detail__system-update-body">{{@update.body}}</p>
          {{else}}
            <p class="atcp-case-detail__update-body atcp-case-detail__pre-wrap">{{@update.body}}</p>
          {{/if}}
        {{/if}}

        {{#unless @update.is_system}}
          {{#if this.attachments.length}}
            <div class="atcp-case-detail__update-attachments">
              <span class="atcp-case-detail__attachment-count">
                {{this.fileCountLabel}}
              </span>

              <div class="atcp-case-detail__attachment-list">
                {{#each this.attachments as |attachment|}}
                  <a
                    class="atcp-case-detail__attachment"
                    href={{attachment.url}}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {{#if attachment.is_image}}
                      <img
                        class="atcp-case-detail__attachment-image"
                        src={{attachment.url}}
                        alt=""
                        loading="lazy"
                      />
                    {{/if}}

                    <span class="atcp-case-detail__attachment-name">
                      {{attachment.original_filename}}
                    </span>

                    {{#if attachment.human_filesize}}
                      <span class="atcp-case-detail__attachment-size">
                        {{attachment.human_filesize}}
                      </span>
                    {{/if}}
                  </a>
                {{/each}}
              </div>
            </div>
          {{/if}}
        {{/unless}}

        {{#if this.editHistory.length}}
          <details class="atcp-case-detail__history">
            <summary class="atcp-case-detail__history-summary">
              {{i18n
                "atcp_case.cases.detail.edit_update.previous_versions"
                count=this.editHistory.length
              }}
            </summary>

            <ol class="atcp-case-detail__history-list">
              {{#each this.editHistory as |version|}}
                <li class="atcp-case-detail__history-entry">
                  <div class="atcp-case-detail__history-meta">
                    <time datetime={{version.edited_at}}>
                      {{version.edited_at_label}}
                    </time>

                    {{#if version.update_type}}
                      <span class="atcp-case-detail__history-type">
                        {{version.update_type}}
                      </span>
                    {{/if}}
                  </div>

                  {{#if version.has_body}}
                    {{#if version.body}}
                      <p class="atcp-case-detail__history-body atcp-case-detail__pre-wrap">{{version.body}}</p>
                    {{/if}}
                  {{else if version.empty_version}}
                    <p class="atcp-case-detail__history-body atcp-case-detail__history-empty-version">{{i18n "atcp_case.cases.detail.edit_update.empty_version"}}</p>
                  {{/if}}

                  {{#each version.added_attachments as |filename|}}
                    <p class="atcp-case-detail__history-attachment">
                      {{i18n
                        "atcp_case.cases.detail.edit_update.added_attachment"
                        filename=filename
                      }}
                    </p>
                  {{/each}}

                  {{#each version.removed_attachments as |filename|}}
                    <p class="atcp-case-detail__history-attachment">
                      {{i18n
                        "atcp_case.cases.detail.edit_update.removed_attachment"
                        filename=filename
                      }}
                    </p>
                  {{/each}}
                </li>
              {{/each}}
            </ol>
          </details>
        {{/if}}
      </div>
    </article>
  </template>
}
