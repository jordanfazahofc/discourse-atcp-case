import AtcpCaseDetail from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/detail";

<template>
  <AtcpCaseDetail
    @atcpCase={{@model.case}}
    @error={{@model.error}}
    @formOptions={{@model.formOptions}}
    @picGroups={{@model.picGroups}}
    @activeTab={{@controller.tab}}
    @onSelectTab={{@controller.selectTab}}
  />
</template>
