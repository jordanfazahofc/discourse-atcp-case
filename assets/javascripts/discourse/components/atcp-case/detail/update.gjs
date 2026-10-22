import Component from "@glimmer/component";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import {
  displayUserName,
  formatCaseDate,
  formatCaseDateTime,
  relativeCaseTime,
  systemEventText,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-detail";

export default class AtcpCaseDetailUpdate extends Component {
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
          </div>

          {{#if @update.body}}
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
