import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { eq, not } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

export default class AtcpCaseTechnicalFields extends Component {
  get frequencyOptions() {
    return this.args.frequencyOptions || [];
  }

  @action
  async updateSelect(field, event) {
    await field.set(event.target.value ?? "");
  }

  <template>
    <@form.Field
      @name="frequency"
      @title={{i18n "atcp_case.cases.detail.technical.frequency"}}
      @type="custom"
      as |field|
    >
      <field.Control>
        <select
          id={{field.id}}
          name={{field.name}}
          class="atcp-case-edit-technical-modal__select"
          value={{field.value}}
          aria-describedby={{field.describedBy}}
          aria-invalid={{if field.error "true"}}
          {{on "change" (fn this.updateSelect field)}}
        >
          <option value="" selected={{not field.value}}>
            {{i18n "atcp_case.cases.detail.technical.edit.not_set"}}
          </option>
          {{#each this.frequencyOptions as |frequencyOption|}}
            <option
              value={{frequencyOption}}
              selected={{eq field.value frequencyOption}}
            >
              {{frequencyOption}}
            </option>
          {{/each}}
        </select>
      </field.Control>
    </@form.Field>

    <@form.Field
      @name="non_trigger_conditions"
      @title={{i18n "atcp_case.cases.detail.technical.non_trigger_conditions"}}
      @type="textarea"
      @format="full"
      as |field|
    >
      <field.Control rows="5" />
    </@form.Field>

    <@form.Field
      @name="bios_version"
      @title={{i18n "atcp_case.cases.detail.technical.bios_version"}}
      @type="input"
      @format="full"
      as |field|
    >
      <field.Control maxlength="255" autocomplete="off" />
    </@form.Field>

    <@form.Field
      @name="os_driver_info"
      @title={{i18n "atcp_case.cases.detail.technical.os_driver_info"}}
      @type="textarea"
      @format="full"
      as |field|
    >
      <field.Control rows="5" />
    </@form.Field>
  </template>
}
