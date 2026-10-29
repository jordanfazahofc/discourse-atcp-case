import Component from "@glimmer/component";
import { i18n } from "discourse-i18n";
import { formatCaseDate } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-detail";
import AtcpCaseAttachmentGallery from "./attachment-gallery";

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
        <AtcpCaseAttachmentGallery
          @attachments={{this.attachments}}
          @variant="rows"
          @onViewUpdate={{@onViewUpdate}}
        />
      {{else}}
        <p class="atcp-case-detail__empty">
          {{i18n "atcp_case.cases.detail.attachments.empty"}}
        </p>
      {{/if}}
    </section>
  </template>
}
