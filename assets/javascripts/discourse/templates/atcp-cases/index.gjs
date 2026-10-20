import AtcpCaseList from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/atcp-case-list";

export default <template>
  <AtcpCaseList
    @list={{@model.list}}
    @error={{@model.error}}
    @formOptions={{@model.formOptions}}
    @picGroups={{@model.picGroups}}
    @filters={{@controller.filters}}
    @isLoading={{@controller.isLoading}}
    @onStatusChange={{@controller.setStatus}}
    @onSearch={{@controller.search}}
    @onFilterChange={{@controller.setFilter}}
    @onDateChange={{@controller.setFilter}}
    @onClearFilters={{@controller.clearFilters}}
    @onPageChange={{@controller.setPage}}
    @onOpenCase={{@controller.openCase}}
  />
</template>
