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
  relativeCaseTime,
  systemEventText,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-detail";
import AtcpCaseDetailEditUpdate from "./edit-update";

export default class AtcpCaseDetailUpdate extends Component {
  @service a11y;
  @service currentUser;
  @service dialog;
  @service router;

  @tracked isDeleting = false;
  @tracked isEditing = false;

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

  get systemText() {
    return systemEventText(this.args.update);
  }

  get showReopenedBody() {
    return (
      this.args.update?.system_event === "reopened" &&
      Boolean(this.args.update?.body?.trim())
    );
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

  get canModify() {
    return (
      !this.args.update?.is_system && this.args.atcpCase?.status !== "Closed"
    );
  }

  get canDelete() {
    return this.canModify && this.currentUser?.admin;
  }

  get editButtonId() {
    return `atcp-case-update-edit-${this.args.update?.id}`;
  }

  @action
  startEditing() {
    this.isEditing = true;
  }

  @action
  finishEditing() {
    this.isEditing = false;
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
      message: i18n(
        "atcp_case.cases.detail.edit_update.delete_confirmation"
      ),
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
      next(() => {
        document
          .getElementById(`atcp-case-add-update-toggle-${this.args.atcpCase?.id}`)
          ?.focus();
      });
    } catch (error) {
      if (error?.jqXHR?.status === 422) {
        await this.router.refresh();
      } else {
        popupAjaxError(error);
      }
    } finally {
      this.isDeleting = false;
    }
  }

  <template>
    {{#if @update.is_system}}
      <div class="atcp-case-detail__system-update">
        <span class="atcp-case-detail__update-icon" aria-hidden="true">
          {{dIcon "gear"}}
        </span>
        <div class="atcp-case-detail__system-update-content">
          <p class="atcp-case-detail__system-update-text">
            {{this.systemText}}
          </p>
          {{#if this.showReopenedBody}}
            <p class="atcp-case-detail__pre-wrap atcp-case-detail__system-update-body">
              {{@update.body}}
            </p>
          {{/if}}
        </div>
      </div>
    {{else}}
      <article class="atcp-case-detail__update">
        <span class="atcp-case-detail__update-icon" aria-hidden="true">
          {{dIcon "user"}}
        </span>

        <div class="atcp-case-detail__update-content">
          <div class="atcp-case-detail__update-header">
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

            {{#if this.canModify}}
              {{#unless this.isEditing}}
                <div class="atcp-case-detail__update-actions">
                  <button
                    id={{this.editButtonId}}
                    type="button"
                    class="btn btn-flat btn-small atcp-case-detail__update-action"
                    {{on "click" this.startEditing}}
                  >
                    {{i18n "atcp_case.cases.detail.edit_update.edit"}}
                  </button>
                  {{#if this.canDelete}}
                    <button
                      type="button"
                      class="btn btn-flat btn-small atcp-case-detail__update-action atcp-case-detail__update-action--danger"
                      disabled={{this.isDeleting}}
                      {{on "click" this.deleteUpdate}}
                    >
                      {{i18n "atcp_case.cases.detail.edit_update.delete"}}
                    </button>
                  {{/if}}
                </div>
              {{/unless}}
            {{/if}}
          </div>

          {{#if this.isEditing}}
            <AtcpCaseDetailEditUpdate
              @update={{@update}}
              @atcpCase={{@atcpCase}}
              @formOptions={{@formOptions}}
              @onCancel={{this.finishEditing}}
              @onSaved={{this.updateSaved}}
            />
          {{else if @update.body}}
            <p class="atcp-case-detail__update-body atcp-case-detail__pre-wrap">
              {{@update.body}}
            </p>
          {{/if}}

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
        </div>
      </article>
    {{/if}}
  </template>
}
