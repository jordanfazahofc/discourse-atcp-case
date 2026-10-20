import Component from "@glimmer/component";
import { i18n } from "discourse-i18n";
import { caseSeverityKey } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-list-params";

export default class AtcpCaseSeverityBadge extends Component {
  get severityKey() {
    return caseSeverityKey(this.args.severity);
  }

  get label() {
    return i18n(`atcp_case.cases.severities.${this.severityKey}`);
  }

  <template>
    <span class="atcp-case-severity atcp-case-severity--{{this.severityKey}}">
      {{this.label}}
    </span>
  </template>
}
