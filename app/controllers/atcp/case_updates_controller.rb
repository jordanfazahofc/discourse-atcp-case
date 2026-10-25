# frozen_string_literal: true

module Atcp
  class CaseUpdatesController < ::ApplicationController
    include Atcp::InternalAccessGuard
    requires_plugin "discourse-atcp-case"

    before_action :ensure_logged_in
    before_action :ensure_internal_access!
    before_action :ensure_admin!, only: :destroy

    rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid

    MAX_ATTACHMENTS = 20

    def create
      atcp_case = find_case!
      if atcp_case.status == "Closed"
        return render_errors(base_error("case_closed"))
      end

      errors = create_validation_errors
      return render_errors(errors) if errors.any?

      update = nil
      locked_error = nil
      begin
        # Savepoint: unique violation meng-abort transaksi PG, dan
        # ActiveRecord::Rollback tidak memulihkannya (ditelan transaksi
        # joinable di dalam). Error khusus memaksa ROLLBACK TO SAVEPOINT.
        ActiveRecord::Base.transaction(requires_new: true) do
          atcp_case.with_lock do
            if atcp_case.status == "Closed"
              locked_error = base_error("case_closed")
              raise ActiveRecord::Rollback
            end

            previous_status = atcp_case.status

            update =
              atcp_case.atcp_case_updates.create!(
                user: current_user,
                is_system: false,
                update_type: update_type_param,
                body: body_param
              )

            attach_uploads(update)

            if status_param && status_param != previous_status
              create_status_update(atcp_case, previous_status, status_param)
              atcp_case.update!(status: status_param)
            end
          end
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

      return render_errors(locked_error) if locked_error

      render json: {
               update:
                 AtcpCaseUpdateSerializer.new(
                   update.reload,
                   root: false
                 ).as_json,
               status: atcp_case.reload.status
             }
    end

    def update
      atcp_case = find_case!
      entry = find_update!(atcp_case)
      if entry.is_system
        return render_errors(base_error("system_update_immutable"))
      end
      if atcp_case.status == "Closed"
        return render_errors(base_error("case_closed"))
      end

      errors = edit_validation_errors
      return render_errors(errors) if errors.any?

      locked_error = nil
      ActiveRecord::Base.transaction do
        atcp_case.with_lock do
          if atcp_case.status == "Closed"
            locked_error = base_error("case_closed")
            raise ActiveRecord::Rollback
          end

          locked = atcp_case.atcp_case_updates.find(entry.id)

          final_body = params.key?(:body) ? body_param : locked.body
          if final_body.blank? && !locked.atcp_case_attachments.exists?
            locked_error = {
              body: [I18n.t("atcp_case.errors.update_body_required")]
            }
            raise ActiveRecord::Rollback
          end

          previous_body = locked.body
          previous_update_type = locked.update_type

          locked.body = body_param if params.key?(:body)
          locked.update_type = update_type_param if params.key?(:update_type)

          locked.edited_at = Time.zone.now
          history = locked.details["edit_history"] || []
          locked.details =
            locked.details.merge(
              "edit_history" =>
                history +
                  [
                    {
                      "edited_at" => locked.edited_at.iso8601,
                      "edited_by_id" => current_user.id,
                      "previous_body" => previous_body,
                      "previous_update_type" => previous_update_type
                    }
                  ]
            )

          locked.save!
        end
      end
      return render_errors(locked_error) if locked_error

      render json: {
               update:
                 AtcpCaseUpdateSerializer.new(entry.reload, root: false).as_json
             }
    end

    def destroy
      atcp_case = find_case!
      entry = find_update!(atcp_case)
      if entry.is_system
        return render_errors(base_error("system_update_immutable"))
      end

      ActiveRecord::Base.transaction do
        atcp_case.with_lock do
          locked = atcp_case.atcp_case_updates.find(entry.id)
          locked.soft_delete!(current_user)
        end
      end

      StaffActionLogger.new(current_user).log_custom(
        "atcp_case_update_deleted",
        details: "case_id: #{atcp_case.id}, update_id: #{entry.id}"
      )

      head :no_content
    end

    private

    def find_case!
      AtcpCase.find_by(id: params[:case_id]) || raise(Discourse::NotFound)
    end

    def find_update!(atcp_case)
      atcp_case.atcp_case_updates.find_by(id: params[:id]) ||
        raise(Discourse::NotFound)
    end

    def ensure_admin!
      raise Discourse::InvalidAccess unless current_user.admin?
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

    def body_param
      params[:body].to_s.strip.presence
    end

    def status_param
      return nil unless params.key?(:status)

      params[:status].to_s.strip.presence
    end

    def update_type_param
      params[:update_type].to_s.strip
    end

    def upload_id_params
      @upload_id_params ||=
        Array(params[:upload_ids])
          .map { |value| value.to_s.strip }
          .reject(&:blank?)
    end

    def create_validation_errors
      errors = {}

      update_type = update_type_param
      if update_type.blank?
        errors[:update_type] = [I18n.t("atcp_case.errors.update_type_required")]
      elsif update_type.length > 100
        errors[:update_type] = [I18n.t("atcp_case.errors.update_type_too_long")]
      end

      @validated_uploads, @upload_errors = validated_uploads
      errors[:upload_ids] = @upload_errors if @upload_errors.any?

      if @upload_errors.empty? && @validated_uploads.empty? && body_param.blank?
        errors[:body] = [I18n.t("atcp_case.errors.update_body_required")]
      end

      if status_param &&
           (
             AtcpCase::STATUSES.exclude?(status_param) ||
               status_param == "Closed"
           )
        errors[:status] = [I18n.t("atcp_case.errors.status_invalid")]
      end

      errors
    end

    def edit_validation_errors
      errors = {}
      type_key = params.key?(:update_type)

      if !params.key?(:body) && !type_key
        return { base: [I18n.t("atcp_case.errors.update_edit_required")] }
      end

      if type_key
        update_type = update_type_param
        if update_type.blank?
          errors[:update_type] = [
            I18n.t("atcp_case.errors.update_type_required")
          ]
        elsif update_type.length > 100
          errors[:update_type] = [
            I18n.t("atcp_case.errors.update_type_too_long")
          ]
        end
      end

      errors
    end

    def validated_uploads
      uploads = []
      errors = []
      ids = upload_id_params

      if ids.size > MAX_ATTACHMENTS
        return [
          [],
          [
            I18n.t(
              "atcp_case.errors.too_many_attachments",
              max: MAX_ATTACHMENTS
            )
          ]
        ]
      end

      allowed_extensions =
        SiteSetting.atcp_case_attachment_extensions.split("|").map(&:downcase)
      max_bytes = SiteSetting.atcp_case_max_attachment_mb.to_i * 1024 * 1024

      ids.uniq.each do |raw|
        upload = raw.match?(/\A\d+\z/) ? Upload.find_by(id: raw.to_i) : nil

        if upload.nil?
          errors << I18n.t(
            "atcp_case.errors.attachment_not_found",
            filename: raw
          )
          next
        end

        if upload.user_id != current_user.id
          errors << I18n.t(
            "atcp_case.errors.attachment_not_owned",
            filename: upload.original_filename
          )
          next
        end

        if AtcpCaseAttachment.exists?(upload_id: upload.id)
          errors << I18n.t(
            "atcp_case.errors.attachment_already_used",
            filename: upload.original_filename
          )
          next
        end

        if allowed_extensions.exclude?(upload.extension.to_s.downcase)
          errors << I18n.t(
            "atcp_case.errors.attachment_extension_not_allowed",
            filename: upload.original_filename
          )
          next
        end

        if upload.filesize > max_bytes
          errors << I18n.t(
            "atcp_case.errors.attachment_too_large",
            filename: upload.original_filename,
            max_mb: SiteSetting.atcp_case_max_attachment_mb
          )
          next
        end

        uploads << upload
      end

      [uploads, errors]
    end

    def attach_uploads(update)
      @validated_uploads.each do |upload|
        update.atcp_case_attachments.create!(
          case_id: update.case_id,
          upload_id: upload.id
        )
      rescue ActiveRecord::RecordNotUnique
        raise AtcpCaseUpdateDuplicateAttachmentError, upload
      end
    end

    def create_status_update(atcp_case, from_value, to_value)
      atcp_case.atcp_case_updates.create!(
        user: current_user,
        is_system: true,
        update_type: nil,
        system_event: "status_changed",
        from_value: from_value,
        to_value: to_value
      )
    end
  end
end
