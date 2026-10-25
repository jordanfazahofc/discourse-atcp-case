import { array } from "@ember/helper";
import { i18n } from "discourse-i18n";
import AtcpCaseDetailAddUpdate from "./add-update";
import AtcpCaseDetailUpdate from "./update";

<template>
  <section class="atcp-case-detail__progress">
    {{#each (array @atcpCase.id) as |caseId|}}
      <AtcpCaseDetailAddUpdate
        @caseId={{caseId}}
        @atcpCase={{@atcpCase}}
        @formOptions={{@formOptions}}
      />
    {{/each}}

    {{#if @updates.length}}
      <div class="atcp-case-detail__timeline">
        {{#each @updates as |update|}}
          <AtcpCaseDetailUpdate
            @update={{update}}
            @atcpCase={{@atcpCase}}
            @formOptions={{@formOptions}}
          />
        {{/each}}
      </div>
    {{else}}
      <p class="atcp-case-detail__empty">
        {{i18n "atcp_case.cases.detail.progress.empty"}}
      </p>
    {{/if}}
  </section>
</template>
