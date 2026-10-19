# frozen_string_literal: true

# Lampiran kasus dari anggota Internal memakai allowlist ekstensi dan batas
# ukuran dari setting plugin kasus, tanpa mengubah setting upload global.
# Plugin kasus dimuat SEBELUM core, jadi modul ditulis bersarang (bukan
# `module Atcp::X`) dan gate InternalAccess diperiksa saat request dengan
# fail-closed bila core belum tersedia.
module Atcp
  module CaseUploadPatch
    CASE_ATTACHMENT_TYPE = "atcp-case-attachment"

    def create_for(user_id)
      Thread.current[:atcp_case_upload] = true if case_attachment_for_internal?(
        user_id
      )
      super
    ensure
      Thread.current[:atcp_case_upload] = nil
    end

    private

    def case_attachment_for_internal?(user_id)
      return false if @opts[:type] != CASE_ATTACHMENT_TYPE
      return false if user_id.blank?
      return false unless defined?(::Atcp::InternalAccess)

      user = User.find_by(id: user_id)
      return false if user.nil?

      ::Atcp::InternalAccess.allowed?(user)
    rescue StandardError
      false
    end
  end
end
