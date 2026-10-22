import { tracked } from "@glimmer/tracking";
import Service from "@ember/service";

export const CASE_LIST_URL = "/internal/cases";

function isSafeCaseListUrl(value) {
  if (typeof value !== "string") {
    return false;
  }

  if (value !== CASE_LIST_URL && !value.startsWith(`${CASE_LIST_URL}?`)) {
    return false;
  }

  if (value.includes("//") || /^[a-z][a-z0-9+.-]*:/i.test(value)) {
    return false;
  }

  return true;
}

export default class AtcpCaseReturnUrl extends Service {
  @tracked _url = CASE_LIST_URL;

  get url() {
    return isSafeCaseListUrl(this._url) ? this._url : CASE_LIST_URL;
  }

  set url(value) {
    if (isSafeCaseListUrl(value)) {
      this._url = value;
    }
  }

  remember(url) {
    if (isSafeCaseListUrl(url)) {
      this._url = url;
    }
  }
}
