import { on } from "@ember/modifier";
import { i18n } from "discourse-i18n";

<template>
  <div class="atcp-case-detail__not-found">
    <a
      href={{@returnURL}}
      class="atcp-case-detail__back"
      {{on "click" @onBack}}
    >
      <span aria-hidden="true">←</span>
      {{i18n "atcp_case.cases.detail.back_to_list"}}
    </a>

    <h1>{{i18n "atcp_case.cases.detail.not_found"}}</h1>
  </div>
</template>
