import Component from "@glimmer/component";
import { i18n } from "discourse-i18n";
import { caseStatusKey } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-list-params";

export default class AtcpCaseStatusBadge extends Component {
  get statusKey() {
    return caseStatusKey(this.args.status);
  }

  get label() {
    return i18n(`atcp_case.cases.statuses.${this.statusKey}`);
  }

  <template>
    <span class="atcp-case-status atcp-case-status--{{this.statusKey}}">
      {{this.label}}
    </span>
  </template>
}
