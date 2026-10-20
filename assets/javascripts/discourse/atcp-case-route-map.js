export default function () {
  this.route("atcp-cases", { path: "/internal/cases" }, function () {
    this.route("index", { path: "/" });
    this.route("show", { path: "/:case_id" });
  });
}
