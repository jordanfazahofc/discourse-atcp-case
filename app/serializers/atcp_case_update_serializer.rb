# frozen_string_literal: true

class AtcpCaseUpdateSerializer < ApplicationSerializer
  attributes :id,
             :update_type,
             :body,
             :is_system,
             :system_event,
             :from_value,
             :to_value,
             :details,
             :edited_at,
             :created_at,
             :user,
             :attachments,
             :initial_report,
             :can_edit,
             :can_delete

  def user
    author = object.user
    { id: author.id, username: author.username, name: author.name }
  end

  def attachments
    object.atcp_case_attachments.map do |attachment|
      upload = attachment.upload
      {
        id: attachment.id,
        upload_id: upload.id,
        url: upload.url,
        original_filename: upload.original_filename,
        human_filesize: upload.human_filesize,
        is_image: FileHelper.is_supported_image?("image.#{upload.extension}")
      }
    end
  end

  def can_edit
    object.editable_by?(scope&.user)
  end

  def can_delete
    if object.initial_report
      scope&.user&.admin? || false
    else
      object.editable_by?(scope&.user)
    end
  end
end
