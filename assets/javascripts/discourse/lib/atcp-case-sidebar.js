// Salinan lokal dari plugin shell: bundle plugin case tidak boleh bergantung
// pada bundle plugin shell saat boot (shell bisa dimatikan tanpa case).
export const ATCP_PANEL = "atcp";

export function forceAtcpSidebar(sidebarState) {
  // Panel "atcp" didaftarkan plugin shell; tanpa itu setPanel akan membuat
  // sidebar merender panel yang tidak ada.
  if (!sidebarState.panels?.some((panel) => panel.key === ATCP_PANEL)) {
    return;
  }

  sidebarState.isForcingSidebar = true;
  sidebarState.forcingSidebarPanel = ATCP_PANEL;
  sidebarState.setPanel(ATCP_PANEL);
  sidebarState.setSeparatedMode();
  sidebarState.hideSwitchPanelButtons();
}
