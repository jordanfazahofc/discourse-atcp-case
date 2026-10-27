import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { array, fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import AtcpCaseDetailAddUpdate from "./add-update";
import AtcpCaseDetailUpdate from "./update";

export default class AtcpCaseDetailProgress extends Component {
  @service dialog;

  @tracked editingUpdateId = null;
  @tracked editingDirty = false;

  get activeEditingUpdateId() {
    return this.args.updates?.some(
      (update) => update.id === this.editingUpdateId
    )
      ? this.editingUpdateId
      : null;
  }

  @action
  async startEditing(update) {
    const currentId = this.activeEditingUpdateId;

    if (currentId === update.id) {
      return;
    }

    if (currentId && this.editingDirty) {
      const confirmed = await this.dialog.confirm({
        message: i18n(
          "atcp_case.cases.detail.edit_update.discard_unsaved"
        ),
        confirmButtonLabel: "atcp_case.cases.detail.edit_update.discard",
        cancelButtonLabel: "atcp_case.cases.detail.edit_update.keep_editing",
      });

      if (!confirmed) {
        return;
      }
    }

    this.editingUpdateId = update.id;
    this.editingDirty = false;
  }

  @action
  stopEditing(update) {
    if (this.editingUpdateId === update.id) {
      this.editingUpdateId = null;
      this.editingDirty = false;
    }
  }

  @action
  setEditingDirty(update, dirty) {
    if (this.editingUpdateId === update.id) {
      this.editingDirty = Boolean(dirty);
    }
  }

  <template>
  <section class="atcp-case-detail__progress">
    {{#each (array @atcpCase.id) as |caseId|}}
      <AtcpCaseDetailAddUpdate
        @caseId={{caseId}}
        @atcpCase={{@atcpCase}}
        @formOptions={{@formOptions}}
      />
    {{/each}}

    {{#if @updates.length}}
      <div class="atcp-case-detail__timeline">
        {{#each @updates as |update|}}
          <AtcpCaseDetailUpdate
            @update={{update}}
            @atcpCase={{@atcpCase}}
            @isEditing={{eq update.id this.activeEditingUpdateId}}
            @onStartEdit={{fn this.startEditing update}}
            @onStopEdit={{fn this.stopEditing update}}
            @onDirtyChange={{fn this.setEditingDirty update}}
            @formOptions={{@formOptions}}
          />
        {{/each}}
      </div>
    {{else}}
      <p class="atcp-case-detail__empty">
        {{i18n "atcp_case.cases.detail.progress.empty"}}
      </p>
    {{/if}}
  </section>
</template>
}
