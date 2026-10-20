import AtcpCasesController from "discourse/plugins/discourse-atcp-case/discourse/controllers/atcp-cases";

export default class AtcpCasesIndexController extends AtcpCasesController {
  queryParams = [
    "status",
    "q",
    "severity",
    "case_type",
    "product_id",
    "assignee_id",
    "date_from",
    "date_to",
    "page",
  ];
}
