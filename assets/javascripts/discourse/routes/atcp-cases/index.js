import { service } from "@ember/service";
import AtcpCaseRoute from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-route";

export default class AtcpCasesIndexRoute extends AtcpCaseRoute {
  @service router;
  @service currentUser;

  beforeModel() {
    if (!this.currentUser?.atcp_internal_access) {
      this.router.replaceWith("/");
    }
  }
}
