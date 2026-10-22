import Component from "@glimmer/component";
import { i18n } from "discourse-i18n";

export default class AtcpCaseDetailResolution extends Component {
  get parts() {
    return [
      ["solution", "atcp_case.cases.detail.resolution.solution"],
      ["root_cause_summary", "atcp_case.cases.detail.resolution.root_cause"],
      ["workaround", "atcp_case.cases.detail.resolution.workaround"],
      ["conclusion", "atcp_case.cases.detail.resolution.conclusion"],
    ]
      .map(([field, translationKey]) => ({
        field,
        label: i18n(translationKey),
        value: this.args.atcpCase?.[field]?.trim(),
      }))
      .filter((part) => part.value);
  }

  <template>
    <section class="atcp-case-detail__resolution">
      <h2 class="atcp-case-detail__section-title">
        {{i18n "atcp_case.cases.detail.resolution.title"}}
      </h2>

      {{#each this.parts as |part|}}
        <div class="atcp-case-detail__resolution-part" data-field={{part.field}}>
          <h3>{{part.label}}</h3>
          <p class="atcp-case-detail__pre-wrap">{{part.value}}</p>
        </div>
      {{/each}}
    </section>
  </template>
}
