# frozen_string_literal: true

module Atcp
  class CasesController < ::ApplicationController
    include Atcp::InternalAccessGuard
    include AtcpCaseAttachmentUploads
    requires_plugin "discourse-atcp-case"

    before_action :ensure_logged_in
    before_action :ensure_internal_access!

    rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid

    DEFAULT_PER_PAGE = 20
    MAX_PER_PAGE = 100
    TITLE_MAX_LENGTH = 255
    TEXT_MAX_LENGTH = 255
    REOPEN_REASON_MAX_LENGTH = 2000
    JAKARTA_ZONE = "Asia/Jakarta"

    UPDATE_TEXT_FIELDS = %i[
      title
      case_type
      severity
      source
      symptom
      non_trigger_conditions
      os_driver_info
      root_cause_summary
      solution
      workaround
      conclusion
    ].freeze
    UPDATE_OPTIONAL_FIELDS = %i[bios_version frequency reproducibility].freeze

    def index
      status = params[:status].to_s.presence || "active"
      if status != "active" && AtcpCase::STATUSES.exclude?(status)
        return(
          render_json_error(
            I18n.t("atcp_case.errors.invalid_status"),
            status: 422
          )
        )
      end

      if invalid_id_filter?(:product_id) || invalid_id_filter?(:assignee_id)
        return(
          render_json_error(
            I18n.t("atcp_case.errors.invalid_filter"),
            status: 422
          )
        )
      end

      base_scope = filtered_scope
      return if base_scope.nil?

      page = page_param
      per_page = per_page_param

      scope =
        if status == "active"
          base_scope.where.not(status: "Closed")
        else
          base_scope.where(status: status)
        end

      total_count = scope.count
      cases =
        scope
          .includes(:atcp_case_products, :assignee, :atcp_case_updates)
          .order(opened_at: :desc, id: :desc)
          .offset((page - 1) * per_page)
          .limit(per_page)

      render json: {
               cases:
                 ActiveModel::ArraySerializer.new(
                   cases,
                   each_serializer: AtcpCaseListItemSerializer,
                   root: false
                 ).as_json,
               status_counts: status_counts(base_scope),
               total_count: total_count,
               page: page,
               per_page: per_page,
               total_pages: [(total_count.to_f / per_page).ceil, 1].max
             }
    end

    def show
      render json: { case: serialized_case(params[:id]) }
    end

    def form_options
      render json: {
               case_types: AtcpCase::CASE_TYPES,
               severities: AtcpCase::SEVERITIES,
               statuses: AtcpCase::STATUSES,
               close_reasons: AtcpCase::CLOSE_REASONS,
               frequencies: AtcpCase::FREQUENCIES,
               reproducibilities: AtcpCase::REPRODUCIBILITIES,
               upload: {
                 extensions:
                   SiteSetting.atcp_case_attachment_extensions.split("|"),
                 max_mb: SiteSetting.atcp_case_max_attachment_mb
               }
             }
    end

    def pic_candidates
      render json: { groups: AtcpCasePicDirectory.groups }
    end

    def create
      errors = create_validation_errors
      return render_errors(errors) if errors.any?

      atcp_case = nil
      begin
        ActiveRecord::Base.transaction do
          attrs = {
            title: title_param,
            case_type: params[:case_type].to_s,
            severity: params[:severity].to_s,
            source: source_param,
            symptom: params[:symptom].to_s.strip,
            assignee_id: assignee&.id,
            bios_version: params[:bios_version].to_s.strip.presence,
            status: "Open",
            opened_at: Time.zone.now,
            created_by_id: current_user.id
          }
          atcp_case = AtcpCase.create_with_generated_number!(attrs)

          create_case_products(atcp_case, products)

          if @validated_uploads.present?
            initial_report =
              atcp_case.atcp_case_updates.create!(
                user: current_user,
                is_system: false,
                update_type: AtcpCaseUpdate::INITIAL_REPORT_TYPE,
                body: nil,
                initial_report: true
              )
            attach_uploads(initial_report)
          end

          StaffActionLogger.new(current_user).log_custom(
            "atcp_case_created",
            details:
              "case_id: #{atcp_case.id}, case_number: #{atcp_case.case_number}"
          )
        end
      rescue AtcpCaseUpdateDuplicateAttachmentError => error
        return(
          render_errors(
            upload_ids: [
              I18n.t(
                "atcp_case.errors.attachment_already_used",
                filename: error.upload.original_filename
              )
            ]
          )
        )
      end

      render json: { case: serialized_case(atcp_case.id) }
    end

    def update
      atcp_case = find_case!
      unless atcp_case.manageable_by?(current_user)
        raise Discourse::InvalidAccess
      end
      if atcp_case.status == "Closed"
        return render_errors(base_error("case_closed"))
      end

      errors = update_validation_errors
      return render_errors(errors) if errors.any?

      locked_error = nil
      ActiveRecord::Base.transaction do
        atcp_case.with_lock do
          if atcp_case.status == "Closed"
            locked_error = base_error("case_closed")
            raise ActiveRecord::Rollback
          end

          previous_severity = atcp_case.severity
          previous_assignee_name = assignee_name(atcp_case.assignee)

          atcp_case.assign_attributes(editable_attributes)
          atcp_case.save!

          if params.key?(:product_ids)
            replace_case_products(atcp_case, products)
          end

          if atcp_case.severity != previous_severity
            create_system_update(
              atcp_case,
              "severity_changed",
              previous_severity,
              atcp_case.severity
            )
          end

          new_assignee_name = assignee_name(atcp_case.assignee)
          if new_assignee_name != previous_assignee_name
            create_system_update(
              atcp_case,
              "assignee_changed",
              previous_assignee_name,
              new_assignee_name
            )
          end
        end
      end
      return render_errors(locked_error) if locked_error

      render json: { case: serialized_case(atcp_case.id) }
    end

    def close
      atcp_case = find_case!
      unless atcp_case.manageable_by?(current_user)
        raise Discourse::InvalidAccess
      end
      if atcp_case.status == "Closed"
        return render_errors(base_error("already_closed"))
      end

      errors = close_validation_errors(atcp_case)
      return render_errors(errors) if errors.any?

      locked_error = nil
      ActiveRecord::Base.transaction do
        atcp_case.with_lock do
          if atcp_case.status == "Closed"
            locked_error = base_error("already_closed")
            raise ActiveRecord::Rollback
          end

          previous_status = atcp_case.status
          attrs = {
            status: "Closed",
            closed_at: Time.zone.now,
            close_reason: params[:close_reason].to_s.strip
          }
          if params.key?(:solution)
            attrs[:solution] = params[:solution].to_s.strip.presence
          end
          if params.key?(:root_cause_summary)
            attrs[:root_cause_summary] = params[:root_cause_summary]
              .to_s
              .strip
              .presence
          end
          if params.key?(:workaround)
            attrs[:workaround] = params[:workaround].to_s.strip.presence
          end
          if params.key?(:conclusion)
            attrs[:conclusion] = params[:conclusion].to_s.strip.presence
          end

          atcp_case.update!(attrs)

          create_system_update(
            atcp_case,
            "closed",
            previous_status,
            "Closed",
            details: {
              "close_reason" => atcp_case.close_reason
            }
          )
        end
      end
      return render_errors(locked_error) if locked_error

      render json: { case: serialized_case(atcp_case.id) }
    end

    def reopen
      atcp_case = find_case!
      unless atcp_case.manageable_by?(current_user)
        raise Discourse::InvalidAccess
      end
      unless atcp_case.status == "Closed"
        return render_errors(base_error("not_closed"))
      end

      reason = params[:reason].to_s.strip
      errors = {}
      if reason.blank?
        errors[:reason] = [I18n.t("atcp_case.errors.reopen_reason_required")]
      elsif reason.length > REOPEN_REASON_MAX_LENGTH
        errors[:reason] = [I18n.t("atcp_case.errors.reopen_reason_too_long")]
      end
      return render_errors(errors) if errors.any?

      locked_error = nil
      ActiveRecord::Base.transaction do
        atcp_case.with_lock do
          unless atcp_case.status == "Closed"
            locked_error = base_error("not_closed")
            raise ActiveRecord::Rollback
          end

          previous_closed_at = atcp_case.closed_at
          previous_close_reason = atcp_case.close_reason

          atcp_case.update!(
            status: "In Progress",
            closed_at: nil,
            close_reason: nil
          )

          create_system_update(
            atcp_case,
            "reopened",
            "Closed",
            "In Progress",
            body: reason,
            details: {
              "previous_closed_at" => previous_closed_at,
              "previous_close_reason" => previous_close_reason
            }
          )
        end
      end
      return render_errors(locked_error) if locked_error

      render json: { case: serialized_case(atcp_case.id) }
    end

    private

    def case_scope
      AtcpCase.includes(
        :atcp_case_products,
        :assignee,
        :created_by,
        atcp_case_updates: [:user, { atcp_case_attachments: :upload }]
      )
    end

    def find_case!
      AtcpCase.find_by(id: params[:id]) || raise(Discourse::NotFound)
    end

    def serialized_case(id)
      atcp_case = case_scope.find_by(id: id) || raise(Discourse::NotFound)
      AtcpCaseSerializer.new(
        atcp_case,
        scope: current_user.guardian,
        root: false
      ).as_json
    end

    def render_errors(errors)
      render json: { errors: errors }, status: :unprocessable_entity
    end

    def render_record_invalid(exception)
      errors = exception.record ? exception.record.errors.messages : {}
      errors = { base: [exception.message] } if errors.empty?
      render json: { errors: errors }, status: :unprocessable_entity
    end

    def base_error(key)
      { base: [I18n.t("atcp_case.errors.#{key}")] }
    end

    def page_param
      value = params[:page].to_s
      return 1 unless value.match?(/\A\d+\z/)

      [value.to_i, 1].max
    end

    def per_page_param
      value = params[:per_page].to_s
      return DEFAULT_PER_PAGE if value.blank? || !value.match?(/\A\d+\z/)

      number = value.to_i
      return DEFAULT_PER_PAGE if number < 1

      [number, MAX_PER_PAGE].min
    end

    def invalid_id_filter?(key)
      raw = params[key]
      raw.present? && !raw.to_s.match?(/\A\d+\z/)
    end

    def filtered_scope
      scope = AtcpCase.all
      severity = params[:severity].to_s
      scope = scope.where(severity: severity) if severity.present?
      case_type = params[:case_type].to_s
      scope = scope.where(case_type: case_type) if case_type.present?
      if params[:product_id].present?
        scope =
          scope.joins(:atcp_case_products).where(
            atcp_case_products: {
              product_id: params[:product_id].to_s.to_i
            }
          )
      end
      if params[:assignee_id].present?
        scope = scope.where(assignee_id: params[:assignee_id].to_s.to_i)
      end

      scope = search_scope(scope)
      apply_date_filters(scope)
    end

    def search_scope(scope)
      query = params[:q].to_s.strip
      return scope if query.blank?

      pattern = "%#{query.gsub(/[\\%_]/) { |character| "\\#{character}" }}%"
      scope.where(
        "atcp_cases.case_number ILIKE :pattern ESCAPE '\\' " \
          "OR atcp_cases.title ILIKE :pattern ESCAPE '\\' " \
          "OR atcp_cases.symptom ILIKE :pattern ESCAPE '\\'",
        pattern: pattern
      )
    end

    def apply_date_filters(scope)
      from = parse_iso_date(params[:date_from])
      return nil if from == :invalid
      to = parse_iso_date(params[:date_to])
      return nil if to == :invalid

      if from && to && from > to
        render_json_error(
          I18n.t("atcp_case.errors.date_range_invalid"),
          status: 422
        )
        return nil
      end

      zone = ActiveSupport::TimeZone[JAKARTA_ZONE]
      if from
        scope =
          scope.where(opened_at: zone.local(from.year, from.month, from.day)..)
      end
      if to
        next_day = zone.local(to.year, to.month, to.day) + 1.day
        scope = scope.where(opened_at: ...next_day)
      end
      scope
    end

    def parse_iso_date(raw)
      value = raw.to_s.strip
      return nil if value.blank?

      Date.iso8601(value)
    rescue Date::Error
      render_json_error(I18n.t("atcp_case.errors.date_invalid"), status: 422)
      :invalid
    end

    def status_counts(base_scope)
      counts = base_scope.group("atcp_cases.status").count
      {
        :active => counts.except("Closed").values.sum,
        "Open" => counts.fetch("Open", 0),
        "In Progress" => counts.fetch("In Progress", 0),
        "On Hold" => counts.fetch("On Hold", 0),
        "Solution Found" => counts.fetch("Solution Found", 0),
        "Closed" => counts.fetch("Closed", 0)
      }
    end

    def create_validation_errors
      errors = {}

      if title_param.blank?
        errors[:title] = [I18n.t("atcp_case.errors.title_required")]
      elsif title_param.length > TITLE_MAX_LENGTH
        errors[:title] = [I18n.t("atcp_case.errors.title_too_long")]
      end

      if AtcpCase::CASE_TYPES.exclude?(params[:case_type].to_s)
        errors[:case_type] = [I18n.t("atcp_case.errors.case_type_invalid")]
      end

      if AtcpCase::SEVERITIES.exclude?(params[:severity].to_s)
        errors[:severity] = [I18n.t("atcp_case.errors.severity_invalid")]
      end

      if source_param.blank?
        errors[:source] = [I18n.t("atcp_case.errors.source_required")]
      elsif source_param.length > TEXT_MAX_LENGTH
        errors[:source] = [I18n.t("atcp_case.errors.source_too_long")]
      end

      if params[:symptom].to_s.strip.blank?
        errors[:symptom] = [I18n.t("atcp_case.errors.symptom_required")]
      end

      if params[:bios_version].to_s.strip.length > TEXT_MAX_LENGTH
        errors[:bios_version] = [
          I18n.t("atcp_case.errors.bios_version_too_long")
        ]
      end

      if params.key?(:upload_ids)
        @validated_uploads, @upload_errors = validated_uploads
        errors[:upload_ids] = @upload_errors if @upload_errors.any?
      end

      product_error = product_validation_error
      errors[:product_ids] = [product_error] if product_error

      if params[:assignee_id].present? && assignee.nil?
        errors[:assignee_id] = [I18n.t("atcp_case.errors.assignee_invalid")]
      end

      errors
    end

    def update_validation_errors
      errors = {}

      if params.key?(:title)
        title = params[:title].to_s.strip
        if title.blank?
          errors[:title] = [I18n.t("atcp_case.errors.title_required")]
        elsif title.length > TITLE_MAX_LENGTH
          errors[:title] = [I18n.t("atcp_case.errors.title_too_long")]
        end
      end

      if params.key?(:case_type) &&
           AtcpCase::CASE_TYPES.exclude?(params[:case_type].to_s)
        errors[:case_type] = [I18n.t("atcp_case.errors.case_type_invalid")]
      end

      if params.key?(:severity) &&
           AtcpCase::SEVERITIES.exclude?(params[:severity].to_s)
        errors[:severity] = [I18n.t("atcp_case.errors.severity_invalid")]
      end

      if params.key?(:source)
        source = params[:source].to_s.strip
        if source.blank?
          errors[:source] = [I18n.t("atcp_case.errors.source_required")]
        elsif source.length > TEXT_MAX_LENGTH
          errors[:source] = [I18n.t("atcp_case.errors.source_too_long")]
        end
      end

      if params.key?(:symptom) && params[:symptom].to_s.strip.blank?
        errors[:symptom] = [I18n.t("atcp_case.errors.symptom_required")]
      end

      if params.key?(:bios_version) &&
           params[:bios_version].to_s.strip.length > TEXT_MAX_LENGTH
        errors[:bios_version] = [
          I18n.t("atcp_case.errors.bios_version_too_long")
        ]
      end

      if params.key?(:frequency)
        frequency = params[:frequency].to_s.strip
        if frequency.present? && AtcpCase::FREQUENCIES.exclude?(frequency)
          errors[:frequency] = [I18n.t("atcp_case.errors.frequency_invalid")]
        end
      end

      if params.key?(:reproducibility)
        reproducibility = params[:reproducibility].to_s.strip
        if reproducibility.present? &&
             AtcpCase::REPRODUCIBILITIES.exclude?(reproducibility)
          errors[:reproducibility] = [
            I18n.t("atcp_case.errors.reproducibility_invalid")
          ]
        end
      end

      if params.key?(:assignee_id) && params[:assignee_id].present? &&
           assignee_for(params[:assignee_id]).nil?
        errors[:assignee_id] = [I18n.t("atcp_case.errors.assignee_invalid")]
      end

      if params.key?(:product_ids)
        product_error = product_validation_error
        errors[:product_ids] = [product_error] if product_error
      end

      errors
    end

    def close_validation_errors(atcp_case)
      errors = {}
      reason = params[:close_reason].to_s.strip

      if reason.blank?
        errors[:close_reason] = [
          I18n.t("atcp_case.errors.close_reason_required")
        ]
      elsif AtcpCase::CLOSE_REASONS.exclude?(reason)
        errors[:close_reason] = [
          I18n.t("atcp_case.errors.close_reason_invalid")
        ]
      end

      if reason == "Resolved" && !errors.key?(:close_reason)
        effective_solution =
          if params.key?(:solution)
            params[:solution].to_s.strip
          else
            atcp_case.solution.to_s
          end
        if effective_solution.blank?
          errors[:solution] = [I18n.t("atcp_case.errors.solution_required")]
        end
      end

      errors
    end

    def editable_attributes
      attrs = {}

      UPDATE_TEXT_FIELDS.each do |field|
        next unless params.key?(field)
        attrs[field] = params[field].to_s.strip.presence
      end

      UPDATE_OPTIONAL_FIELDS.each do |field|
        next unless params.key?(field)
        attrs[field] = params[field].to_s.strip.presence
      end

      if params.key?(:assignee_id)
        attrs[:assignee_id] = assignee_for(params[:assignee_id])&.id
      end

      attrs
    end

    def create_case_products(atcp_case, selected_products)
      selected_products.each do |product|
        AtcpCaseProduct.create!(
          case_id: atcp_case.id,
          product_id: product.id,
          product_name: product.name,
          sku_code: product.sku_code
        )
      end
    end

    # Pengganti penuh: produk lama yang tetap dipilih mempertahankan snapshot
    # lamanya, produk yang dihapus dari daftar ikut dihapus, produk baru
    # dibuat dengan snapshot saat ini.
    def replace_case_products(atcp_case, selected_products)
      keep_ids = selected_products.map(&:id)
      atcp_case.atcp_case_products.where.not(product_id: keep_ids).delete_all

      existing_ids = atcp_case.atcp_case_products.pluck(:product_id)
      selected_products.each do |product|
        next if existing_ids.include?(product.id)

        AtcpCaseProduct.create!(
          case_id: atcp_case.id,
          product_id: product.id,
          product_name: product.name,
          sku_code: product.sku_code
        )
      end
    end

    def create_system_update(
      atcp_case,
      event,
      from_value,
      to_value,
      body: nil,
      details: {}
    )
      atcp_case.atcp_case_updates.create!(
        user: current_user,
        is_system: true,
        update_type: nil,
        system_event: event,
        from_value: from_value,
        to_value: to_value,
        body: body,
        details: details
      )
    end

    def assignee_name(user)
      user&.username || "Unassigned"
    end

    def title_param
      params[:title].to_s.strip
    end

    def source_param
      params[:source].to_s.strip
    end

    def requested_product_ids
      @requested_product_ids ||=
        Array(params[:product_ids])
          .map { |value| value.to_s.strip }
          .reject(&:blank?)
          .uniq
    end

    def products
      @products ||= AtcpProduct.where(id: requested_product_ids).to_a
    end

    def product_validation_error
      if requested_product_ids.empty?
        return I18n.t("atcp_case.errors.products_required")
      end

      numeric_ids = requested_product_ids.select { |id| id.match?(/\A\d+\z/) }
      if numeric_ids.size != requested_product_ids.size
        return I18n.t("atcp_case.errors.products_unknown")
      end
      if products.size != numeric_ids.size
        return I18n.t("atcp_case.errors.products_unknown")
      end

      nil
    end

    def assignee_for(raw)
      return nil if raw.blank?
      return nil unless raw.to_s.match?(/\A\d+\z/)

      user = User.find_by(id: raw.to_i)
      user if AtcpCasePicDirectory.candidate?(user)
    end

    def assignee
      return @assignee if defined?(@assignee)

      @assignee = assignee_for(params[:assignee_id])
    end
  end
end
