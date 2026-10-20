// Salinan lokal dari plugin shell: bundle plugin case tidak boleh bergantung
// pada bundle plugin shell saat boot (shell bisa dimatikan tanpa case).
export const ATCP_PANEL = "atcp";

export function forceAtcpSidebar(sidebarState) {
  sidebarState.isForcingSidebar = true;
  sidebarState.forcingSidebarPanel = ATCP_PANEL;
  sidebarState.setPanel(ATCP_PANEL);
  sidebarState.setSeparatedMode();
  sidebarState.hideSwitchPanelButtons();
}
