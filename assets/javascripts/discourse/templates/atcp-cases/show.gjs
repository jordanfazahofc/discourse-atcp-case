import AtcpCaseDetail from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/detail";

<template>
  <AtcpCaseDetail
    @atcpCase={{@model.case}}
    @error={{@model.error}}
    @activeTab={{@controller.tab}}
    @onSelectTab={{@controller.selectTab}}
  />
</template>
