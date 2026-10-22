import Component from "@glimmer/component";
import { i18n } from "discourse-i18n";

const NOT_PROVIDED_KEY = "atcp_case.cases.detail.technical.not_provided";

export default class AtcpCaseDetailTechnical extends Component {
  get fields() {
    return [
      ["symptom", "atcp_case.cases.detail.technical.symptom"],
      ["frequency", "atcp_case.cases.detail.technical.frequency"],
      ["reproducibility", "atcp_case.cases.detail.technical.reproducibility"],
      [
        "non_trigger_conditions",
        "atcp_case.cases.detail.technical.non_trigger_conditions",
      ],
      ["bios_version", "atcp_case.cases.detail.technical.bios_version"],
      ["os_driver_info", "atcp_case.cases.detail.technical.os_driver_info"],
    ].map(([field, translationKey]) => {
      const value = this.args.atcpCase?.[field]?.trim();

      return {
        field,
        label: i18n(translationKey),
        value,
        isEmpty: !value,
      };
    });
  }

  get notProvided() {
    return i18n(NOT_PROVIDED_KEY);
  }

  <template>
    <section class="atcp-case-detail__technical">
      <dl class="atcp-case-detail__technical-list">
        {{#each this.fields as |field|}}
          <div class="atcp-case-detail__technical-item" data-field={{field.field}}>
            <dt>{{field.label}}</dt>
            <dd class={{if field.isEmpty "atcp-case-detail__muted"}}>
              {{#if field.isEmpty}}
                {{this.notProvided}}
              {{else}}
                <span class="atcp-case-detail__pre-wrap">{{field.value}}</span>
              {{/if}}
            </dd>
          </div>
        {{/each}}
      </dl>
    </section>
  </template>
}
