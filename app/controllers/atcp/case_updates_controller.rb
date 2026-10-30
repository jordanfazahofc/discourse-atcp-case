# frozen_string_literal: true

module Atcp
  class CaseUpdatesController < ::ApplicationController
    include Atcp::InternalAccessGuard
    include AtcpCaseAttachmentUploads
    requires_plugin "discourse-atcp-case"

    before_action :ensure_logged_in
    before_action :ensure_internal_access!

    rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid

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
                   scope: current_user.guardian,
                   root: false
                 ).as_json,
               status: atcp_case.reload.status
             }
    end

    def update
      atcp_case = find_case!
      entry = find_update!(atcp_case)
      raise Discourse::InvalidAccess unless entry.editable_by?(current_user)
      if atcp_case.status == "Closed"
        return render_errors(base_error("case_closed"))
      end

      if entry.initial_report && params.key?(:update_type) &&
           update_type_param != entry.update_type
        return(
          render_errors(
            update_type: [I18n.t("atcp_case.errors.initial_report_type_locked")]
          )
        )
      end

      return update_system_entry(atcp_case, entry) if entry.is_system

      errors = edit_validation_errors
      return render_errors(errors) if errors.any?

      # Semua raise ActiveRecord::Rollback harus terjadi sebelum penulisan.
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

            locked = atcp_case.atcp_case_updates.find(entry.id)
            current_attachments = locked.atcp_case_attachments.to_a
            remove_ids = remove_attachment_id_params
            numeric_remove_ids =
              remove_ids.filter_map { |id| id.to_i if id.match?(/\A\d+\z/) }
            invalid_remove_ids =
              remove_ids.reject { |id| id.match?(/\A\d+\z/) } +
                (numeric_remove_ids - current_attachments.map(&:id)).map(&:to_s)

            if invalid_remove_ids.any?
              locked_error = {
                remove_attachment_ids: [
                  I18n.t(
                    "atcp_case.errors.attachment_not_in_update",
                    ids: invalid_remove_ids.join(", ")
                  )
                ]
              }
              raise ActiveRecord::Rollback
            end

            attachments_to_remove =
              current_attachments.select do |attachment|
                numeric_remove_ids.include?(attachment.id)
              end
            remaining_attachments = current_attachments - attachments_to_remove

            if remaining_attachments.size + @validated_uploads.size >
                 MAX_ATTACHMENTS
              locked_error = {
                upload_ids: [
                  I18n.t(
                    "atcp_case.errors.too_many_attachments",
                    max: MAX_ATTACHMENTS
                  )
                ]
              }
              raise ActiveRecord::Rollback
            end

            current_body = normalize_body(locked.body)
            requested_body = params.key?(:body) ? body_param : current_body
            if requested_body.blank? && remaining_attachments.empty? &&
                 @validated_uploads.empty?
              locked_error = {
                body: [I18n.t("atcp_case.errors.update_body_required")]
              }
              raise ActiveRecord::Rollback
            end

            body_changed = params.key?(:body) && requested_body != current_body
            type_changed =
              params.key?(:update_type) &&
                update_type_param != locked.update_type
            attachments_changed =
              attachments_to_remove.any? || @validated_uploads.any?

            unless body_changed || type_changed || attachments_changed
              locked_error = base_error("update_edit_required")
              raise ActiveRecord::Rollback
            end

            previous_body = locked.body
            previous_update_type = locked.update_type

            locked.body = requested_body if params.key?(:body)
            locked.update_type = update_type_param if params.key?(:update_type)

            removed_attachments =
              attachments_to_remove.map do |attachment|
                {
                  "upload_id" => attachment.upload_id,
                  "filename" => attachment.upload.original_filename
                }
              end
            attachments_to_remove.each do |attachment|
              attachment.soft_delete!(current_user)
            end

            created_attachments = attach_uploads(locked)
            added_attachments =
              created_attachments.map do |attachment|
                {
                  "upload_id" => attachment.upload_id,
                  "filename" => attachment.upload.original_filename
                }
              end

            locked.edited_at = Time.zone.now
            details = locked.details || {}
            history = details["edit_history"] || []
            history_entry = {
              "edited_at" => locked.edited_at.iso8601,
              "edited_by_id" => current_user.id,
              "previous_body" => previous_body,
              "previous_update_type" => previous_update_type
            }
            if added_attachments.any?
              history_entry["added_attachments"] = added_attachments
            end
            if removed_attachments.any?
              history_entry["removed_attachments"] = removed_attachments
            end

            locked.details =
              details.merge("edit_history" => history + [history_entry])

            locked.save!

            edited_by_author = current_user.id == locked.user_id
            if removed_attachments.any? || !edited_by_author
              log_update_edited(
                atcp_case,
                locked,
                added_upload_ids:
                  added_attachments.map { |row| row["upload_id"] },
                removed_upload_ids:
                  removed_attachments.map { |row| row["upload_id"] },
                edited_by_author:
              )
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
                   entry.reload,
                   scope: current_user.guardian,
                   root: false
                 ).as_json
             }
    end

    def destroy
      atcp_case = find_case!
      entry = find_update!(atcp_case)
      if entry.initial_report && !current_user.admin?
        raise Discourse::InvalidAccess
      end
      raise Discourse::InvalidAccess unless entry.editable_by?(current_user)
      if atcp_case.status == "Closed"
        return render_errors(base_error("case_closed"))
      end

      locked_error = nil
      ActiveRecord::Base.transaction do
        atcp_case.with_lock do
          if atcp_case.status == "Closed"
            locked_error = base_error("case_closed")
            raise ActiveRecord::Rollback
          end

          locked = atcp_case.atcp_case_updates.find(entry.id)
          locked.soft_delete!(current_user)
        end
      end
      return render_errors(locked_error) if locked_error

      deleted_details = { case_id: atcp_case.id, update_id: entry.id }
      deleted_details[:system_event] = entry.system_event if entry.is_system
      StaffActionLogger.new(current_user).log_custom(
        "atcp_case_update_deleted",
        deleted_details
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

    def update_system_entry(atcp_case, entry)
      forbidden_keys = %w[update_type upload_ids remove_attachment_ids]
      if forbidden_keys.any? { |key| params.key?(key) }
        return render_errors(base_error("system_update_body_only"))
      end

      # Semua raise ActiveRecord::Rollback harus terjadi sebelum penulisan.
      locked_error = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        atcp_case.with_lock do
          if atcp_case.status == "Closed"
            locked_error = base_error("case_closed")
            raise ActiveRecord::Rollback
          end

          locked = atcp_case.atcp_case_updates.find(entry.id)
          current_body = normalize_body(locked.body)
          final_body = params.key?(:body) ? body_param : current_body
          if locked.system_event == "reopened" && final_body.blank?
            locked_error = {
              body: [I18n.t("atcp_case.errors.update_body_required")]
            }
            raise ActiveRecord::Rollback
          end
          if final_body == current_body
            locked_error = base_error("update_edit_required")
            raise ActiveRecord::Rollback
          end

          previous_body = locked.body
          edited_at = Time.zone.now
          details = locked.details || {}
          history = details["edit_history"] || []
          history_entry = {
            "edited_at" => edited_at.iso8601,
            "edited_by_id" => current_user.id,
            "previous_body" => previous_body
          }

          locked.body = final_body
          locked.edited_at = edited_at
          locked.details =
            details.merge("edit_history" => history + [history_entry])
          locked.save!

          edited_by_author = current_user.id == locked.user_id
          unless edited_by_author
            log_update_edited(
              atcp_case,
              locked,
              added_upload_ids: [],
              removed_upload_ids: [],
              edited_by_author:
            )
          end
        end
      end

      return render_errors(locked_error) if locked_error

      render json: {
               update:
                 AtcpCaseUpdateSerializer.new(
                   entry.reload,
                   scope: current_user.guardian,
                   root: false
                 ).as_json
             }
    end

    def log_update_edited(
      atcp_case,
      entry,
      added_upload_ids:,
      removed_upload_ids:,
      edited_by_author:
    )
      StaffActionLogger.new(current_user).log_custom(
        "atcp_case_update_edited",
        {
          case_id: atcp_case.id,
          update_id: entry.id,
          system_event: entry.system_event,
          added_upload_ids:,
          removed_upload_ids:,
          edited_by_author:
        }
      )
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

    def normalize_body(value)
      value.to_s.strip.presence
    end

    def body_param
      normalize_body(params[:body])
    end

    def status_param
      return nil unless params.key?(:status)

      params[:status].to_s.strip.presence
    end

    def update_type_param
      params[:update_type].to_s.strip
    end

    def remove_attachment_id_params
      Array(params[:remove_attachment_ids])
        .map { |value| value.to_s.strip }
        .reject(&:blank?)
        .uniq
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
      attachment_key =
        params.key?(:upload_ids) || params.key?(:remove_attachment_ids)

      if !params.key?(:body) && !type_key && !attachment_key
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

      @validated_uploads, @upload_errors = validated_uploads
      errors[:upload_ids] = @upload_errors if @upload_errors.any?

      errors
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
