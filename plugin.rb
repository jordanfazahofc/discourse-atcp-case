# frozen_string_literal: true

# name: discourse-atcp-case
# about: ATCP Case Management - structured, product-centric case lifecycle built on Discourse
# meta_topic_id:
# version: 0.1.0
# authors: Axioo Technical Community Platform Team
# url: (internal - permanent fork, not published)

enabled_site_setting :atcp_case_enabled

after_initialize do
  require_relative "app/models/atcp_case"
  require_relative "app/models/atcp_case_product"
  require_relative "app/models/atcp_case_update"
  require_relative "app/models/atcp_case_attachment"

  require_relative "lib/atcp_case_upload_patch"
  require_relative "lib/atcp_case_upload_validator_patch"

  reloadable_patch { UploadCreator.prepend(Atcp::CaseUploadPatch) }
  reloadable_patch { UploadValidator.prepend(Atcp::CaseUploadValidatorPatch) }
end
