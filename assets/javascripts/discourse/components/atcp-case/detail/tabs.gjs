import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { i18n } from "discourse-i18n";

const NAVIGATION_KEYS = ["ArrowLeft", "ArrowRight", "Home", "End"];

export default class AtcpCaseDetailTabs extends Component {
  get tabs() {
    return (this.args.tabs || []).map((tab) => ({
      ...tab,
      active: tab.key === this.args.activeTab,
      tabId: `atcp-case-detail-tab-${tab.key}`,
      panelId: `atcp-case-detail-panel-${tab.key}`,
    }));
  }

  @action
  selectTab(tab, event) {
    event.preventDefault();
    this.args.onSelect?.(tab.key);
  }

  @action
  handleKeydown(event) {
    if (!NAVIGATION_KEYS.includes(event.key)) {
      return;
    }

    const buttons = Array.from(
      event.currentTarget.querySelectorAll('[role="tab"]')
    );
    const currentIndex = buttons.indexOf(event.target);

    if (currentIndex === -1) {
      return;
    }

    event.preventDefault();

    let nextIndex;
    if (event.key === "Home") {
      nextIndex = 0;
    } else if (event.key === "End") {
      nextIndex = buttons.length - 1;
    } else {
      const delta = event.key === "ArrowRight" ? 1 : -1;
      nextIndex = (currentIndex + delta + buttons.length) % buttons.length;
    }

    const nextButton = buttons[nextIndex];
    this.args.onSelect?.(nextButton.dataset.tab);
    nextButton.focus();
  }

  <template>
    <div
      class="atcp-case-detail__tabs"
      role="tablist"
      aria-label={{i18n "atcp_case.cases.detail.tabs.label"}}
      {{on "keydown" this.handleKeydown}}
    >
      {{#each this.tabs as |tab|}}
        <button
          id={{tab.tabId}}
          type="button"
          class="atcp-case-detail__tab
            {{if tab.active 'atcp-case-detail__tab--active'}}"
          role="tab"
          aria-selected={{if tab.active "true" "false"}}
          aria-controls={{tab.panelId}}
          tabindex={{if tab.active "0" "-1"}}
          data-tab={{tab.key}}
          {{on "click" (fn this.selectTab tab)}}
        >
          {{tab.label}}
        </button>
      {{/each}}
    </div>
  </template>
}
