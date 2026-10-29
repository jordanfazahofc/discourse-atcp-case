import Component from "@glimmer/component";
import { concat } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import lightbox from "discourse/lib/lightbox";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class AtcpCaseAttachmentGallery extends Component {
  get variant() {
    return this.args.variant || "inline";
  }

  get isRows() {
    return this.variant === "rows";
  }

  get isSummary() {
    return this.variant === "summary";
  }

  get attachments() {
    return this.args.attachments || [];
  }

  get galleryKey() {
    return this.attachments
      .map(
        (attachment) =>
          attachment.id ??
          attachment.upload_id ??
          attachment.original_filename ??
          attachment.url
      )
      .join("|");
  }

  get galleryEntries() {
    return [{ key: this.galleryKey }];
  }

  get listClass() {
    return this.isSummary
      ? "atcp-case-attachment-gallery__list"
      : "atcp-case-detail__attachment-list";
  }

  get itemClass() {
    return this.isSummary
      ? "atcp-case-attachment-gallery__item"
      : "atcp-case-detail__attachment";
  }

  get nameClass() {
    return this.isSummary
      ? "atcp-case-attachment-gallery__name"
      : "atcp-case-detail__attachment-name";
  }

  get sizeClass() {
    return this.isSummary
      ? "atcp-case-attachment-gallery__size"
      : "atcp-case-detail__attachment-size";
  }

  get imageClass() {
    return this.isSummary
      ? "atcp-case-attachment-gallery__image"
      : "atcp-case-detail__attachment-image";
  }

  @action
  setupLightbox(element) {
    lightbox(element);
  }

  <template>
    {{#each this.galleryEntries key="key" as |gallery|}}
      <div
        class="atcp-case-attachment-gallery atcp-case-attachment-gallery--{{this.variant}}"
        data-gallery-key={{gallery.key}}
        {{didInsert this.setupLightbox}}
      >
        {{#if this.isRows}}
          <ul class="atcp-case-detail__attachment-table">
            {{#each this.attachments as |attachment|}}
              <li class="atcp-case-detail__attachment-row">
                <a
                  class={{concat
                    "atcp-case-detail__attachment-preview"
                    (if attachment.is_image " lightbox")
                  }}
                  href={{attachment.url}}
                  target="_blank"
                  rel="noopener noreferrer"
                  title={{attachment.original_filename}}
                  data-large-src={{if
                    attachment.is_image
                    attachment.url
                  }}
                  data-orig-src={{if attachment.is_image attachment.url}}
                  data-download-href={{if
                    attachment.is_image
                    attachment.url
                  }}
                >
                  {{#if attachment.is_image}}
                    <img
                      class="atcp-case-detail__attachment-thumbnail"
                      src={{attachment.url}}
                      alt={{attachment.original_filename}}
                      loading="lazy"
                    />
                  {{else}}
                    <span
                      class="atcp-case-detail__attachment-file"
                      aria-hidden="true"
                    >
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

                {{#if @onViewUpdate}}
                  <button
                    type="button"
                    class="btn btn-link atcp-case-detail__attachment-view"
                    {{on "click" @onViewUpdate}}
                  >
                    {{i18n "atcp_case.cases.detail.attachments.view_update"}}
                  </button>
                {{/if}}
              </li>
            {{/each}}
          </ul>
        {{else}}
          <div class={{this.listClass}}>
            {{#each this.attachments as |attachment|}}
              <a
                class={{concat
                  this.itemClass
                  (if attachment.is_image " lightbox")
                }}
                href={{attachment.url}}
                target="_blank"
                rel="noopener noreferrer"
                title={{attachment.original_filename}}
                data-large-src={{if attachment.is_image attachment.url}}
                data-orig-src={{if attachment.is_image attachment.url}}
                data-download-href={{if attachment.is_image attachment.url}}
              >
                {{#if attachment.is_image}}
                  <img
                    class={{this.imageClass}}
                    src={{attachment.url}}
                    alt={{attachment.original_filename}}
                    loading="lazy"
                  />
                {{else if this.isSummary}}
                  <span
                    class="atcp-case-attachment-gallery__icon"
                    aria-hidden="true"
                  >
                    {{dIcon "file"}}
                  </span>
                {{/if}}

                <span class={{this.nameClass}}>
                  {{attachment.original_filename}}
                </span>

                {{#if attachment.human_filesize}}
                  <span class={{this.sizeClass}}>
                    {{attachment.human_filesize}}
                  </span>
                {{/if}}
              </a>
            {{/each}}
          </div>
        {{/if}}
      </div>
    {{/each}}
  </template>
}
