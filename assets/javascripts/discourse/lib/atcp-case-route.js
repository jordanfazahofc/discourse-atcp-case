import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";
import { forceAtcpSidebar } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-sidebar";

export default class AtcpCaseRoute extends DiscourseRoute {
  @service sidebarState;

  activate() {
    super.activate?.(...arguments);
    forceAtcpSidebar(this.sidebarState);
  }
}
