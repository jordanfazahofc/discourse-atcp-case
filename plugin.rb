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

  # Plugin kasus dimuat SEBELUM core, sedangkan guard dipakai di body class
  # controller (dievaluasi saat require) - muat lebih awal bila core belum
  # sempat mendefinisikannya. Pola sama dengan announcement/plugin.rb.
  unless defined?(Atcp::InternalAccess)
    require_relative "../discourse-atcp-core/lib/atcp_internal_access"
  end
  unless defined?(Atcp::InternalAccessGuard)
    require_relative "../discourse-atcp-core/lib/atcp_internal_access_guard"
  end

  require_relative "lib/atcp_case_timing"
  require_relative "lib/atcp_case_pic_directory"

  require_relative "app/serializers/atcp_case_list_item_serializer"
  require_relative "app/serializers/atcp_case_update_serializer"
  require_relative "app/serializers/atcp_case_serializer"
  require_relative "app/controllers/atcp/cases_controller"

  require_relative "lib/atcp_case_upload_patch"
  require_relative "lib/atcp_case_upload_validator_patch"

  reloadable_patch { UploadCreator.prepend(Atcp::CaseUploadPatch) }
  reloadable_patch { UploadValidator.prepend(Atcp::CaseUploadValidatorPatch) }

  Discourse::Application.routes.append do
    namespace :atcp, defaults: { format: :json } do
      resources :cases, only: %i[index show create] do
        collection do
          get :form_options
          get :pic_candidates
        end
      end
    end
  end
end
