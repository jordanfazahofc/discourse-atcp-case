# frozen_string_literal: true

module AtcpCaseAttachmentUploads
  MAX_ATTACHMENTS = 20

  private

  def upload_id_params
    @upload_id_params ||=
      Array(params[:upload_ids])
        .map { |value| value.to_s.strip }
        .reject(&:blank?)
  end

  def validated_uploads
    uploads = []
    errors = []
    ids = upload_id_params

    if ids.size > MAX_ATTACHMENTS
      return [
        [],
        [I18n.t("atcp_case.errors.too_many_attachments", max: MAX_ATTACHMENTS)]
      ]
    end

    allowed_extensions =
      SiteSetting.atcp_case_attachment_extensions.split("|").map(&:downcase)
    max_bytes = SiteSetting.atcp_case_max_attachment_mb.to_i * 1024 * 1024

    ids.uniq.each do |raw|
      upload = raw.match?(/\A\d+\z/) ? Upload.find_by(id: raw.to_i) : nil

      if upload.nil?
        errors << I18n.t("atcp_case.errors.attachment_not_found", filename: raw)
        next
      end

      if upload.user_id != current_user.id
        errors << I18n.t(
          "atcp_case.errors.attachment_not_owned",
          filename: upload.original_filename
        )
        next
      end

      if AtcpCaseAttachment.with_deleted.exists?(upload_id: upload.id)
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
    @validated_uploads.map do |upload|
      update.atcp_case_attachments.create!(
        case_id: update.case_id,
        upload_id: upload.id
      )
    rescue ActiveRecord::RecordNotUnique
      raise AtcpCaseUpdateDuplicateAttachmentError, upload
    end
  end
end
