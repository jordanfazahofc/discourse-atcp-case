import { on } from "@ember/modifier";
import { i18n } from "discourse-i18n";
import AtcpCaseSeverityBadge from "../atcp-case-severity-badge";
import AtcpCaseStatusBadge from "../atcp-case-status-badge";

<template>
  <header class="atcp-case-detail__header">
    <a
      href={{@returnURL}}
      class="atcp-case-detail__back"
      {{on "click" @onBack}}
    >
      <span aria-hidden="true">←</span>
      {{i18n "atcp_case.cases.detail.back_to_list"}}
    </a>

    <h1 class="atcp-case-detail__title">
      {{@atcpCase.case_number}}
      ·
      {{@atcpCase.title}}
    </h1>

    <div class="atcp-case-detail__meta">
      <AtcpCaseSeverityBadge @severity={{@atcpCase.severity}} />
      <AtcpCaseStatusBadge @status={{@atcpCase.status}} />

      {{#if @atcpCase.case_type}}
        <span class="atcp-case-detail__type">{{@atcpCase.case_type}}</span>
      {{/if}}

      {{#if @atcpCase.waiting}}
        <span class="atcp-case-detail__waiting">
          {{i18n
            "atcp_case.cases.waiting"
            label=@atcpCase.waiting.label
            days=@atcpCase.waiting.days
          }}
        </span>
      {{/if}}
    </div>
  </header>
</template>
