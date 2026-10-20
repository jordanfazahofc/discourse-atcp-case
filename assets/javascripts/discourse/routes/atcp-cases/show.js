import { service } from "@ember/service";
import AtcpCaseRoute from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-route";

export default class AtcpCasesShowRoute extends AtcpCaseRoute {
  @service router;
  @service currentUser;

  model(params) {
    return params.case_id;
  }

  beforeModel() {
    if (!this.currentUser?.atcp_internal_access) {
      this.router.replaceWith("/");
    }
  }
}
