# frozen_string_literal: true

module Atcp
  class CasesController < ::ApplicationController
    include Atcp::InternalAccessGuard
    requires_plugin "discourse-atcp-case"

    before_action :ensure_logged_in
    before_action :ensure_internal_access!

    def index
      page = [params[:page].to_i, 1].max
      per_page =
        (
          if params[:per_page].blank?
            20
          else
            [[params[:per_page].to_i, 1].max, 100].min
          end
        )

      status = params[:status].presence || "active"
      if status != "active" && AtcpCase::STATUSES.exclude?(status)
        return(
          render_json_error(
            I18n.t("atcp_case.errors.invalid_status"),
            status: 422
          )
        )
      end

      base_scope = filtered_scope
      return if base_scope.nil?

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
      atcp_case = case_scope.find_by(id: params[:id])
      raise Discourse::NotFound if atcp_case.nil?

      render json: {
               case: AtcpCaseSerializer.new(atcp_case, root: false).as_json
             }
    end

    def form_options
      render json: {
               case_types: AtcpCase::CASE_TYPES,
               severities: AtcpCase::SEVERITIES,
               statuses: AtcpCase::STATUSES,
               close_reasons: AtcpCase::CLOSE_REASONS,
               frequencies: AtcpCase::FREQUENCIES,
               reproducibilities: AtcpCase::REPRODUCIBILITIES,
               update_labels: SiteSetting.atcp_case_update_labels.split("|"),
               branches: form_option_branches,
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
      if errors.any?
        return render json: { errors: errors }, status: :unprocessable_entity
      end

      atcp_case = nil
      ActiveRecord::Base.transaction do
        attrs = {
          title: title_param,
          case_type: params[:case_type],
          severity: params[:severity],
          source: source_param,
          symptom: params[:symptom].to_s.strip,
          reporter_name: params[:reporter_name].presence,
          reporter_branch_id: reporter_branch&.id,
          reporter_branch_name: reporter_branch_label,
          assignee_id: assignee&.id,
          status: "Open",
          opened_at: Time.zone.now,
          created_by_id: current_user.id
        }
        atcp_case = AtcpCase.create_with_generated_number!(attrs)

        products.each do |product|
          AtcpCaseProduct.create!(
            case_id: atcp_case.id,
            product_id: product.id,
            product_name: product.name,
            sku_code: product.sku_code
          )
        end

        StaffActionLogger.new(current_user).log_custom(
          "atcp_case_created",
          details:
            "case_id: #{atcp_case.id}, case_number: #{atcp_case.case_number}"
        )
      end

      render json: {
               case:
                 AtcpCaseSerializer.new(
                   case_scope.find(atcp_case.id),
                   root: false
                 ).as_json
             }
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

    def filtered_scope
      scope = AtcpCase.all
      scope = scope.where(severity: params[:severity]) if params[
        :severity
      ].present?
      scope = scope.where(case_type: params[:case_type]) if params[
        :case_type
      ].present?
      if params[:product_id].present?
        scope =
          scope.joins(:atcp_case_products).where(
            atcp_case_products: {
              product_id: params[:product_id]
            }
          )
      end
      scope = scope.where(assignee_id: params[:assignee_id]) if params[
        :assignee_id
      ].present?

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

      scope = scope.where(opened_at: from.beginning_of_day..) if from
      scope = scope.where(opened_at: ..to.end_of_day) if to
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

    def form_option_branches
      AtcpBranch
        .where(status: "active")
        .order(:name)
        .map do |branch|
          {
            id: branch.id,
            name: branch.name,
            code: branch.code,
            label: "#{branch.name} (#{branch.code})"
          }
        end
    end

    def create_validation_errors
      errors = {}

      errors[:title] = [
        I18n.t("atcp_case.errors.title_required")
      ] if title_param.blank?

      if AtcpCase::CASE_TYPES.exclude?(params[:case_type].to_s)
        errors[:case_type] = [I18n.t("atcp_case.errors.case_type_invalid")]
      end

      if AtcpCase::SEVERITIES.exclude?(params[:severity].to_s)
        errors[:severity] = [I18n.t("atcp_case.errors.severity_invalid")]
      end

      if source_param.blank?
        errors[:source] = [I18n.t("atcp_case.errors.source_required")]
      elsif source_param.length > 255
        errors[:source] = [I18n.t("atcp_case.errors.source_too_long")]
      end

      if params[:symptom].to_s.strip.blank?
        errors[:symptom] = [I18n.t("atcp_case.errors.symptom_required")]
      end

      product_error = product_validation_error
      errors[:product_ids] = [product_error] if product_error

      if params[:reporter_branch_id].present? && reporter_branch.nil?
        errors[:reporter_branch_id] = [
          I18n.t("atcp_case.errors.reporter_branch_invalid")
        ]
      end

      if params[:assignee_id].present? && assignee.nil?
        errors[:assignee_id] = [I18n.t("atcp_case.errors.assignee_invalid")]
      end

      errors
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

    def reporter_branch
      return @reporter_branch if defined?(@reporter_branch)

      @reporter_branch =
        if params[:reporter_branch_id].blank?
          nil
        else
          AtcpBranch.where(status: "active").find_by(
            id: params[:reporter_branch_id]
          )
        end
    end

    def reporter_branch_label
      branch = reporter_branch
      "#{branch.name} (#{branch.code})" if branch
    end

    def assignee
      return @assignee if defined?(@assignee)

      @assignee =
        if params[:assignee_id].blank?
          nil
        else
          user = User.find_by(id: params[:assignee_id])
          user if user && !user.bot? && Atcp::InternalAccess.allowed?(user)
        end
    end
  end
end
