import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import { formatCaseDate } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-detail";

export default class AtcpCaseDetailAttachments extends Component {
  get attachments() {
    return (this.args.attachments || []).map((attachment) => ({
      ...attachment,
      date: formatCaseDate(attachment.created_at),
    }));
  }

  <template>
    <section class="atcp-case-detail__attachments">
      {{#if this.attachments.length}}
        <ul class="atcp-case-detail__attachment-table">
          {{#each this.attachments as |attachment|}}
            <li class="atcp-case-detail__attachment-row">
              <a
                class="atcp-case-detail__attachment-preview"
                href={{attachment.url}}
                target="_blank"
                rel="noopener noreferrer"
              >
                {{#if attachment.is_image}}
                  <img
                    class="atcp-case-detail__attachment-thumbnail"
                    src={{attachment.url}}
                    alt=""
                    loading="lazy"
                  />
                {{else}}
                  <span class="atcp-case-detail__attachment-file" aria-hidden="true">
                    {{dIcon "file"}}
                  </span>
                {{/if}}
              </a>

              <div class="atcp-case-detail__attachment-details">
                <a
                  class="atcp-case-detail__attachment-link"
                  href={{attachment.url}}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {{attachment.original_filename}}
                </a>

                <span class="atcp-case-detail__attachment-meta">
                  {{#if attachment.human_filesize}}
                    {{attachment.human_filesize}}
                    ·
                  {{/if}}
                  {{attachment.uploaded_by}}
                  ·
                  {{attachment.date}}
                </span>
              </div>

              <button
                type="button"
                class="btn btn-link atcp-case-detail__attachment-view"
                {{on "click" @onViewUpdate}}
              >
                {{i18n "atcp_case.cases.detail.attachments.view_update"}}
              </button>
            </li>
          {{/each}}
        </ul>
      {{else}}
        <p class="atcp-case-detail__empty">
          {{i18n "atcp_case.cases.detail.attachments.empty"}}
        </p>
      {{/if}}
    </section>
  </template>
}
